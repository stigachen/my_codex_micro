# MicroKeys

把 OpenAI **Codex Micro** 键盘上的任意按键映射成系统快捷键的常驻小应用，macOS 菜单栏版和 Windows 托盘版共用一份配置。
和 ChatGPT / Codex 桌面端**并存**：键盘照常配合 Codex 使用，多出来的几个键交给 MicroKeys。

典型用法：语音键 → 按住 `右Ctrl + 右Shift`，给 Wispr Flow / Superwhisper 这类按住说话的听写软件用。

```json
{ "bindings": { "MIC": { "mode": "hold", "keys": "rctrl+rshift" } } }
```

**配置说明见 [docs/CONFIG.md](docs/CONFIG.md)。**

## 原理

Codex Micro 的按键不发标准键盘扫描码，所有输入都通过一条厂商 HID 通道（Report ID 6）以 JSON-RPC 的形式发出，
协议由 [freemicro](https://github.com/eliBenven/freemicro) 项目逆向并验证。MicroKeys 用 IOKit 以**共享方式**打开设备，
只读事件、从不写灯光，因此和 ChatGPT 桌面端互不干扰；收到按键后用 CGEvent 合成系统按键。

```
Codex Micro ──HID(Report 6, JSON)──▶ PadMonitor ──▶ FrameDecoder ──▶ Mapper ──▶ CGKeySynthesizer ──▶ 系统
                                      (IOKit)                        (config.json)   (CGEvent)
```

* `macos/Sources/MicroKeysCore/` 纯逻辑，无 AppKit 依赖，有单元测试：帧解码、快捷键语法、配置解析、映射规则。
* `macos/Sources/MicroKeys/` 应用：HID 监听（IOKit）、按键合成（CGEvent）、权限、菜单栏。
* `windows/MicroKeys.Core/` 同一套逻辑的 C# 版，测试在任何系统上都能跑。
* `windows/MicroKeys/` 托盘应用：HID 监听（HidSharp）、按键合成（SendInput）、托盘菜单。
* `docs/`、`config.example.json`、`VERSION` 在仓库根目录，各平台共用。

根目录的 `make test` 跑两个平台的测试；其余目标转发到 `macos/`，Windows 的用 `make windows-test` / `make windows-publish`。

## 构建与安装

只需要 Xcode Command Line Tools（`xcode-select --install`），不需要完整 Xcode。macOS 13 及以上。

```sh
make icon        # 从 Resources/icon-source.png 重新生成 AppIcon.icns
make test        # 单元测试（含一百万事件的内存压力测试）
make app         # 生成 build/MicroKeys.app（临时签名）
make perf        # 启动应用跑一分钟，检查内存、CPU 和 leaks，发布前跑
make install     # 复制到 /Applications 并启动
```

首次启动会：

1. 在 `~/.config/microkeys/config.json` 生成示例配置；
2. 弹出两个系统权限请求。**两个都必须给**，在「系统设置 → 隐私与安全性」里：
   * **输入监控**：读取键盘。没有它设备根本打不开。
   * **辅助功能**：发出合成按键。没有它系统会静默丢弃。

授权后不需要重启，菜单栏图标会从灰色变成正常。

### 让权限在重新编译后保留

macOS 把权限绑定在应用的代码签名上。临时签名（ad-hoc）每次编译都不同，所以每次 `make app` 之后都要重新授权。
一次性解决：在「钥匙串访问 → 证书助理 → 创建证书」里建一张类型为「代码签名」、名字随意（比如 `MicroKeys Dev`）的自签名证书，然后：

```sh
SIGN_IDENTITY="MicroKeys Dev" make app
```

私钥只在建证书的这台 Mac 上。换机器构建要先在钥匙串访问里把证书连同私钥导出为 `.p12` 带过去，否则签名身份会变。

## 发布给别人

```sh
SIGN_IDENTITY="MicroKeys Dev" make release
```

产物在 `dist/`：`MicroKeys-<版本>.dmg`、同内容的 `.zip`，以及 `SHA256SUMS.txt`。应用用指定证书签名并开启 hardened runtime。

**自签名证书**能让权限跨版本保留，但 Gatekeeper 不认。收到 dmg 的人第一次打开会被拦，两种放行方式任选：

* 打开被拦后，去「系统设置 → 隐私与安全性」，页面下方点「仍要打开」；
* 或在终端执行 `xattr -dr com.apple.quarantine /Applications/MicroKeys.app`。

之后就和正常应用一样，升级也不用再授权。

**Developer ID 证书**可以进一步公证，收到的人双击即开，没有任何提示。先用
`xcrun notarytool store-credentials "MicroKeys" --apple-id … --team-id …` 存好凭据，然后：

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="MicroKeys" make release
```

脚本会签名、提交公证、等待结果、staple，再打包。

也可以在 GitHub Actions 上出包：把 `VERSION` 改成新版本号并提交，再推送同名的 tag（如 `v0.3.0`），就会自动签名、打包并创建 Release；合并 PR 不会触发。

签名的完整说明，包括自签名证书的创建与迁移、Developer ID 的申请步骤、公证凭据、GitHub Actions 配置、常见问题：
**[docs/SIGNING.md](docs/SIGNING.md)**。

## Windows 版

Windows 10/11，x64 或 Arm64。从 Release 下载对应的 zip，解压后运行 `MicroKeys.exe` 即可，不需要安装 .NET，也不需要任何权限。
未签名，SmartScreen 第一次会提示，点「更多信息 → 仍要运行」。托盘图标右键有和 macOS 版相同的菜单，含「开机自动启动」。

命令行诊断和 macOS 版一致：`MicroKeys.exe --detect`、`--dump-pad 20`、`--dump-events 20`、`--test-shortcut "rctrl+rshift"`、`--check-config`。

从源码构建只需要 .NET 10 SDK，在 macOS 或 Linux 上也能交叉编译：

```sh
make windows-test       # Core 单元测试
make windows-publish    # windows/dist/MicroKeys-<版本>-win-x64.zip 和 win-arm64.zip
```

## 菜单栏

点图标可以看到：键盘连接状态与传输方式（USB / 蓝牙）、两个权限的状态（点击直达设置页）、当前所有绑定、
**最近按键**（用来查某个物理键的 id）、最近触发的快捷键、打开配置 / 文档 / 日志、语言、开机自启、退出。

界面支持简体中文和 English。默认跟随系统语言，在「语言 / Language」子菜单里选定后会记住，下次启动仍然生效。
配置错误提示、命令行输出也随语言切换。英文版配置说明见 [docs/CONFIG.en.md](docs/CONFIG.en.md)。

## 命令行

```sh
MicroKeys --check-config                      # 校验配置并列出绑定
MicroKeys --test-shortcut "rctrl+rshift" 800  # 3 秒后合成一次快捷键，验证目标应用是否响应
MicroKeys --dump-pad 20                       # 打印 20 秒内键盘发出的原始按键 id，查哪个开关是 ACT10 / ACT11
MicroKeys --dump-events 20                    # 打印 20 秒内系统投递的键盘事件，诊断用
MicroKeys --detect                            # 列出接在本机的 Work Louder 键盘及其通道信息
MicroKeys --uninstall                         # 清除配置、日志、偏好、开机自启，见「卸载」
MicroKeys --version
```

（可执行文件在 `MicroKeys.app/Contents/MacOS/MicroKeys`。）

## 和 ChatGPT 共存的注意事项

ChatGPT 仍会响应你映射的键（出厂 ACT 键分别是快速模式 / 同意 / 拒绝 / 分叉 / 按住说话 / 发送）。
要让某个键只属于 MicroKeys，在 ChatGPT 的 Codex Micro 设置里把该槽位换成空白键帽 EMPT1～EMPT5 且不绑命令。
细节见 [docs/CONFIG.md 第 6 节](docs/CONFIG.md#6-和-chatgpt--codex-桌面应用共存)。

## 其他 Work Louder 键盘（Creator Micro 2）

Codex Micro 就是 Work Louder Creator Micro 2 的机身加 Codex 固件，官方说 CM2 同样用 Input 软件配置而不是 QMK/VIA，
大概率走同一条厂商 HID 通道，但**没有实机验证过**。MicroKeys 会接管任何乐鑫 VID（0x303A）下厂商名为 Work Louder 的设备。
插上后先运行：

```sh
MicroKeys --detect
```

它会列出设备的 VID/PID、连接方式，以及报告描述符里有没有厂商通道（0xFF00）。有厂商通道就值得一试；
按键后菜单里「最近按键」有显示，就是兼容的。

## 资源占用

常驻程序，所以专门测过（Apple Silicon，macOS 26，release 构建）：

| 指标 | 数值 |
|---|---|
| 空闲内存（RSS） | 约 42 MB，运行数分钟不变 |
| 空闲 CPU | 一分钟累计 0.1 秒左右，即约 0.1%，来自每秒一次的配置文件 stat 和每 3 秒一次的权限检查 |
| 一百万个按键事件 | 常驻内存增长 0（`StressTests`，每次 `make test` 都跑） |
| `leaks` 工具 | 288 个对象、14 KB，全部是系统框架启动时的 XPC 连接，数分钟内不增长 |

两道回归防线：`make test` 里的 `StressTests` 断言一百万事件后常驻内存增长小于 4 MB；`make perf` 启动真实的 .app
跑一分钟（`DURATION=300` 可加长），常驻内存超过 80 MB、期间增长超过 5 MB、平均 CPU 超过 1%、或 `leaks` 数量增加，都会失败。

设计上没有会随时间累积的东西：按键不写日志，帧缓冲上限 8 KB，菜单只在打开时构建，
事件解析在自己的 autoreleasepool 里完成，所以即使一次回调里连续来几十个报告也不会堆积。

## 卸载

两个平台都有一条命令把应用自己创建的东西清干净，会先列出清单再确认（加 `--yes` 跳过确认）：

```sh
# macOS
/Applications/MicroKeys.app/Contents/MacOS/MicroKeys --uninstall
# Windows
MicroKeys.exe --uninstall
```

它会退出正在运行的实例，然后删除下面这些：

| | macOS | Windows |
|---|---|---|
| 配置 | `~/.config/microkeys/` | `%APPDATA%\MicroKeys\` |
| 日志 | `~/Library/Logs/MicroKeys.log` | `%LOCALAPPDATA%\MicroKeys\` |
| 语言等偏好 | `~/Library/Preferences/com.chenguang.MicroKeys.plist` | 注册表 `HKCU\Software\MicroKeys` |
| 开机自启 | 登录项 | 注册表 `HKCU\…\CurrentVersion\Run` 的 `MicroKeys` |
| 运行时缓存 | 无 | `%TEMP%\.net\MicroKeys\` |

命令跑完会打印剩下需要你手动做的：删除程序本身（macOS 的 `.app`，Windows 的 `.exe`）；macOS 上还要去
「系统设置 → 隐私与安全性」的「输入监控」和「辅助功能」里移除 MicroKeys 那一行，这是系统的权限记录，
任何应用都无法替用户撤销，留着也无害。

不做的事：两个平台都不写系统目录，不装服务、守护进程、驱动或计划任务。

## 已知限制

* Windows 版 2026-09-13 在一台 x64 机器上验证通过（USB 连接，语音键映射）；Arm64 版只经过交叉编译，未实测。
* 摇杆与左下角触控板不可绑定。
* 不支持媒体键（音量、播放）。想用旋钮调音量之类的系统功能，把它映射成一个空闲快捷键，再在 Raycast 等软件里把该快捷键指到对应动作。
* macOS 上合成的方向键、Home/End/PageUp/PageDown、F 键不带真实键盘会附加的 fn / 小键盘标志位，因此按标志位比对热键的软件（已确认 Raycast）认不出它们，字母、数字、Escape 等键不受影响。临时办法：把热键改成字母或数字。待修。
* 少数直接读底层 HID 的应用看不到合成按键。
* 目前只验证了固件 v0.4.1 的协议（来自 freemicro 的实测记录）。

## 致谢与许可

设备协议、按键 id、出厂布局等事实来自 [freemicro](https://github.com/eliBenven/freemicro)（MIT）。
MicroKeys 是独立实现，MIT 许可。"Codex"、"Codex Micro"、"OpenAI" 是 OpenAI 的商标，此处仅用于说明兼容性。
