# MicroKeys 配置说明

MicroKeys 用一个 JSON 文件描述「Codex Micro 上的哪个键 → 系统的哪个快捷键」。
文件保存后会自动重新加载，不需要重启应用；写错了会在菜单栏里直接显示错误原因。

## 1. 配置文件在哪

默认路径：

| 系统 | 配置文件 | 日志 |
|---|---|---|
| macOS | `~/.config/microkeys/config.json` | `~/Library/Logs/MicroKeys.log` |
| Windows | `%APPDATA%\MicroKeys\config.json` | `%LOCALAPPDATA%\MicroKeys\MicroKeys.log` |

* 第一次启动时会自动生成一份示例配置（内容和仓库里的 `config.example.json` 一样）。
* 菜单栏 / 托盘图标 → 「打开配置文件…」会用系统默认编辑器打开它。
* 想换位置：启动前设置环境变量 `MICROKEYS_CONFIG=/你的/路径.json`。

**同一份配置文件在两个系统上都能用**，按键 id 和快捷键写法完全一致，差异只有第 5 节末尾列出的几处。

## 2. 最小示例

把语音键（出厂时印着话筒图标的双宽键）映射成「按住右 Ctrl + 右 Shift」：

```json
{
  "version": 1,
  "bindings": {
    "MIC": { "mode": "hold", "keys": "rctrl+rshift" }
  }
}
```

按下语音键时 MicroKeys 按下右 Ctrl 和右 Shift 并一直按住；松开语音键时再松开它们。
这正是 Wispr Flow、Superwhisper、macOS 听写这类「按住说话」应用需要的行为。

## 3. 文件结构

```json
{
  "version": 1,
  "_comment": "任意说明文字，以下划线开头的字段都会被忽略",

  "options": {
    "key_interval_ms": 30
  },

  "bindings": {
    "<按键 id>": "<快捷键>",
    "<按键 id>": { "mode": "tap" | "hold", "keys": "<快捷键>" }
  }
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `version` | 否 | 目前只能是 `1`，省略也可以 |
| `options.key_interval_ms` | 否 | 同一个快捷键内部各个按下/抬起事件之间的间隔，毫秒，默认 `30`。**不要设成 0**：Typeless 等听写软件会忽略事件紧挨着到达的组合键，实测 30 可用。想降低延迟可以试 10～20 |
| `bindings` | 是 | 按键 id 到快捷键的映射，可以为空 |
| 任何以 `_` 开头的字段 | 否 | 注释，随便写 |

JSON 本身不支持 `//` 注释，想写备注就用 `"_comment": "..."`。

### 每个绑定的两种写法

**简写**：直接给快捷键字符串，等价于单击（`tap`）模式。

```json
"ACT06": "cmd+shift+4"
```

**完整写法**：对象，可以指定模式。

```json
"ACT06": { "mode": "tap", "keys": "cmd+shift+4", "_comment": "截图" }
```

### 两种模式

| mode | 行为 | 适合 |
|---|---|---|
| `tap`（默认） | 键按下的瞬间，把快捷键按一下就松开 | 绝大多数快捷键：截图、切换应用、打开某个面板 |
| `hold` | 键按下时按下快捷键，键松开时才松开 | 按住说话、按住临时显示某个窗口、把某个键当修饰键用 |

旋钮的转动（`ENC_CW` / `ENC_CC`）没有「松开」事件，所以只能用 `tap`，写 `hold` 会报错。

## 4. 按键 id

键盘的物理布局和对应的 id：

```
第 1 行：  [ ◯ 旋钮 ]   [ AG00 ]  [ AG01 ]  [ ● 摇杆 ]
第 2 行：  [ AG02 ]     [ AG03 ]  [ AG04 ]  [ AG05 ]
第 3 行：  [ ACT06 ]    [ ACT07 ] [ ACT08 ] [ ACT09 ]
第 4 行：  [ ◉ 触控板 ] [ ══ ACT10 + ACT11 ══ ] [ ACT12 ]
```

| id | 是什么 | 出厂键帽 | 备注 |
|---|---|---|---|
| `AG00` ~ `AG05` | 六个会发光的 Agent 键 | 无字 | ChatGPT 运行时它们固定用来切换线程，见第 6 节 |
| `ACT06` | 第 3 行第 1 个 | FAST ⚡ | |
| `ACT07` | 第 3 行第 2 个 | APPR ✓ | |
| `ACT08` | 第 3 行第 3 个 | REJ ⊗ | |
| `ACT09` | 第 3 行第 4 个 | SPLIT | |
| `ACT10`（别名 `MIC`） | 第 4 行的双宽键 | MIC 🎤 | 双宽键下面是两个开关，`ACT10` 和 `ACT11` 会同时触发；MicroKeys 只认 `ACT10`，写 `ACT11` 也会被当成 `ACT10` |
| `ACT12` | 第 4 行最右 | CODEX | |
| `ENC_CLK`（别名 `DIAL`） | 按下旋钮 | | |
| `ENC_CW`（别名 `DIAL_CW`） | 顺时针转一格 | | 每格触发一次，只能 `tap` |
| `ENC_CC`（别名 `DIAL_CC`） | 逆时针转一格 | | 同上 |

键帽是可以拔下来互换的，所以「印着什么图标」不代表是哪个 id。**不确定哪个键是哪个 id？**
按一下那个键，然后点开菜单栏图标，「最近按键」一行会显示它的 id。

id 不区分大小写，`mic`、`Mic`、`MIC` 都可以。同一个物理键只能绑一次（比如同时写 `MIC` 和 `ACT10` 会报错）。

摇杆和左下角的触控板不能绑定：摇杆是模拟量输入，触控板走的是标准键盘通道，MicroKeys 收不到。

## 5. 快捷键的写法

用 `+` 连接若干个修饰键和最多一个普通键，不区分大小写，`+` 两边可以有空格。

```
rctrl+rshift          只有修饰键，没有普通键（按住说话类应用常用）
cmd+shift+4           截图
ctrl+cmd+space        表情面板
f13                   单独一个键
fn                    单独的 fn/🌐 键
```

### 修饰键

| 写法 | 含义 |
|---|---|
| `cmd` / `command` / `⌘` | 左 Command |
| `rcmd` / `right_command` | 右 Command |
| `shift` / `⇧` | 左 Shift |
| `rshift` / `right_shift` | 右 Shift |
| `ctrl` / `control` / `⌃` | 左 Control |
| `rctrl` / `right_control` | 右 Control |
| `opt` / `option` / `alt` / `⌥` | 左 Option |
| `ropt` / `right_option` / `ralt` | 右 Option |
| `fn` / `globe` | fn / 🌐 |

左右是有区别的：MicroKeys 会发出带「右侧」标记的事件，所以把 `rctrl+rshift` 设成按住说话快捷键的应用能正确认出它。
不写 `r` 前缀默认是左侧。

### 普通键

* 字母 `a`～`z`，数字 `0`～`9`
* `f1`～`f20`
* `return` / `enter`、`tab`、`space`、`escape` / `esc`、`delete` / `backspace`、`forwarddelete`
* `up`、`down`、`left`、`right`、`home`、`end`、`pageup`、`pagedown`
* 符号可以直接写字符：`-` `=` `[` `]` `\` `;` `'` `,` `.` `/` `` ` ``；也可以写名字：`minus` `equal` `leftbracket` `rightbracket` `backslash` `semicolon` `quote` `comma` `period` `slash` `grave`
* 小键盘：`keypad0`～`keypad9`、`keypadenter`、`keypadplus`、`keypadminus`、`keypadmultiply`、`keypaddivide`、`keypaddecimal`、`keypadequals`

按键名对应的是美式键盘布局的物理位置。

不支持的：一个快捷键里放两个普通键。

### Windows 上的差异

| 写法 | macOS | Windows |
|---|---|---|
| `cmd` / `⌘` | Command 键 | Win 键（`win` 也可以写） |
| `opt` / `alt` | Option 键 | Alt 键 |
| `fn` | fn / 🌐 | 不支持，Windows 没有可合成的 fn 键 |
| `delete` / `backspace` | 退格 | 退格（与 macOS 含义一致） |
| `forwarddelete` / `del` | 前向删除 | Delete 键 |
| `volumeup` `volumedown` `mute` `playpause` `nexttrack` `prevtrack` | 不支持 | 支持 |
| `insert` `printscreen` `scrolllock` `pause` `numlock` `apps` | 不支持 | 支持 |

Windows 上合成按键不需要任何权限。唯一限制：MicroKeys 以普通权限运行时，按键无法送进以管理员身份运行的窗口。

## 6. 和 ChatGPT / Codex 桌面应用共存

MicroKeys 以共享方式打开设备，**不会**抢走 ChatGPT 的连接，也从不碰灯光。
两个程序同时收到每一次按键，各干各的。

但这意味着：你在 MicroKeys 里绑了某个键，ChatGPT 仍然会执行它原本的动作。
出厂布局下 ACT06～ACT12 分别是「快速模式 / 同意 / 拒绝 / 分叉 / 按住说话 / 发送」，
六个 Agent 键固定切换线程，旋钮固定发上下箭头。

要让某个键只属于 MicroKeys，在 ChatGPT 里把它设成空白键帽：
ChatGPT 桌面端 → 设置 → Codex Micro → 把对应槽位的键帽换成 **EMPT1～EMPT4**（单宽）或 **EMPT5**（双宽，用于语音键的位置），并且不要给它绑任何命令。
这样 ChatGPT 看到按键就什么也不做，而 MicroKeys 照常触发。

注意 ChatGPT 里的 MIC 键帽会**无条件**触发按住说话，改不掉。所以如果你把语音键映射给了别的听写软件，记得在 ChatGPT 里把这个双宽槽位换成 EMPT5，否则两个录音会同时开始。

Agent 键和旋钮在 ChatGPT 里没有「空白」选项，把它们映射成系统快捷键时会和 Codex 的动作同时发生；建议优先用 ACT06～ACT12。

## 7. 完整示例

```json
{
  "version": 1,
  "_comment": "语音键给听写软件，其余几个键做常用快捷键",

  "options": { "key_interval_ms": 30 },

  "bindings": {
    "MIC":     { "mode": "hold", "keys": "rctrl+rshift", "_comment": "按住说话" },
    "ACT06":   "cmd+shift+4",
    "ACT07":   { "mode": "tap",  "keys": "ctrl+cmd+space", "_comment": "表情面板" },
    "ACT12":   { "mode": "hold", "keys": "cmd", "_comment": "按住时相当于按住 ⌘，可以配合鼠标点击" },
    "DIAL":    "cmd+shift+a",
    "DIAL_CW": "cmd+=",
    "DIAL_CC": "cmd+-"
  }
}
```

## 8. 检查配置是否正确

三种方式，任选：

1. 保存后点开菜单栏图标：正常会列出每个绑定；出错会显示「❌ 配置错误：…」并说明是哪个键、错在哪。
2. 命令行校验，不需要连接键盘：
   ```sh
   /Applications/MicroKeys.app/Contents/MacOS/MicroKeys --check-config
   ```
3. 不插键盘也能验证目标应用是否响应某个快捷键（3 秒后按下，按住 800 ms 再松开）：
   ```sh
   /Applications/MicroKeys.app/Contents/MacOS/MicroKeys --test-shortcut "rctrl+rshift" 800
   ```
4. 目标应用收不到时，打印系统实际投递的键盘事件做对比。20 秒内先按一次真实键盘上的快捷键，再按一次映射的键：
   ```sh
   /Applications/MicroKeys.app/Contents/MacOS/MicroKeys --dump-events 20
   ```
   真实按键 `srcPid=0`；两组的 keyCode、flags 应一致。第一次运行会向终端索要「输入监控」权限。

### Typeless 实测可用的配置

Typeless 是「按一下开始、再按一下结束」的切换式，用 `tap` 模式；并且必须保留事件间隔：

```json
{
  "options": { "key_interval_ms": 30 },
  "bindings": { "MIC": { "mode": "tap", "keys": "ctrl+option+d" } }
}
```

在 Typeless 设置里给 Dictate 点「Add another」录入同一个组合即可，原来的 Fn 不受影响。

## 9. 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| 菜单显示「❌ 输入监控权限未授予」（macOS） | 系统设置 → 隐私与安全性 → 输入监控，打开 MicroKeys 的开关。授予后会自动重连，不用重启 |
| Windows 上「最近按键」有显示，目标应用没反应 | 目标应用是否以管理员身份运行？是的话 MicroKeys 也要以管理员运行。再用 `--dump-events` 看目标应用是否忽略 `injected=yes` 的事件 |
| 键按了，「最近按键」有显示，但目标应用没反应 | 先确认 `options.key_interval_ms` 不是 0（Typeless 需要 ≥ 30）。再查辅助功能权限：系统设置 → 隐私与安全性 → 辅助功能。仍不行可用 `--dump-events` 对比真实按键和合成按键的字段，见第 8 节 |
| 「最近按键」什么都不显示 | 键盘没连上，或者输入监控权限没给。USB 和蓝牙都支持，两者都连着时走 USB |
| 修改配置后没生效 | 看菜单里有没有「配置错误」。也可以手动点「重新加载配置」 |
| 重新编译后权限又要重新给 | 用了临时签名（ad-hoc）。参考 README 用自签名证书签名，权限就能跨版本保留 |
| 按住说话结束后某个修饰键好像卡住了 | MicroKeys 在键盘断开、配置重载、退出时都会自动松开所有按住的键；如仍异常，随手按一下那个修饰键即可复位 |

日志位置见第 1 节的表格，菜单里「打开日志…」可直接查看。

## 10. 卸载

```sh
/Applications/MicroKeys.app/Contents/MacOS/MicroKeys --uninstall    # macOS
MicroKeys.exe --uninstall                                            # Windows
```

先列出将删除的内容再确认（`--yes` 跳过确认）：配置、日志、语言偏好、开机自启，以及正在运行的实例。
之后手动删除程序本身；macOS 上还需在「系统设置 → 隐私与安全性」里移除两条权限记录。详见 README「卸载」一节。
