import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import watch_files as watcher


class ArchiveIntegrityTests(unittest.TestCase):
    def test_windows_names_stay_inside_destination(self):
        for name in ['../../outside.txt', 'C:\\private\\secret.txt', 'CON', 'NUL.txt', 'x\x00.pdf', '..']:
            clean = watcher.safe_name(name)
            self.assertNotIn('/', clean)
            self.assertNotIn('\\', clean)
            self.assertNotIn(':', clean)
            self.assertNotIn(clean.split('.')[0].upper(), {'CON', 'NUL'})
            self.assertNotIn(clean, {'', '.', '..'})

    def check_download(self, corrupt):
        with tempfile.TemporaryDirectory() as directory:
            data = b'verified attachment bytes'
            digest = hashlib.sha256(data).hexdigest()
            cfg = {'output': directory, 'groups': {'room': 'group'}, 'wx': 'fake',
                   'client_config': 'fake', 'data_dir': 'fake', 'server': 'fake', 'account': 'fake'}
            def read_api(cfg, path):
                if path.endswith('/media'):
                    return {'items': [{'kind': 'file', 'filename': '../../report.txt', 'sha256': digest}]}
                return {'threadId': 'room', 'type': 49, 'appMessageType': 6}
            def execute(command, **kwargs):
                path = Path(command[command.index('--output') + 1])
                path.write_bytes(b'corrupt' if corrupt else data)
                class Result:
                    returncode = 0
                    stdout = json.dumps({'state': 'available', 'sha256': digest, 'byteLength': len(data)})
                return Result()
            with patch.object(watcher, 'api', side_effect=read_api), patch.object(watcher.subprocess, 'run', side_effect=execute), patch.object(watcher.subprocess, 'CREATE_NO_WINDOW', 0, create=True):
                entry = {'thread': 'room', 'seen': 0}
                if corrupt:
                    with self.assertRaisesRegex(RuntimeError, 'integrity'):
                        watcher.download(cfg, 'message', entry)
                else:
                    receipt = watcher.download(cfg, 'message', entry)
                    self.assertEqual(receipt['state'], 'saved')
                    self.assertTrue(Path(receipt['path']).is_relative_to(Path(directory)))
                    with patch.object(watcher.subprocess, 'run', side_effect=AssertionError('must not download twice')):
                        self.assertEqual(watcher.download(cfg, 'message', entry)['sha256'], digest)

    def test_corrupt_download_is_rejected(self):
        self.check_download(True)

    def test_completed_download_recovers_without_overwrite(self):
        self.check_download(False)


if __name__ == '__main__':
    unittest.main()
