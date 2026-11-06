# Third-party software

This project invokes the separately downloaded `wx` executable from
[thisnick/agent-wechat](https://github.com/thisnick/agent-wechat), pinned to v1.5.1.
The executable, upstream sources, credentials and profiles are not included here.

Agent WeChat's original code is MIT licensed, copyright 2026 Nick Yu and contributors.
Its bundled third-party components retain their own licenses; consult the
[upstream license](https://github.com/thisnick/agent-wechat/blob/v1.5.1/LICENSE)
and the release's `wx-v1.5.1-THIRD-PARTY-NOTICES.txt` before redistribution.

The Windows launcher in this repository uses documented Windows token/process APIs.
It does not add privileges, implement the WeChat protocol, inject code into the
official client, or distribute the official client.
