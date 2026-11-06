# WeChat Group File Watcher

Windows 下指定微信群的新文件自动归档脚本。通过本机 [agent-wechat](https://github.com/thisnick/agent-wechat) 接口接收新消息，筛选群 ID，下载普通文件并验证大小和 SHA-256。

## 功能

- 同时监听配置中的多个群，保存到 `downloads/群名/YYYY-MM-DD/`。
- 首次启动跳过已有事件，只处理此后到达的新消息。
- 事件进度与待下载任务一起落盘，失败重试，重启后继续。
- 消息标识摘要作为文件名前缀，避免同名覆盖；已完成文件可校验恢复。
- Windows 隐藏进程运行，提供启动和停止脚本；不依赖桌面微信的 UI Automation。
- 仅保存普通附件；不保存图片/视频，不自动回复，不设置开机自启。

## 环境

Windows x64、Python 3.11+（含 `py` 启动器），管理员 PowerShell。Python 部分仅使用标准库，无需安装第三方 Python 包。

依赖非官方开源客户端 agent-wechat **v1.5.1**。安装脚本下载其独立 Windows 程序并校验固定 SHA-256，不打包或修改官方微信。使用需要手机扫码确认一个独立客户端会话；请自行评估非官方客户端的账号兼容性。

## 安装与登录

下载本仓库，在管理员 PowerShell 中进入项目目录：

```powershell
.\Setup.ps1
.\Login.ps1
```

按终端提示打开二维码 PNG，用手机微信扫码并确认。二维码过期可重新运行 `Login.ps1`。不要分享二维码或 `runtime/` 目录。

查询你要监听的群：

```powershell
.\Find-Group.ps1 -Name '示例群'
```

从结果中确认准确的群 ID，在安装后生成的 `watch-config.json` 里修改 `groups`。同名群需要核对 ID：

```json
"groups": {
  "FIRST_GROUP_ID@chatroom": "示例群一",
  "SECOND_GROUP_ID@chatroom": "示例群二"
}
```

其余路径由安装脚本按当前机器生成，`watch-config.example.json` 仅展示结构。`account` 由登录脚本填入。

## 运行

```powershell
.\Start-Watcher.ps1
Get-Content .\watch.log -Tail 20
# 停止监听及本机接口服务
.\Stop-Watcher.ps1
```

首次运行必须在登录在线后初始化；如果过早启动，登录完成后重新运行启动脚本。运行时不要编辑进度文件。修改群配置后重启监听；切换账号请先停止，并备份、移走旧的 `watch-state.json`，避免沿用其他账号的游标。

默认接口地址为 `127.0.0.1:18766`；该端口须未被其他服务占用。启动脚本仅支持本地接口。重启电脑后需手动启动，微信会话失效后需重新扫码。

## Windows 文件所有者处理

在部分管理员环境中，SQLite 新建的 WAL/SHM 文件默认归 Administrators 组所有，而上游客户端要求它们属于当前用户，导致 HTTP 500。

`scripts/Start-PrivateProcess.ps1` 复制当前用户的进程令牌，只将子进程默认文件所有者设为当前用户；身份和权限不变，不修改系统策略。使用者需要有调用相应 Windows 进程 API 的权限。

## 数据与边界

`runtime/` 包含登录凭据；`watch-config.json` 包含本机路径、账号和群信息；`watch-state.json`、日志及下载文件也属于本地数据。这些路径已加入 `.gitignore`，公开仓库只提供占位示例。

上游下载普通文件的上限为 512 MiB。过期、撤回或不支持的附件可能无法下载。网络中断会重试，但永久错误也可能持续重试，应查看日志。依赖本机开机与网络；睡眠恢复、长期锁屏和大文件尚未实测。下载命令单次超时为 90 秒，大文件可能需要后续重试。

目前已在一台 Windows x64 机器上实测：手机扫码登录、指定群推送、一个 PDF 自动保存与 SHA-256 校验、服务重启后进度恢复。此证据不代表所有账号、微信版本及附件格式均可用。Setup/Login 的通用安装流程通过语法检查，但尚未在第二台干净机器上验证。

## 测试

```powershell
python -m unittest discover -s tests -v
```

测试覆盖 Windows 文件名与路径处理、损坏文件拒绝、完成任务恢复时不重复下载。GitHub Actions 在 Windows 上运行这些测试及 PowerShell 语法检查，不连接真实微信账号。

## 许可

本仓库原创脚本使用 MIT 许可证。上游 agent-wechat 由其作者维护并按其自身许可证发布；本项目不隶属于腾讯或微信。详见 [第三方说明](THIRD_PARTY_NOTICES.md)。
