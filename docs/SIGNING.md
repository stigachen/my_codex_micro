# 签名、公证与分发

MicroKeys 是常驻在菜单栏、需要「输入监控」和「辅助功能」两项权限的应用。这两项权限和 Gatekeeper 都以**代码签名**为准，
所以怎么签名直接决定了用户装起来顺不顺。本文档记录三种签名方式、各自的效果、具体操作步骤，以及日后拿到 Developer ID 之后要做的事。

## 1. 为什么签名重要

| 系统机制 | 看什么 | 签名不对的后果 |
|---|---|---|
| 权限（TCC） | 签名者身份加 bundle id | 身份一变，输入监控和辅助功能都要重新授予 |
| Gatekeeper | 是否由 Apple 认可的证书签名并经过公证 | 双击打不开，提示「已损坏」或「无法验证开发者」 |
| 开机自启（SMAppService） | 签名与应用路径稳定 | 注册失效或被系统提示「后台项目已添加」后失联 |

## 2. 三种签名方式

| 方式 | 权限跨版本保留 | Gatekeeper 放行 | 成本 | 适合 |
|---|---|---|---|---|
| 临时签名（ad-hoc） | ❌ 每次构建都要重新授权 | ❌ | 0 | 本机开发调试 |
| 自签名证书 | ✅ | ❌ 收件人要手动放行一次 | 0，两分钟 | 自己用、小范围内部分发 |
| Developer ID + 公证 | ✅ | ✅ 双击即开 | 99 美元/年 | 公开分发 |

`make app` 默认临时签名；`make release` 要求指定证书，可以是自签名或 Developer ID。

## 3. 自签名证书（当前使用的方式）

### 3.1 用钥匙串访问创建（图形界面）

1. 打开「钥匙串访问」→ 菜单「钥匙串访问」→「证书助理」→「创建证书」。
2. 名称 `MicroKeys Dev`，身份类型「自签名根证书」，证书类型「代码签名」，创建。
3. 终端确认：

```sh
security find-identity -v -p codesigning
#   1) XXXXXXXX "MicroKeys Dev"
```

### 3.2 用命令行创建（可脚本化）

```sh
cat > ext.cnf <<'EOF2'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = MicroKeys Dev
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF2
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes -keyout key.pem -out cert.pem -config ext.cnf
openssl pkcs12 -export -inkey key.pem -in cert.pem -name "MicroKeys Dev" -out cert.p12 -passout pass:changeme -legacy
security import cert.p12 -k ~/Library/Keychains/login.keychain-db -P changeme -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db cert.pem
rm key.pem cert.pem cert.p12 ext.cnf
```

`-T /usr/bin/codesign` 让 codesign 使用私钥时不再弹密码框。`add-trusted-cert` 可能弹出一次钥匙串授权，点允许即可。

### 3.3 使用

```sh
SIGN_IDENTITY="MicroKeys Dev" make app        # 本地构建，签名身份固定
SIGN_IDENTITY="MicroKeys Dev" make release    # 发布包，见第 5 节
```

### 3.4 换机器构建

私钥只在创建证书的那台 Mac 上。换机器要把证书**连同私钥**带过去，否则新机器上签出来的是另一个身份，用户又要重新授权。

1. 钥匙串访问 → 我的证书 → 右键「MicroKeys Dev」→ 导出，格式 `.p12`，设一个密码。
2. 新机器上双击 `.p12` 导入，或 `security import xxx.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign`。
3. 新机器上同样执行一次 `security add-trusted-cert … -p codeSign …`（导出证书的 `.cer` 或 `.pem` 即可）。

### 3.5 收件人怎么装

自签名不被 Gatekeeper 认可，第一次打开会被拦。二选一：

* 打开被拦后，去「系统设置 → 隐私与安全性」，页面下方点「仍要打开」；
* 或在终端执行 `xattr -dr com.apple.quarantine /Applications/MicroKeys.app`。

之后升级只要还是同一张证书签的，不再有任何提示，权限也不用重新给。

## 4. Developer ID（日后升级路径）

### 4.1 申请开发者账号

1. 准备开了双重认证的 Apple ID。
2. 在 iPhone/iPad 上装 **Apple Developer** 应用登录，点 Enroll。个人身份会要求拍身份证件和人脸验证。网页入口是 developer.apple.com/programs/enroll。
3. 类型选**个人（Individual）**最简单，证书显示个人姓名；**组织**需要 D-U-N-S 编码和法人授权，审核更久。
4. 付费 99 美元/年，中国区支持支付宝、银联。
5. 等待激活，个人通常几小时到两天，收到 Welcome 邮件即可。

### 4.2 创建 Developer ID Application 证书

不需要 Xcode。

1. 「钥匙串访问」→「证书助理」→「从证书颁发机构请求证书」，填邮箱和名字，选「存储到磁盘」，得到 `.certSigningRequest`。
2. developer.apple.com → Certificates, Identifiers & Profiles → Certificates → ＋。
3. 类型选 **Developer ID Application**（不是 Mac App Distribution），上传请求文件，下载 `.cer`。
4. 双击 `.cer` 导入。确认：

```sh
security find-identity -v -p codesigning
#   1) XXXXXXXX "Developer ID Application: Your Name (TEAMID)"
```

只有账号持有人能创建 Developer ID 证书；个人账号天然是持有人。私钥同样只在这台机器，备份方式见 3.4。

### 4.3 公证凭据

公证通过 `notarytool` 提交，需要 App 专用密码：

1. appleid.apple.com → 登录与安全 → App 专用密码，生成一个。
2. 存进钥匙串，只做一次：

```sh
xcrun notarytool store-credentials "MicroKeys" --apple-id 你的AppleID --team-id TEAMID
```

按提示粘贴 App 专用密码。之后脚本通过 `--keychain-profile "MicroKeys"` 使用它。

### 4.4 发布

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="MicroKeys" make release
```

脚本会：用证书签名并开启 hardened runtime、带时间戳、打 zip 提交公证并等待结果、把公证票据 staple 到 .app、再打 dmg 和 zip。
公证通常几分钟，首次可能更久。

验证：

```sh
spctl --assess --type execute build/MicroKeys.app      # 应输出 accepted
xcrun stapler validate build/MicroKeys.app            # 应输出 The validate action worked
```

### 4.5 从自签名切换到 Developer ID 时用户会经历什么

签名身份变了，所以已安装的用户升级时会**再授权一次**输入监控和辅助功能，之后永久稳定。在发布说明里提前告知即可。

## 5. `make release` 说明

脚本在 `scripts/release.sh`。

| 环境变量 | 必填 | 含义 |
|---|---|---|
| `SIGN_IDENTITY` | 是 | 钥匙串里的证书名。缺少或找不到直接失败，不会退回临时签名 |
| `NOTARY_PROFILE` | 否 | `notarytool store-credentials` 时起的名字。给了就公证并 staple，自签名证书不要给（Apple 不会公证） |

产物在 `dist/`：

* `MicroKeys-<版本>.dmg`：挂载后拖到 Applications，内附快捷方式
* `MicroKeys-<版本>.zip`：同内容，适合命令行或 Homebrew
* `SHA256SUMS.txt`

版本号取自根目录的 `VERSION` 文件。

## 6. 在 GitHub Actions 上出 Release

仓库里有两个工作流：

| 文件 | 触发 | 作用 |
|---|---|---|
| `.github/workflows/ci-macos.yml` | push 到 main、PR，且改动涉及 `macos/` | 只构建和跑测试，不出包 |
| `.github/workflows/release.yml` | 推送 `v*` 形式的 tag | 签名、打包、创建 GitHub Release 并附上 dmg、zip、SHA256SUMS |

合并 PR 永远不会产生 Release。发版就三步：

```sh
# 1. 改根目录的 VERSION 文件，提交
echo 0.3.0 > VERSION && git commit -am "0.3.0"
# 2. 打 tag，版本号必须和 VERSION 一致，否则工作流第一步就失败
git tag v0.3.0
git push origin main v0.3.0
# 3. 几分钟后在仓库 Releases 页面看到产物
```

工作流分三段：`check` 校验版本号，每个平台一个 job 构建并上传产物，最后 `publish` 汇总所有产物生成校验和并创建 Release。任一平台失败就不会创建 Release。

### 6.1 仓库里需要的 Secret 和 Variable

| 名称 | 类型 | 内容 |
|---|---|---|
| `MACOS_CERT_P12` | Secret | 证书连私钥的 `.p12` 文件，base64 编码 |
| `MACOS_CERT_PASSWORD` | Secret | 导出 `.p12` 时设的密码 |
| `SIGN_IDENTITY` | Variable | 证书名，如 `MicroKeys Dev` 或 `Developer ID Application: Name (TEAMID)` |
| `NOTARY_APPLE_ID` / `NOTARY_PASSWORD` / `NOTARY_TEAM_ID` | Secret，可选 | 有 Developer ID 后填上，工作流会自动公证并 staple |

导出并写入的命令（在有证书的那台 Mac 上执行）：

```sh
security export -k ~/Library/Keychains/login.keychain-db -t identities -f pkcs12 -P '密码' -o cert.p12
base64 -i cert.p12 | gh secret set MACOS_CERT_P12
gh secret set MACOS_CERT_PASSWORD --body '密码'
gh variable set SIGN_IDENTITY --body "MicroKeys Dev"
rm cert.p12
```

`security export -t identities` 会导出登录钥匙串里**所有**带私钥的证书，如果不止一张，先在钥匙串访问里单独导出目标证书。

### 6.2 工作流里签名是怎么做的

新建一个临时钥匙串，导入 `.p12`，允许 codesign 免密使用私钥，把证书加入系统信任（自签名证书必须这一步，否则 codesign 不认），跑 `make release`，最后无论成败都删除临时钥匙串。私钥只存在于运行器的临时目录，日志里不会出现。

### 6.3 费用

私有仓库的 macOS 运行器按 Linux 的 10 倍计费，免费额度折合每月约 200 分钟 macOS 时间；一次 Release 构建约 3 到 5 分钟。CI 工作流每次 push 也会用掉几分钟，频繁提交时留意用量。

## 7. 检查一个包的签名状态

```sh
codesign -dvv MicroKeys.app 2>&1 | grep -E "Authority|Signature|flags"
#   Signature=adhoc            → 临时签名
#   Authority=MicroKeys Dev    → 自签名
#   Authority=Developer ID Application: … → 正式证书
#   flags=0x10000(runtime)     → 已开启 hardened runtime

spctl --assess --type execute MicroKeys.app
#   accepted → 已公证；rejected → 未公证（临时签名和自签名都是这个结果）
```

## 8. 常见问题

| 现象 | 原因 / 处理 |
|---|---|
| 每次升级都要重新授权 | 用的是临时签名，或换了证书。用同一张自签名或 Developer ID 证书签 |
| 「MicroKeys 已损坏，无法打开」 | 下载时被打上隔离属性且未公证。按 3.5 放行 |
| `make release` 报 no code-signing identity | 证书名写错，或证书没有私钥（只导入了 .cer）。`security find-identity -v -p codesigning` 看列表 |
| codesign 弹密码框 | 导入 .p12 时没加 `-T /usr/bin/codesign`。钥匙串访问里找到私钥 → 访问控制 → 允许 codesign |
| 公证失败 | `xcrun notarytool log <submission-id> --keychain-profile MicroKeys` 看原因，常见是没开 hardened runtime 或没带时间戳，脚本已处理这两项 |
| 换了机器后用户又要授权 | 新机器上是新证书。按 3.4 把原证书连私钥迁过去 |
