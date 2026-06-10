# mirrorsh

> tiny POSIX sh mirror switcher for Linux and embedded devices
>
> mirrorsh：一个轻量、无依赖、适合 Linux 小设备的软件源切换脚本

`mirrorsh` 是一个**单文件、无依赖、POSIX sh 兼容**的软件源切换工具，专为 Debian、Ubuntu、Alpine、OpenWrt，以及刷机后的随身 WiFi、软路由、嵌入式 Linux 小设备设计。

它不是守护进程，没有安装器，没有后台服务，没有花哨 UI。它就是一个可以直接执行的一键脚本。

```sh
sh mirror.sh --mirror ustc --yes
```

> **mirrorsh 不安装、不常驻、不升级系统。** 它只切换软件源并执行 `update`，**绝不**执行 `upgrade` / `full-upgrade`。脚本跑完即退出，不留任何后台进程，不修改 init/systemd，不自我更新。

---

## 目录

- [设计目标](#设计目标)
- [支持的系统](#支持的系统)
- [支持的镜像](#支持的镜像)
- [为什么默认 protocol 是 auto](#为什么默认-protocol-是-auto)
- [为什么小设备上 HTTPS 可能失败](#为什么小设备上-https-可能失败)
- [为什么 OpenWrt 只替换基础地址](#为什么-openwrt-只替换基础地址)
- [快速开始](#快速开始)
- [命令参数](#命令参数)
- [交互模式](#交互模式)
- [备份与恢复](#备份与恢复)
- [风险说明](#风险说明)
- [故障排查](#故障排查)
- [测试与 CI](#测试与-ci)

---

## 设计目标

1. **单文件**：主脚本是单个 `mirror.sh`（项目名 `mirrorsh`），可直接 `curl | sh` 或 `scp` 到设备执行。
2. **POSIX sh**：不依赖 bash 专属语法，兼容 BusyBox / ash / dash。
3. **无运行时依赖**：不依赖 Python / Perl / jq / Node.js / Go / Rust，甚至不强依赖 awk。
4. **小设备友好**：任何可选命令（curl/wget/mktemp/sort…）使用前都先检测是否存在，并有 fallback。
5. **安全第一**：修改前自动备份，可一键恢复，绝不删除用户原始配置，绝不生成错误源。
6. **只换源不升级**：只执行 `apt/apk/opkg update`，**绝不**执行 `upgrade` / `full-upgrade`。

---

## 支持的系统

| 系统 | 包管理器 | 修改的文件 |
|------|----------|-----------|
| Debian 10/11/12/13 (buster/bullseye/bookworm/trixie) | apt | `/etc/apt/sources.list`（deb822 `.sources` 会被备份并禁用） |
| Ubuntu 20.04+ (focal/jammy/noble…) | apt | `/etc/apt/sources.list`（含 ports 架构） |
| Alpine 3.x / edge | apk | `/etc/apk/repositories` |
| OpenWrt 19.07+ | opkg | `/etc/opkg/distfeeds.conf`（仅替换基础地址） |

> 第一版**不支持** CentOS / Rocky / AlmaLinux / Fedora / Arch。

---

## 支持的镜像

国内镜像优先展示，海外/官方靠后。**并非每个镜像都支持每个发行版**——`mirrorsh` 内置一张支持矩阵，不可用的组合在菜单中标注 `[不可用]`，在命令行模式下会明确报错，绝不生成假 URL。

| 镜像 | 名称 | Debian | Ubuntu | Ubuntu-ports | Alpine | OpenWrt |
|------|------|:------:|:------:|:------------:|:------:|:-------:|
| `ustc`    | 中科大        | ✅ | ✅ | ✅ | ✅ | ✅ |
| `tuna`    | 清华 TUNA     | ✅ | ✅ | ✅ | ✅ | ✅ |
| `aliyun`  | 阿里云        | ✅ | ✅ | ✅ | ✅ | ✅ |
| `tencent` | 腾讯云        | ✅ | ✅ | ✅ | ✅ | ✅ |
| `huawei`  | 华为云        | ✅ | ✅ | ✅ | ✅ | ✅ |
| `nju`     | 南京大学      | ✅ | ✅ | ✅ | ✅ | ✅ |
| `sjtu`    | 上海交大      | ✅ | ✅ | ✅ | ✅ | ✅ |
| `bfsu`    | 北京外国语    | ✅ | ✅ | ✅ | ✅ | ✅ |
| `sustech` | 南方科技大学  | ✅ | ✅ | ✅ | ✅ | ✅ |
| `163`     | 网易 163      | ✅ | ✅ | ❌ | ✅ | ❌ |
| `zju`     | 浙江大学      | ✅ | ✅ | ✅ | ✅ | ❌ |
| `lzu`     | 兰州大学      | ✅ | ✅ | ✅ | ✅ | ❌ |
| `official`| 官方源        | ✅ | ✅ | ✅ | ✅ | ✅ |

`official` 使用全球 CDN（`deb.debian.org`、`archive/ports.ubuntu.com`、`dl-cdn.alpinelinux.org`、`downloads.openwrt.org`），是最可靠的海外/兜底选项。

> **没有默认镜像**：无论命令行还是交互菜单，镜像都由你自己选择，`mirrorsh` 不偏向任何一个（包括 TUNA）。Debian 的 security 源始终使用官方 `security.debian.org`，不会因为选了某个镜像而被替换。

> **关于海外镜像（kernel / jaist / riken / leaseweb）**：这些站点的实际可用路径需要逐一核实，当前**未启用**，以免生成无法验证的 URL。它们已列入 `.github/workflows/mirror-check.yml` 的待验证清单，验证通过后会在后续版本加入支持矩阵。这符合本项目“宁可不启用，也不生成错误源”的原则。

---

## 为什么默认 protocol 是 auto

`--protocol auto`（默认）会做如下决策：

1. **优先 HTTPS**：更安全，能抵抗运营商劫持/注入。
2. **必要时自动用 HTTP**：当系统明显不适合 HTTPS 时（见下节），直接用 HTTP，避免一上来就握手失败。
3. **失败自动回退**：若选了 HTTPS 后 `update` 因证书/TLS/时间问题失败，自动改写为 HTTP 并**重试一次**。

你也可以用 `--protocol https` 或 `--protocol http` 强制指定。注意：**强制 https 时不会自动回退 http**（尊重你的显式意图）。

---

## 为什么小设备上 HTTPS 可能失败

随身 WiFi、软路由、刷机后的 OpenWrt、精简 BusyBox 环境经常**没有 CA 证书**或**系统时间不准**，导致 HTTPS 握手必然失败。`auto` 在以下情况会直接选用 HTTP：

- 系统时间明显异常（年份 < 2020，TLS 证书会被判“尚未生效”）。
- 找不到常见 CA 证书文件：
  - `/etc/ssl/certs/ca-certificates.crt`
  - `/etc/ssl/cert.pem`
  - `/etc/pki/tls/certs/ca-bundle.crt`

`mirrorsh` **不会**使用 `--no-check-certificate` 之类的不安全开关；它只是在条件不足时退回到 HTTP。

---

## 为什么 OpenWrt 只替换基础地址

OpenWrt 的 `distfeeds.conf` 里的路径包含 target / subtarget / arch（如 `releases/23.05.5/targets/ramips/mt7621/packages`）。这些信息**只有设备自己知道**，脚本去推断极易出错并直接刷不了机。

因此 `mirrorsh` 采取最保守策略：**只替换已有 feed URL 的基础地址，完整保留后面的路径**。

```diff
- src/gz openwrt_core https://downloads.openwrt.org/releases/23.05.5/targets/ramips/mt7621/packages
+ src/gz openwrt_core https://mirrors.ustc.edu.cn/openwrt/releases/23.05.5/targets/ramips/mt7621/packages
```

只识别已知官方/镜像基础地址（`downloads.openwrt.org` 及已知镜像的 `/openwrt`），不会误伤其它 URL。若 `/etc/opkg/distfeeds.conf` 不存在，直接报错，**绝不凭空生成**。

---

## 快速开始

### curl 一键运行

```sh
curl -fsSL https://raw.githubusercontent.com/akiiya/mirrorsh/main/mirror.sh | sh -s -- --mirror ustc --yes
```

### wget 一键运行

```sh
wget -O- https://raw.githubusercontent.com/akiiya/mirrorsh/main/mirror.sh | sh -s -- --mirror ustc --yes
```

> 通过管道执行时（`curl | sh`），交互菜单会从 `/dev/tty` 读取输入，不会因 stdin 被占用而卡死。若没有 `/dev/tty` 且未带参数，会显示帮助并退出。

> ⚠️ **GitHub raw 本身就是 HTTPS。** 如果设备的 HTTPS 已经坏掉（没有 CA 证书、系统时间不准），那么 `curl`/`wget` 连 `raw.githubusercontent.com` 都会失败——这时**先在电脑上下载 `mirror.sh`，再用下面的 scp 方式拷进设备**，比在设备上硬连 GitHub 更可靠。

### 手动下载 / scp 到随身 WiFi、软路由（离线/无 curl 环境推荐）

```sh
scp mirror.sh root@192.168.8.1:/tmp/mirror.sh
ssh root@192.168.8.1 'sh /tmp/mirror.sh --mirror ustc --yes'
```

### 典型用法

```sh
sh mirror.sh --check                       # 只检测系统, 不改任何东西
sh mirror.sh --list                        # 看支持哪些镜像
sh mirror.sh --mirror ustc --dry-run       # 预览将写入的内容
sh mirror.sh --mirror aliyun --yes         # 切到阿里云并 apt update
sh mirror.sh --mirror official --yes       # 切回官方源
sh mirror.sh --mirror ustc --protocol http --yes   # 强制 HTTP
sh mirror.sh --restore                     # 恢复最近一次备份
```

---

## 命令参数

```
--help            显示帮助
--version         显示版本号 (v0.1.0-rc1)
--list            列出支持的系统、镜像与当前系统可用镜像
--check           只检测系统信息, 不修改任何文件
--mirror <name>   指定镜像 (ustc/aliyun/official ...)
--protocol <p>    协议 auto|http|https (默认 auto)
--dry-run         只打印将修改的文件和内容, 不实际修改
--yes             跳过确认
--no-update       切换后不执行 apt/apk/opkg update
--restore         恢复最近一次 mirrorsh 备份
--debug           输出更多诊断信息
--no-color        禁用彩色输出
```

**非交互模式**（带任意参数时）：

- 除 `--help / --version / --list / --check / --restore` 外，**必须**带 `--mirror`，否则报错退出。
- 不会等待用户输入而卡死。未带 `--yes` 且非 `--dry-run` 时，若有 `/dev/tty` 会提示确认，否则报错。

### `--check` 示例

```
$ sh mirror.sh --check
== mirrorsh --check ==
distro:            debian
version:           12
codename:          bookworm
package manager:   apt
cpu architecture:  amd64
detected sources:  /etc/apt/sources.list.d/debian.sources
suggested protocol: https (--protocol=auto)
current mirror:    official
```

### `--list` 示例

```
$ sh mirror.sh --list
== 当前系统 (debian / amd64) 可用镜像 ==
  [可用] ustc      中科大 USTC
  [可用] aliyun    阿里云 Aliyun
  ...
```

### `--dry-run` 示例

```
$ sh mirror.sh --mirror ustc --dry-run
== 将要修改的文件 ==
  禁用并备份: /etc/apt/sources.list.d/debian.sources -> ...mirrorsh.bak.<ts>
  写入: /etc/apt/sources.list
== 新内容 (/etc/apt/sources.list) ==
  | deb https://mirrors.ustc.edu.cn/debian bookworm main contrib non-free non-free-firmware
  | ...
(dry-run: 未修改任何文件)
```

### 在随身 WiFi / 软路由上“安全试运行”的推荐流程

逐步加大动作，每一步都能随时停下：

```sh
sh mirror.sh --check                  # 1. 只看检测结果, 零风险
sh mirror.sh --mirror ustc --dry-run  # 2. 预览将写入的内容, 仍不改文件
sh mirror.sh --mirror ustc --yes --no-update   # 3. 换源但先不联网 update
sh mirror.sh --mirror ustc --yes      # 4. 确认网络 OK 后再带 update
```

### 切换后网络坏了怎么办

```sh
sh mirror.sh --restore                # 一键回到切换前的源
```

---

## 真实设备冒烟测试

适合随身 WiFi / 软路由用户的最小验证流程（每一步都能停下并 `--restore`）：

```sh
sh mirror.sh --check
sh mirror.sh --mirror ustc --dry-run
sh mirror.sh --mirror ustc --yes --no-update
cat /etc/apt/sources.list 2>/dev/null || true
cat /etc/apk/repositories 2>/dev/null || true
cat /etc/opkg/distfeeds.conf 2>/dev/null || true
sh mirror.sh --restore
```

想试清华 TUNA（先预览，不写文件）：

```sh
sh mirror.sh --mirror tuna --dry-run
```

> ⚠️ **远程 SSH 连接设备时，第一次测试建议带 `--no-update`**：避免联网 `update` 过程卡住，让你误以为脚本失败。确认文件改对、`--restore` 能还原之后，再去掉 `--no-update`。

---

## 交互模式

直接执行（不带参数）进入交互菜单：

```sh
sh mirror.sh
```

流程：检测系统 → 显示系统信息 → 列出当前系统可用镜像（国内优先）→ 选择镜像 → 选择协议（默认 auto）→ 是否 update（默认 yes）→ 展示将修改的文件 → 最终确认。

- 所有输入都从 `/dev/tty` 读取，`curl | sh` 不会卡死。
- 输入无效会重新提示；Ctrl+C 干净退出。
- 没有 `/dev/tty` 时显示帮助并退出。

---

## 备份与恢复

修改任何文件前，`mirrorsh` 都会**先备份**：

- 默认备份目录：`/etc/mirrorsh/backup/<timestamp>/`
- 若 `/etc/mirrorsh` 不可写，回退到：`/root/mirrorsh-backup/<timestamp>/`
- 每次备份包含 `metadata`（distro/version/codename/mirror/protocol/source_files）与 `manifest`（恢复用的反向操作清单）。
- deb822 `.sources` 文件**不会被删除**，只会被备份并重命名为 `*.mirrorsh.bak.<ts>` 禁用。
- 备份失败则中止，不会继续修改系统。

恢复最近一次备份：

```sh
sh mirror.sh --restore
```

`--restore` 只还原 mirrorsh 改动过的源相关文件：把备份的原文件拷回、把被禁用的 `.sources` 改名还原、并移除 mirrorsh 新生成的 `sources.list`（若它原本不存在）。

恢复的健壮性保证：

- `--restore` 恢复的是**最近一次 mirrorsh 备份**（按时间戳取最新目录），它把系统恢复到**那次切换之前**的状态——**不是**切换到 official 源。
- 同一秒内连续切换两次，备份目录不会冲突（自动追加 `-1`、`-2` 后缀），每次切换都能独立恢复。
- 若 `manifest` 丢失、为空或损坏，`--restore` 会**清晰报错并中止**，绝不“盲目恢复”造成半套状态。
- 备份目录无法创建（不可写）时，切换会在**写任何文件之前**中止，系统保持原样。
- `--restore` **不会**执行 `update`。

### `--mirror official` 和 `--restore` 有什么区别？

| | `--mirror official` | `--restore` |
|---|---|---|
| 作用 | 把源**切换到官方源**（deb.debian.org 等），是一次新的切换，会再次备份 | 把源**还原到上一次切换之前**的样子（可能是某个镜像，也可能是官方） |
| 适用 | 想主动用官方/全球 CDN | 切换后出问题，想撤销 mirrorsh 的改动 |
| 是否备份 | 是（这是一次正常切换） | 否（这是反向操作） |

---

## 风险说明

```
mirrorsh 只负责切换软件源并执行 update，不会执行 upgrade/full-upgrade。
在随身 WiFi、软路由、OpenWrt 等小设备上，不建议随意执行系统大版本升级。
```

- `update` 失败**不等于**换源失败，可能只是 DNS、网络、镜像站临时异常、版本 EOL 或运营商劫持。
- `update` 失败时 `mirrorsh` **不会自动 restore**，只提示你可以手动 `--restore`。
- 第一版**不支持** EOL 的 `archive.debian.org` / `old-releases.ubuntu.com`；检测到可能过旧的系统时会提示。

---

## 故障排查

| 现象 | 可能原因 / 处理 |
|------|----------------|
| `apt update` 404 | 系统版本可能已 EOL（普通镜像无此版本）；考虑 archive/old-releases；或镜像暂未同步。 |
| `NO_PUBKEY` | 缺少 keyring，与换源无关；安装对应 `*-archive-keyring` 或导入公钥。 |
| DNS 解析失败 | 检查 `/etc/resolv.conf`，`nslookup 镜像域名`；小设备常需手动设 DNS。 |
| HTTPS 证书错误 | 缺 CA 证书或时间不准；用 `--protocol http`，或安装 `ca-certificates` 后重试。 |
| 系统时间不准 | `date` 检查；时间错会导致 TLS“证书尚未生效”。auto 模式会自动退回 HTTP。 |
| OpenWrt `opkg update` 失败 | 确认 `distfeeds.conf` 路径未被破坏；`mirrorsh` 只改基础地址，可 `--restore` 还原。 |
| Alpine `repository not found` | 确认分支（v3.19 / edge）正确；`apk update` 后再试。 |
| Ubuntu ports 架构源错误 | 非 amd64/i386 必须用 `/ubuntu-ports`；`mirrorsh` 已按架构自动选择。 |
| Debian/Ubuntu EOL 版本 | 普通镜像没有该版本；本版本不实现 archive，请自行处理。 |
| GitHub raw 无法访问 | 用 `scp`/`wget` 离线方式把 `mirror.sh` 拷到设备执行。 |
| curl/wget 不存在 | 用 `scp mirror.sh root@设备:/tmp/` 后 `sh /tmp/mirror.sh`。 |

---

## 测试与 CI

主测试是**纯离线**的：用临时 `ROOT_DIR` 模拟系统，不碰宿主 `/etc`，不依赖镜像站网络。覆盖 Debian/Ubuntu/Alpine/OpenWrt 的源生成、TUNA 全组合、deb822 禁用、dry-run、check、list、备份/恢复字节级一致、manifest 损坏处理、备份目录唯一性、非交互报错、交互菜单选号逻辑与无 tty 行为、HTTPS auto 判定与 HTTPS→HTTP 回退等共 126 个断言。

```sh
sh tests/run-tests.sh        # 任意 POSIX shell 均可
dash tests/run-tests.sh
busybox sh tests/run-tests.sh
```

### 发布前一键检查

`tests/preflight.sh` 顺序跑全部门禁（语法 → sh 测试 → dash/busybox/shellcheck，可选项缺失则 skipped），任一必需项失败返回非零：

```sh
sh tests/preflight.sh
```

### 开发者测试机制

测试通过环境变量把 mirrorsh 重定向到沙箱，绝不动真实系统：

```sh
ROOT_DIR=/tmp/test-root sh mirror.sh --mirror ustc --yes --no-update
```

| 变量 | 作用 |
|------|------|
| `ROOT_DIR` | 把 `/etc` 重定向到沙箱目录（生产默认就是 `/etc`） |
| `MIRRORSH_FAKE_ARCH` | 伪造 `uname -m`，用于测试 ports 架构（如 `aarch64`） |
| `MIRRORSH_NO_TTY=1` | 模拟“没有 /dev/tty”（管道执行 / headless CI） |
| `MIRRORSH_BACKUP_DIR` | 覆盖主备份根目录 |
| `MIRRORSH_NO_MAIN=1` | 只 `source` 脚本而不执行 `main`，用于单测内部函数 |

回退/协议逻辑的单测通过 `source` 脚本后**重定义** `run_update` / `system_year` 等函数来模拟 TLS 失败和系统时间，**完全不依赖真实网络**。

### GitHub Actions

- `.github/workflows/test.yml`：push / PR 时运行（权限 `contents: read`，全部离线、不写宿主 `/etc`），含：`sh` 与 `dash` 的 `-n` 语法检查 + 离线测试；**BusyBox sh** 测试（runner 不可用则 skipped）；**Alpine 容器**测试（Alpine 的 `/bin/sh` 即 BusyBox ash，仅只读挂载仓库目录）；`shellcheck -s sh mirror.sh tests/run-tests.sh tests/preflight.sh`（shellcheck 仅 CI 依赖，用户设备无需安装）。每个 job 都把 `pass/fail/skipped` 写入 Job Summary。
- `.github/workflows/mirror-check.yml`：**仅** `workflow_dispatch` 或每周定时触发的**健康检查**，在线探测**所有已启用**镜像组合（含 TUNA）的可达性（HEAD，失败回退小 GET），在 Job Summary 输出 Markdown 矩阵。`continue-on-error: true`，**绝不阻塞**主 CI——它失败只代表某镜像站当时不可达，**不代表主测试失败或脚本有问题**。该矩阵与代码 `resolve_base()`、本 README 表格三方保持一致。

---

## 发布检查（v0.1.0-rc1）

当前版本为发布候选 **v0.1.0-rc1**。打 tag 前：

1. 本地或 CI 通过一键检查：
   ```sh
   sh tests/preflight.sh
   ```
2. GitHub Actions `test.yml` 全绿。
3. 手动运行一次 `mirror-check.yml`，确认没有大面积 ❌（个别站点临时不可达可接受）。**因为本轮加入了 TUNA，务必确认 TUNA 那一行 5 个组合没有明显路径错误。**
4. 在真实小设备上至少执行：
   ```sh
   sh mirror.sh --check
   sh mirror.sh --list
   sh mirror.sh --mirror ustc --dry-run
   sh mirror.sh --mirror ustc --yes --no-update
   sh mirror.sh --restore
   ```
5. 随身 WiFi / OpenWrt 上先用 `--no-update` 验证文件修改与 `--restore`，确认无误再联网 update。
6. 打发布候选 tag：
   ```sh
   git tag v0.1.0-rc1
   git push origin v0.1.0-rc1
   ```
7. 正式 `v0.1.0` 前，至少收集一次真实 Debian / Ubuntu / Alpine / OpenWrt 设备的反馈。

---

## License

[MIT](LICENSE)
