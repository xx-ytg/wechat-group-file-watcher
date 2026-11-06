"""Archive new ordinary files from configured groups through a local wx API."""
import argparse
import hashlib
import json
import logging
import msvcrt
import os
from pathlib import Path
import re
import subprocess
import time
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
CFG = ROOT / 'watch-config.json'
STATE = ROOT / 'watch-state.json'


def safe_name(value):
    value = re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', value).strip(' .')
    value = value[:150] or 'attachment'
    if value.split('.')[0].upper() in {'CON', 'PRN', 'AUX', 'NUL', *(f'COM{i}' for i in range(1, 10)), *(f'LPT{i}' for i in range(1, 10))}:
        value = '_' + value
    return value


def save_state(state):
    temp = STATE.with_suffix('.tmp')
    with temp.open('w', encoding='utf-8') as stream:
        json.dump(state, stream, ensure_ascii=False, indent=2)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, STATE)


def api(cfg, path, **query):
    token = Path(cfg['data_dir'], 'api-token').read_text(encoding='utf-8').strip()
    url = cfg['server'] + '/v1/accounts/' + quote(cfg['account'], safe='') + path
    if query:
        url += '?' + urlencode(query)
    req = Request(url, headers={'Authorization': 'Bearer ' + token})
    with urlopen(req, timeout=20) as response:
        return json.load(response)


def bootstrap(cfg):
    status = api(cfg, '')
    if not status.get('authenticated') or status.get('connection') != 'online':
        raise RuntimeError('Account is not online; refusing to initialize watcher')
    cursor = '0'
    while True:
        page = api(cfg, '/events', after=cursor, limit=200)
        cursor = page['nextCursor']
        if len(page['items']) < 200:
            break
    state = {'cursor': cursor, 'pending': {}, 'saved': {}, 'started_at': time.time()}
    save_state(state)
    logging.info('Initialized at cursor %s; old events skipped', cursor)
    return state


def download(cfg, message_id, entry):
    encoded = quote(message_id, safe='')
    message = api(cfg, '/messages/' + encoded)
    if message['threadId'] != entry['thread']:
        raise RuntimeError('Message/group identity mismatch')
    # A WeChat ordinary document is app-message subtype 6. Images/videos ignored.
    if message.get('type') != 49 or message.get('appMessageType') != 6:
        return {'state': 'ignored'}
    media = api(cfg, '/messages/' + encoded + '/media')['items']
    files = [asset for asset in media if asset.get('kind') == 'file']
    if not files:
        raise RuntimeError('File metadata not available yet')
    asset = files[0]
    if asset.get('state') in {'expired', 'unsupported'}:
        return {'state': asset['state']}
    destination = Path(cfg['output']) / safe_name(cfg['groups'][entry['thread']]) / time.strftime('%Y-%m-%d', time.localtime(entry['seen']))
    destination.mkdir(parents=True, exist_ok=True)
    key = hashlib.sha256(message_id.encode()).hexdigest()[:16]
    output = destination / (key + '__' + safe_name(asset.get('filename') or 'attachment'))
    # Recover a successful download if the process stopped before saving state.
    if output.exists():
        expected = asset.get('sha256')
        with output.open('rb') as stream:
            actual = hashlib.file_digest(stream, 'sha256').hexdigest()
        if not expected or actual != expected:
            raise RuntimeError('Existing output cannot be verified; refusing overwrite')
        return {'state': 'saved', 'path': str(output), 'sha256': actual}
    command = [cfg['wx'], '--config', cfg['client_config'], '--data-dir', cfg['data_dir'],
               '--server', cfg['server'], '--account', cfg['account'], '--json',
               'messages', 'media', entry['thread'], message_id, '--output', str(output), '--wait', '30']
    result = subprocess.run(command, capture_output=True, encoding='utf-8', timeout=90,
                            creationflags=subprocess.CREATE_NO_WINDOW)
    if result.returncode:
        # Do not log raw protocol messages, XML, keys or credentials.
        raise RuntimeError('Attachment command failed, exit=' + str(result.returncode))
    reply = json.loads(result.stdout)
    if reply.get('state') in {'expired', 'unsupported'}:
        return {'state': reply['state']}
    if reply.get('state') != 'available' or not output.is_file():
        raise RuntimeError('Transfer pending or unavailable')
    with output.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    if reply.get('sha256') != digest or reply.get('byteLength') != output.stat().st_size:
        raise RuntimeError('Downloaded file failed integrity verification')
    return {'state': 'saved', 'path': str(output), 'sha256': digest}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--initialize', action='store_true')
    parser.add_argument('--once', action='store_true')
    args = parser.parse_args()
    logging.basicConfig(filename=ROOT / 'watch.log', level=logging.INFO,
                        format='%(asctime)s %(levelname)s %(message)s', encoding='utf-8')
    with (ROOT / 'watch.lock').open('a+b') as lock:
        lock.seek(0)
        if not lock.read(1):
            lock.write(b'0'); lock.flush()
        lock.seek(0)
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        cfg = json.loads(CFG.read_text(encoding='utf-8-sig'))
        state = json.loads(STATE.read_text(encoding='utf-8')) if STATE.exists() else bootstrap(cfg)
        if args.initialize:
            print(json.dumps({'cursor': state['cursor'], 'pending': len(state['pending'])}))
            return
        logging.info('Watcher running for %d configured group(s)', len(cfg['groups']))
        while True:
            try:
                page = api(cfg, '/events', after=state['cursor'], limit=200)
                for event in page['items']:
                    data = event.get('data', {})
                    mid = data.get('messageId')
                    if event['kind'] == 'message.committed' and data.get('threadId') in cfg['groups'] and mid and mid not in state['saved']:
                        state['pending'].setdefault(mid, {'thread': data['threadId'], 'seen': time.time(), 'attempts': 0, 'next': 0})
                state['cursor'] = page['nextCursor']
                # Commit queued work with its cursor before attempting downloads.
                save_state(state)
                for mid, entry in list(state['pending'].items()):
                    if entry['next'] > time.time():
                        continue
                    try:
                        receipt = download(cfg, mid, entry)
                        if receipt['state'] in {'expired', 'unsupported'}:
                            logging.warning('File unavailable: %s %s', mid, receipt['state'])
                        elif receipt['state'] == 'saved':
                            logging.info('File saved: %s', receipt['path'])
                        state['saved'][mid] = receipt
                        del state['pending'][mid]
                    except Exception as error:
                        entry['attempts'] += 1
                        entry['next'] = time.time() + min(300, 5 * 2 ** min(entry['attempts'], 6))
                        logging.warning('Download pending: %s (%s)', mid, type(error).__name__)
                    save_state(state)
            except Exception as error:
                logging.warning('Poll failed (%s); keeping cursor', type(error).__name__)
            if args.once:
                return
            time.sleep(2)


if __name__ == '__main__':
    main()
