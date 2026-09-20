# MicroKeys configuration guide

MicroKeys maps keys on the Codex Micro to macOS system shortcuts through one JSON file.
The file is reloaded automatically when saved; a mistake shows up in the menu bar menu with the reason.

## 1. Where the file lives

| OS | Config | Log |
|---|---|---|
| macOS | `~/.config/microkeys/config.json` | `~/Library/Logs/MicroKeys.log` |
| Windows | `%APPDATA%\MicroKeys\config.json` | `%LOCALAPPDATA%\MicroKeys\MicroKeys.log` |

* An example config is written on first launch (same as `config.example.json` in the repo).
* Menu bar / tray icon → "Open Config File…" opens it in your default editor.
* To use another location, set `MICROKEYS_CONFIG=/path/to/file.json` before launching.

**The same config file works on both systems**: key ids and shortcut syntax are identical; the few differences are listed at the end of section 5.

## 2. Smallest example

Map the voice key (the double-width key with the microphone cap) to holding Right Ctrl + Right Shift:

```json
{
  "version": 1,
  "bindings": {
    "MIC": { "mode": "hold", "keys": "rctrl+rshift" }
  }
}
```

While the voice key is down, MicroKeys holds Right Ctrl and Right Shift; when you let go, it releases them.
That is what push-to-talk dictation apps expect.

## 3. File structure

```json
{
  "version": 1,
  "_comment": "any text; fields starting with an underscore are ignored",

  "options": {
    "key_interval_ms": 30
  },

  "bindings": {
    "<key id>": "<shortcut>",
    "<key id>": { "mode": "tap" | "hold", "keys": "<shortcut>" }
  }
}
```

| Field | Required | Meaning |
|---|---|---|
| `version` | no | only `1`; may be omitted |
| `options.key_interval_ms` | no | pause between the individual down/up events of one shortcut, in ms. Default `30`. **Do not set it to 0**: dictation apps such as Typeless ignore a chord whose events arrive back to back. 10–20 may work if you want less latency |
| `options.split_mic_key` | no | `true` treats the two switches under the double-width MIC cap as separate keys, so `ACT10` and `ACT11` can be bound individually. This is the Codex app's "use independent microphone keys". Default `false`, in which case `ACT11` is folded into `ACT10` |
| `bindings` | yes | key id → shortcut; may be empty |
| any field starting with `_` | no | a comment |

JSON has no `//` comments; use `"_comment": "..."` instead.

### Two ways to write a binding

**Short form**: a shortcut string, which means tap mode.

```json
"ACT06": "cmd+shift+4"
```

**Full form**: an object with a mode.

```json
"ACT06": { "mode": "tap", "keys": "cmd+shift+4", "_comment": "screenshot" }
```

### The two modes

| mode | Behaviour | Good for |
|---|---|---|
| `tap` (default) | press and release the shortcut the moment the key goes down | almost everything: screenshots, switching apps, opening a panel |
| `hold` | press the shortcut on key-down, release it on key-up | push-to-talk, holding a window, using a pad key as a modifier |

Dial rotation (`ENC_CW` / `ENC_CC`) has no release event, so it only supports `tap`; `hold` is rejected.

## 4. Key ids

Physical layout and ids:

```
row 1:  [ ◯ dial ]     [ AG00 ]  [ AG01 ]  [ ● joystick ]
row 2:  [ AG02 ]       [ AG03 ]  [ AG04 ]  [ AG05 ]
row 3:  [ ACT06 ]      [ ACT07 ] [ ACT08 ] [ ACT09 ]
row 4:  [ ◉ touchpad ] [ ══ ACT10 + ACT11 ══ ] [ ACT12 ]
```

| id | What | Factory cap | Notes |
|---|---|---|---|
| `AG00` – `AG05` | the six lit Agent Keys | blank | while ChatGPT runs they always switch threads, see section 6 |
| `ACT06` | row 3, first | FAST ⚡ | |
| `ACT07` | row 3, second | APPR ✓ | |
| `ACT08` | row 3, third | REJ ⊗ | |
| `ACT09` | row 3, fourth | SPLIT | |
| `ACT10` (alias `MIC`) | the double-width key in row 4 | MIC 🎤 | two switches sit under one cap, each with its own id, and a press lands on whichever side you push; by default MicroKeys treats `ACT11` as `ACT10`, so the whole cap is one key |
| `ACT11` | the other half of the double-width key | | bindable on its own only with `options.split_mic_key` set to `true`. Use `--dump-pad` (section 8) to see which half is which |
| `ACT12` | row 4, right | CODEX | |
| `ENC_CLK` (alias `DIAL`) | dial press | | |
| `ENC_CW` (alias `DIAL_CW`) | dial, one detent clockwise | | fires once per detent, `tap` only |
| `ENC_CC` (alias `DIAL_CC`) | dial, one detent counter-clockwise | | same |

Keycaps are swappable, so the printed icon does not tell you the id. **Not sure which key is which?**
Press it, then open the menu: "Last key" shows its id.

Ids are case-insensitive. Each physical key can be bound once (writing both `MIC` and `ACT10` is an error, and so is `ACT10` plus `ACT11` unless `split_mic_key` is on).

To use the double-width key as two keys:

```json
{
  "options": { "split_mic_key": true },
  "bindings": {
    "ACT10": { "mode": "hold", "keys": "rctrl+rshift" },
    "ACT11": "f13"
  }
}
```

The joystick and the touchpad cannot be bound: the joystick is analogue and the touchpad speaks plain HID keyboard, which MicroKeys does not read.

## 5. Shortcut syntax

Join modifiers and at most one regular key with `+`. Case-insensitive; spaces around `+` are fine.

```
rctrl+rshift          modifiers only (push-to-talk apps like this)
cmd+shift+4           screenshot
ctrl+cmd+space        emoji picker
f13                   a single key
fn                    the fn / 🌐 key on its own
```

### Modifiers

| Spelling | Meaning |
|---|---|
| `cmd` / `command` / `⌘` | left Command |
| `rcmd` / `right_command` | right Command |
| `shift` / `⇧` | left Shift |
| `rshift` / `right_shift` | right Shift |
| `ctrl` / `control` / `⌃` | left Control |
| `rctrl` / `right_control` | right Control |
| `opt` / `option` / `alt` / `⌥` | left Option |
| `ropt` / `right_option` / `ralt` | right Option |
| `fn` / `globe` | fn / 🌐 |

Left and right are distinct: MicroKeys sends the right-hand flag, so an app configured for `rctrl+rshift` recognises it.
Without the `r` prefix you get the left key.

### Regular keys

* letters `a`–`z`, digits `0`–`9`
* `f1`–`f20`
* `return` / `enter`, `tab`, `space`, `escape` / `esc`, `delete` / `backspace`, `forwarddelete`
* `up`, `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown`
* punctuation as the character itself: `-` `=` `[` `]` `\` `;` `'` `,` `.` `/` `` ` ``, or by name: `minus` `equal` `leftbracket` `rightbracket` `backslash` `semicolon` `quote` `comma` `period` `slash` `grave`
* keypad: `keypad0`–`keypad9`, `keypadenter`, `keypadplus`, `keypadminus`, `keypadmultiply`, `keypaddivide`, `keypaddecimal`, `keypadequals`

Key names refer to positions on the US layout.

Not supported: two regular keys in one shortcut.

### Differences on Windows

| Spelling | macOS | Windows |
|---|---|---|
| `cmd` / `⌘` | Command | the Windows key (`win` also works) |
| `opt` / `alt` | Option | Alt |
| `fn` | fn / 🌐 | not available; Windows has no synthesizable fn key |
| `delete` / `backspace` | Backspace | Backspace (same meaning as on macOS) |
| `forwarddelete` / `del` | forward delete | the Delete key |
| `volumeup` `volumedown` `mute` `playpause` `nexttrack` `prevtrack` | not supported | supported |
| `insert` `printscreen` `scrolllock` `pause` `numlock` `apps` | not supported | supported |

Synthesizing keys needs no permission on Windows. The one limit: when MicroKeys runs unelevated, its keys cannot reach windows that run as administrator.

## 6. Living alongside the ChatGPT / Codex desktop app

MicroKeys opens the device in shared mode: it **does not** take the pad away from ChatGPT and never touches the lights.
Both programs see every key press and act independently.

That also means ChatGPT keeps doing whatever a key did before. With the factory layout ACT06–ACT12 are
fast mode / approve / reject / fork / push-to-talk / send, the six Agent Keys switch threads, and the dial sends arrow keys.

To make a key MicroKeys-only, give it a blank cap in ChatGPT:
ChatGPT → Settings → Codex Micro → set that slot's cap to **EMPT1–EMPT4** (single width) or **EMPT5** (double width, for the voice key slot) and leave it without a command.
ChatGPT then ignores the key while MicroKeys still fires.

Note that the MIC cap in ChatGPT **always** triggers push-to-talk and cannot be overridden. If you map the voice key to another dictation app, switch that slot to EMPT5, or both recorders start at once.

Agent Keys and the dial have no blank option in ChatGPT, so mapping them means both actions happen; prefer ACT06–ACT12.

## 7. Full example

```json
{
  "version": 1,
  "_comment": "voice key for dictation, a few keys for everyday shortcuts",

  "options": { "key_interval_ms": 30 },

  "bindings": {
    "MIC":     { "mode": "hold", "keys": "rctrl+rshift", "_comment": "push to talk" },
    "ACT06":   "cmd+shift+4",
    "ACT07":   { "mode": "tap",  "keys": "ctrl+cmd+space", "_comment": "emoji picker" },
    "ACT12":   { "mode": "hold", "keys": "cmd", "_comment": "acts as ⌘ while held, for click-modifiers" },
    "DIAL":    "cmd+shift+a",
    "DIAL_CW": "cmd+=",
    "DIAL_CC": "cmd+-"
  }
}
```

## 8. Checking the config

1. Save and open the menu bar menu: every binding is listed, or a "❌ Config error" line names the key and the problem.
2. Validate from the command line, no pad required:
   ```sh
   /Applications/MicroKeys.app/Contents/MacOS/MicroKeys --check-config
   ```
3. Check whether a target app reacts to a shortcut without the pad (pressed after 3 s, held 800 ms):
   ```sh
   /Applications/MicroKeys.app/Contents/MacOS/MicroKeys --test-shortcut "rctrl+rshift" 800
   ```
4. When the target app does not react, print the keyboard events macOS actually delivers. Within 20 s press the shortcut on a real keyboard, then the mapped pad key:
   ```sh
   /Applications/MicroKeys.app/Contents/MacOS/MicroKeys --dump-events 20
   ```
   Hardware keys show `srcPid=0`; keyCode and flags of the two groups should match. The first run asks for Input Monitoring for the terminal.
5. To learn what the firmware calls a switch (for example which half of the wide key is `ACT10` and which is `ACT11`), print the pad's raw events with no aliasing or folding:
   ```sh
   /Applications/MicroKeys.app/Contents/MacOS/MicroKeys --dump-pad 20
   ```
   Also needs Input Monitoring for the terminal; a running MicroKeys app is not affected.

### A configuration verified with Typeless

Typeless is toggle-style (press once to start, again to stop), so use `tap`, and keep the event interval:

```json
{
  "options": { "key_interval_ms": 30 },
  "bindings": { "MIC": { "mode": "tap", "keys": "ctrl+option+d" } }
}
```

In Typeless, click "Add another" next to the Dictate shortcut and record the same combination; the original Fn shortcut keeps working.

## 9. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Menu shows "❌ Input Monitoring missing" (macOS) | System Settings → Privacy & Security → Input Monitoring, enable MicroKeys. It reconnects on its own; no restart needed |
| On Windows "Last key" updates but the target app does nothing | Is the target app running as administrator? Then MicroKeys must too. Otherwise use `--dump-events` to see whether the app ignores `injected=yes` events |
| A chord with an arrow key such as `ctrl+alt+cmd+up` does not trigger a Raycast hotkey, but the same chord with a letter does | Known issue, to be fixed: on macOS the synthesized arrow, Home/End/Page Up/Page Down and F keys lack the fn / numeric-pad flags a real keyboard adds, so flag-comparing hotkey matchers reject them. Workaround: use a letter or digit in the hotkey |
| "Last key" updates but the target app does nothing | First make sure `options.key_interval_ms` is not 0 (Typeless needs ≥ 30). Then check Accessibility: System Settings → Privacy & Security → Accessibility. Still stuck: compare real vs synthetic events with `--dump-events`, section 8 |
| "Last key" never changes | The pad is not connected, or Input Monitoring is missing. USB and Bluetooth both work; with both connected USB wins |
| Edits do not take effect | Look for a "Config error" line in the menu, or click "Reload Config" |
| Permissions have to be granted again after a rebuild | Ad-hoc signature. Sign with a self-signed certificate (see README) and the grants survive rebuilds |
| A modifier seems stuck after push-to-talk | MicroKeys releases everything it holds on disconnect, config reload and quit; if something still sticks, tap that modifier once |

Log locations are in the table in section 1; "Open Log…" in the menu opens it.

## 10. Uninstalling

```sh
/Applications/MicroKeys.app/Contents/MacOS/MicroKeys --uninstall    # macOS
MicroKeys.exe --uninstall                                            # Windows
```

Lists what will be removed and asks for confirmation (`--yes` skips it): config, log, language preference, the launch-at-login entry, and any running instance.
Then delete the program itself; on macOS also remove the two permission entries under System Settings → Privacy & Security. See the README's uninstall section.
