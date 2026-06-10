#!/bin/sh
# mirrorsh offline test suite (POSIX sh, no bats, never touches host /etc).
# Every test runs mirrorsh against a throwaway ROOT_DIR built from tests/fixtures.
#
# Developer test mechanism (also documented in README):
#   ROOT_DIR=<dir>            redirect /etc to a sandbox
#   MIRRORSH_FAKE_ARCH=<m>    fake `uname -m` (test ports architectures)
#   MIRRORSH_NO_TTY=1         simulate "no /dev/tty" (pipe / headless runner)
#   MIRRORSH_BACKUP_DIR=<dir> override the primary backup root
#   MIRRORSH_NO_MAIN=1        source the script without running, to unit-test fns

# Test-harness shellcheck exemptions (not applicable to ./mirrorsh itself):
#   SC1090 - we source ./mirrorsh dynamically via "$SCRIPT" on purpose
#   SC2034 - CODENAME/MIRROR/... are read by the sourced functions, not here
#   SC2329 - run_update/timestamp/system_year stubs are invoked indirectly
# shellcheck disable=SC1090,SC2034,SC2329
set -u

unset CDPATH 2>/dev/null || true
TESTS_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(cd -- "$TESTS_DIR/.." && pwd)
SCRIPT="$REPO_DIR/mirrorsh"
FIX="$TESTS_DIR/fixtures"
[ -f "$SCRIPT" ] || { echo "找不到 mirrorsh: $SCRIPT" >&2; exit 1; }

PASS=0
FAIL=0
SEQ=0
ROOTS=""

cleanup() { for r in $ROOTS; do rm -rf "$r" 2>/dev/null; done; }
trap cleanup EXIT INT TERM

new_root() { # <fixture-name> -> fresh ROOT_DIR with etc/ from the fixture
	SEQ=$((SEQ + 1))
	if command -v mktemp >/dev/null 2>&1; then
		r=$(mktemp -d 2>/dev/null) || r="${TMPDIR:-/tmp}/mirrorsh-test.$$.$SEQ"
	else
		r="${TMPDIR:-/tmp}/mirrorsh-test.$$.$SEQ"
	fi
	mkdir -p "$r"
	cp -r "$FIX/$1/etc" "$r/etc"
	ROOTS="$ROOTS $r"
	printf '%s' "$r"
}

ok()  { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$1"; [ -n "${2:-}" ] && printf '         %s\n' "$2"; return 0; }

assert_contains()     { if grep -qF "$2" "$1" 2>/dev/null; then ok "$3"; else bad "$3" "未找到: $2  (in $1)"; fi; }
assert_not_contains() { if grep -qF "$2" "$1" 2>/dev/null; then bad "$3" "不应出现: $2  (in $1)"; else ok "$3"; fi; }
assert_file_exists()  { if [ -f "$1" ]; then ok "$2"; else bad "$2" "缺少文件: $1"; fi; }
assert_no_file()      { if [ -f "$1" ]; then bad "$2" "不应存在: $1"; else ok "$2"; fi; }
assert_bytes_equal()  { if cmp -s "$1" "$2"; then ok "$3"; else bad "$3" "字节不一致: $1 vs $2"; fi; }
assert_glob_exists()  { f=0; for g in "$1"/$2; do [ -e "$g" ] && f=1; done; if [ "$f" = 1 ]; then ok "$3"; else bad "$3" "缺少匹配: $1/$2"; fi; }
assert_glob_count()   { c=0; for g in "$1"/$2; do [ -e "$g" ] && c=$((c+1)); done; if [ "$c" = "$3" ]; then ok "$4"; else bad "$4" "期望 $3 个, 实际 $c: $1/$2"; fi; }
assert_str_contains() { case "$1" in *"$2"*) ok "$3";; *) bad "$3" "输出缺少: $2";; esac; }
assert_str_lacks()    { case "$1" in *"$2"*) bad "$3" "输出不应含: $2";; *) ok "$3";; esac; }
assert_exit_nonzero() { if [ "$1" -ne 0 ]; then ok "$2"; else bad "$2" "期望非零退出, 得到 0"; fi; }
assert_exit_zero()    { if [ "$1" -eq 0 ]; then ok "$2"; else bad "$2" "期望 0, 得到 $1"; fi; }

section() { printf '\n== %s ==\n' "$1"; }

# run mirrorsh: run <root> <arch> -- <args...>
run() {
	rr=$1; ra=$2; shift 3
	ROOT_DIR="$rr" MIRRORSH_FAKE_ARCH="$ra" MIRRORSH_NO_TTY=1 \
		sh "$SCRIPT" "$@" </dev/null 2>&1
}

# ===========================================================================
section "Debian 源生成"

R=$(new_root debian-bullseye)
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
assert_contains     "$R/etc/apt/sources.list" "main contrib non-free" "bullseye 组件 main contrib non-free"
assert_not_contains "$R/etc/apt/sources.list" "non-free-firmware"      "bullseye 不生成 non-free-firmware"

R=$(new_root debian-bookworm)
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
assert_contains     "$R/etc/apt/sources.list" "non-free-firmware" "bookworm 生成 non-free-firmware"
assert_glob_exists  "$R/etc/apt/sources.list.d" "debian.sources.mirrorsh.bak.*" "bookworm 禁用并备份 debian.sources"
assert_glob_count   "$R/etc/apt/sources.list.d" "debian.sources.mirrorsh.bak.*" 1 "禁用产生唯一 .bak 文件 (IV.9)"
assert_no_file      "$R/etc/apt/sources.list.d/debian.sources" "bookworm 原 debian.sources 已禁用"

R=$(new_root debian-trixie)
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
assert_contains "$R/etc/apt/sources.list" "non-free-firmware" "trixie 生成 non-free-firmware"
assert_contains "$R/etc/apt/sources.list" "deb https://mirrors.ustc.edu.cn/debian trixie main" "trixie 主源 URL 正确"
assert_contains "$R/etc/apt/sources.list" "https://security.debian.org/debian-security trixie-security" "security 使用官方源 (https)"

# IV.4: security scheme follows --protocol http
R=$(new_root debian-trixie)
run "$R" x86_64 -- --mirror ustc --protocol http --yes --no-update >/dev/null
assert_contains "$R/etc/apt/sources.list" "http://security.debian.org/debian-security trixie-security" "security 跟随 http 协议 (IV.4)"

# IV.10: codename 识别失败 -> 报错且不修改
R=$(new_root debian-bookworm)
printf 'ID=debian\nNAME="Debian"\n' > "$R/etc/os-release"   # 无 codename
rm -f "$R/etc/debian_version"                                # 无回退
EXIT=0; OUT=$(run "$R" x86_64 -- --mirror ustc --yes --no-update) || EXIT=$?
assert_exit_nonzero "$EXIT" "codename 无法识别时报错退出 (IV.10)"
assert_no_file "$R/etc/apt/sources.list" "codename 失败时不创建 sources.list (IV.10)"

R=$(new_root debian-bookworm)
OUT=$(run "$R" x86_64 -- --mirror ustc --dry-run)
assert_no_file "$R/etc/apt/sources.list" "dry-run 不创建 sources.list"
assert_file_exists "$R/etc/apt/sources.list.d/debian.sources" "dry-run 不禁用 debian.sources"
assert_str_contains "$OUT" "dry-run" "dry-run 输出提示"

# ===========================================================================
section "Ubuntu 源生成"

R=$(new_root ubuntu-noble-amd64)
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
assert_contains     "$R/etc/apt/sources.list" "https://mirrors.ustc.edu.cn/ubuntu noble main restricted universe multiverse" "amd64 使用 /ubuntu + 全组件"
assert_not_contains "$R/etc/apt/sources.list" "ubuntu-ports" "amd64 不使用 ubuntu-ports"
assert_contains     "$R/etc/apt/sources.list" "noble-security"  "生成 security"
assert_contains     "$R/etc/apt/sources.list" "noble-updates"   "生成 updates"
assert_contains     "$R/etc/apt/sources.list" "noble-backports" "生成 backports"

# IV.6: ports 架构
for a in aarch64 armv7l riscv64 ppc64le s390x; do
	R=$(new_root ubuntu-noble-arm64)
	run "$R" "$a" -- --mirror ustc --protocol https --yes --no-update >/dev/null
	assert_contains "$R/etc/apt/sources.list" "/ubuntu-ports noble" "arch $a 使用 ubuntu-ports (IV.6)"
done

# i386 使用普通 /ubuntu
R=$(new_root ubuntu-noble-amd64)
run "$R" i686 -- --mirror ustc --protocol https --yes --no-update >/dev/null
assert_contains "$R/etc/apt/sources.list" "/ubuntu noble" "i386 使用 /ubuntu"
assert_not_contains "$R/etc/apt/sources.list" "ubuntu-ports" "i386 不用 ports"

# IV.7 / IV.8: official 普通 vs ports
R=$(new_root ubuntu-noble-amd64)
run "$R" x86_64 -- --mirror official --protocol https --yes --no-update >/dev/null
assert_contains "$R/etc/apt/sources.list" "https://archive.ubuntu.com/ubuntu noble" "official amd64 使用 archive.ubuntu.com (IV.7)"
R=$(new_root ubuntu-noble-arm64)
run "$R" aarch64 -- --mirror official --protocol https --yes --no-update >/dev/null
assert_contains "$R/etc/apt/sources.list" "https://ports.ubuntu.com/ubuntu-ports noble" "official arm64 使用 ports.ubuntu.com (IV.8)"

# 163 无 ports -> 报错
R=$(new_root ubuntu-noble-arm64)
EXIT=0; run "$R" aarch64 -- --mirror 163 --yes --no-update >/dev/null 2>&1 || EXIT=$?
assert_exit_nonzero "$EXIT" "163 不支持 ubuntu-ports 时报错退出"

# ===========================================================================
section "Alpine 源生成"

R=$(new_root alpine-3.19)
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
assert_contains     "$R/etc/apk/repositories" "https://mirrors.ustc.edu.cn/alpine/v3.19/main" "3.19.1 -> v3.19 main"
assert_contains     "$R/etc/apk/repositories" "https://mirrors.ustc.edu.cn/alpine/v3.19/community" "启用 community"
assert_not_contains "$R/etc/apk/repositories" "testing" "不启用 testing"

# V.2: 3.20.0 -> v3.20
R=$(new_root alpine-3.19)
printf '3.20.0\n' > "$R/etc/alpine-release"
rm -f "$R/etc/apk/repositories"   # 避免旧 v3.19 行干扰 edge 检测
run "$R" x86_64 -- --mirror aliyun --protocol https --yes --no-update >/dev/null
assert_contains "$R/etc/apk/repositories" "alpine/v3.20/main" "3.20.0 -> v3.20 (V.2)"

# V.3: edge 保持 edge
R=$(new_root alpine-edge)
run "$R" x86_64 -- --mirror aliyun --protocol https --yes --no-update >/dev/null
assert_contains "$R/etc/apk/repositories" "alpine/edge/main" "edge 保持 edge"

# ===========================================================================
section "OpenWrt 替换边界"

R=$(new_root openwrt)
run "$R" mips -- --mirror ustc --protocol https --yes --no-update >/dev/null
assert_contains     "$R/etc/opkg/distfeeds.conf" "https://mirrors.ustc.edu.cn/openwrt/releases/23.05.5/targets/ramips/mt7621/packages" "官方 https 切换, 保留完整路径 (III.1)"
assert_not_contains "$R/etc/opkg/distfeeds.conf" "downloads.openwrt.org" "原官方地址已替换"
assert_not_contains "$R/etc/opkg/distfeeds.conf" "openwrt/openwrt" "无重复路径 /openwrt/openwrt (III.8)"

# III.2 http, III.3 snapshots, III.5 非 openwrt URL, III.6 注释
R=$(new_root openwrt)
{
	printf 'src/gz openwrt_http http://downloads.openwrt.org/releases/23.05.5/packages/mipsel_24kc/base\n'
	printf 'src/gz openwrt_snap https://downloads.openwrt.org/snapshots/targets/qualcommax/ipq807x/packages\n'
	printf 'src/gz custom_feed https://example.com/my/custom/feed\n'
	printf '# this is a comment line\n'
} >> "$R/etc/opkg/distfeeds.conf"
run "$R" mips -- --mirror aliyun --protocol https --yes --no-update >/dev/null
assert_contains "$R/etc/opkg/distfeeds.conf" "https://mirrors.aliyun.com/openwrt/releases/23.05.5/packages/mipsel_24kc/base" "http 官方地址被切换 (III.2)"
assert_contains "$R/etc/opkg/distfeeds.conf" "https://mirrors.aliyun.com/openwrt/snapshots/targets/qualcommax/ipq807x/packages" "snapshots 路径保留 (III.3)"
assert_contains "$R/etc/opkg/distfeeds.conf" "https://example.com/my/custom/feed" "非 openwrt URL 不被误伤 (III.5)"
assert_contains "$R/etc/opkg/distfeeds.conf" "# this is a comment line" "注释行原样保留 (III.6)"

# III.4: 第三方 -> 第三方
R=$(new_root openwrt)
printf 'src/gz openwrt_base https://mirrors.ustc.edu.cn/openwrt/releases/23.05.5/packages/aarch64_cortex-a53/base\n' > "$R/etc/opkg/distfeeds.conf"
run "$R" mips -- --mirror aliyun --protocol https --yes --no-update >/dev/null
assert_contains     "$R/etc/opkg/distfeeds.conf" "https://mirrors.aliyun.com/openwrt/releases/23.05.5/packages/aarch64_cortex-a53/base" "第三方->第三方保留路径 (III.4)"
assert_not_contains "$R/etc/opkg/distfeeds.conf" "openwrt/openwrt" "第三方切换无重复路径"

# III.7: 缺失 distfeeds.conf -> 报错
R=$(new_root openwrt)
rm -f "$R/etc/opkg/distfeeds.conf"
EXIT=0; run "$R" mips -- --mirror ustc --yes --no-update >/dev/null || EXIT=$?
assert_exit_nonzero "$EXIT" "缺少 distfeeds.conf 时报错退出 (III.7)"

R=$(new_root openwrt)
run "$R" mips -- --mirror ustc --dry-run >/dev/null
assert_contains "$R/etc/opkg/distfeeds.conf" "downloads.openwrt.org" "dry-run 不修改 distfeeds.conf"

# ===========================================================================
section "备份 / 恢复边界"

# II.1: Debian sources.list + debian.sources 都存在 -> restore 后两者字节级一致
R=$(new_root debian-bookworm)
printf 'deb http://deb.debian.org/debian bookworm main\n' > "$R/etc/apt/sources.list"
cp "$R/etc/apt/sources.list" "$R/orig-list"
cp "$R/etc/apt/sources.list.d/debian.sources" "$R/orig-sources"
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
run "$R" x86_64 -- --restore >/dev/null
assert_bytes_equal "$R/etc/apt/sources.list" "$R/orig-list" "II.1 restore 还原原 sources.list (字节级)"
assert_bytes_equal "$R/etc/apt/sources.list.d/debian.sources" "$R/orig-sources" "II.1 restore 还原 debian.sources (字节级)"

# II.2: 仅 debian.sources -> restore 移除生成的 sources.list, 还原 debian.sources
R=$(new_root debian-bookworm)
cp "$R/etc/apt/sources.list.d/debian.sources" "$R/orig-sources"
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
run "$R" x86_64 -- --restore >/dev/null
assert_no_file "$R/etc/apt/sources.list" "II.2 restore 移除 mirrorsh 生成的 sources.list"
assert_bytes_equal "$R/etc/apt/sources.list.d/debian.sources" "$R/orig-sources" "II.2 restore 还原 debian.sources (字节级)"

# II.3: Ubuntu 两种情况
R=$(new_root ubuntu-noble-arm64)
cp "$R/etc/apt/sources.list.d/ubuntu.sources" "$R/orig-ubuntu"
run "$R" aarch64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
run "$R" aarch64 -- --restore >/dev/null
assert_no_file "$R/etc/apt/sources.list" "II.3 ubuntu restore 移除生成的 sources.list"
assert_bytes_equal "$R/etc/apt/sources.list.d/ubuntu.sources" "$R/orig-ubuntu" "II.3 ubuntu restore 还原 ubuntu.sources"

R=$(new_root ubuntu-noble-amd64)
mkdir -p "$R/etc/apt"
printf 'deb http://archive.ubuntu.com/ubuntu noble main\n' > "$R/etc/apt/sources.list"
cp "$R/etc/apt/sources.list" "$R/orig-ulist"
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
run "$R" x86_64 -- --restore >/dev/null
assert_bytes_equal "$R/etc/apt/sources.list" "$R/orig-ulist" "II.3 ubuntu 已有 sources.list 字节级还原"

# II.4: Alpine repositories 字节级一致
R=$(new_root alpine-3.19)
cp "$R/etc/apk/repositories" "$R/orig-apk"
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
run "$R" x86_64 -- --restore >/dev/null
assert_bytes_equal "$R/etc/apk/repositories" "$R/orig-apk" "II.4 alpine repositories 字节级还原"

# V.5: repositories 含注释/空行/旧源 -> 切换替换为 2 行, restore 字节级还原
R=$(new_root alpine-3.19)
{
	printf '# old custom mirror\n'
	printf '\n'
	printf 'https://old.example.com/alpine/v3.19/main\n'
} > "$R/etc/apk/repositories"
cp "$R/etc/apk/repositories" "$R/orig-apk2"
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
assert_not_contains "$R/etc/apk/repositories" "old.example.com" "V.5 旧源被替换"
assert_not_contains "$R/etc/apk/repositories" "# old custom mirror" "V.5 注释被替换 (完整重写)"
run "$R" x86_64 -- --restore >/dev/null
assert_bytes_equal "$R/etc/apk/repositories" "$R/orig-apk2" "V.5 restore 字节级还原原始 repositories"

# V.6: repositories 不存在 -> 创建; restore 删除
R=$(new_root alpine-3.19)
rm -f "$R/etc/apk/repositories"
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
assert_file_exists "$R/etc/apk/repositories" "V.6 原本不存在时创建 repositories"
run "$R" x86_64 -- --restore >/dev/null
assert_no_file "$R/etc/apk/repositories" "V.6 restore 删除 mirrorsh 创建的 repositories"

# II.5: OpenWrt distfeeds.conf 字节级一致
R=$(new_root openwrt)
cp "$R/etc/opkg/distfeeds.conf" "$R/orig-ow"
run "$R" mips -- --mirror ustc --protocol https --yes --no-update >/dev/null
run "$R" mips -- --restore >/dev/null
assert_bytes_equal "$R/etc/opkg/distfeeds.conf" "$R/orig-ow" "II.5 openwrt distfeeds.conf 字节级还原"

# II.6: 没有任何备份 -> --restore 清晰报错, 不把 glob 当目录
R=$(new_root debian-bookworm)
EXIT=0; OUT=$(run "$R" x86_64 -- --restore) || EXIT=$?
assert_exit_nonzero "$EXIT" "II.6 无备份时 --restore 报错退出"
assert_str_lacks "$OUT" '*/' "II.6 不把 glob 字符串当成目录"

# II.9: manifest 损坏 -> 报错且不恢复
R=$(new_root debian-bookworm)
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
cp "$R/etc/apt/sources.list" "$R/after-switch"
for d in "$R/etc/mirrorsh/backup"/*/; do printf 'GARBAGE not a real op\n' > "$d/manifest"; done
EXIT=0; OUT=$(run "$R" x86_64 -- --restore) || EXIT=$?
assert_exit_nonzero "$EXIT" "II.9 manifest 损坏时报错退出"
assert_str_contains "$OUT" "损坏" "II.9 报错信息提到损坏"
assert_bytes_equal "$R/etc/apt/sources.list" "$R/after-switch" "II.9 损坏时不执行任何恢复"

# II.9b: manifest 为空 -> 报错
R=$(new_root debian-bookworm)
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
for d in "$R/etc/mirrorsh/backup"/*/; do : > "$d/manifest"; done
EXIT=0; OUT=$(run "$R" x86_64 -- --restore) || EXIT=$?
assert_exit_nonzero "$EXIT" "II.9b 空 manifest 时报错退出"

# II.10: restore 不执行 update
R=$(new_root alpine-3.19)
run "$R" x86_64 -- --mirror ustc --protocol https --yes --no-update >/dev/null
OUT=$(run "$R" x86_64 -- --restore)
assert_str_lacks "$OUT" "执行 update" "II.10 restore 不触发 update"

# II.8: 备份目录无法创建 -> 中止, 不修改系统
R=$(new_root debian-bookworm)
: > "$R/blocker"        # a FILE where a dir parent is needed
: > "$R/root"           # block the /root fallback too
EXIT=0
OUT=$(ROOT_DIR="$R" MIRRORSH_FAKE_ARCH=x86_64 MIRRORSH_NO_TTY=1 MIRRORSH_BACKUP_DIR="$R/blocker/backup" \
	sh "$SCRIPT" --mirror ustc --yes --no-update </dev/null 2>&1) || EXIT=$?
assert_exit_nonzero "$EXIT" "II.8 备份目录不可创建时报错退出"
assert_no_file "$R/etc/apt/sources.list" "II.8 备份失败时不修改系统 (无 sources.list)"
assert_file_exists "$R/etc/apt/sources.list.d/debian.sources" "II.8 备份失败时不禁用 debian.sources"

# ===========================================================================
section "通用 / 交互安全"

R=$(new_root debian-bookworm)
OUT=$(run "$R" x86_64 -- --check)
assert_str_contains "$OUT" "distro:            debian"   "--check 输出 distro"
assert_str_contains "$OUT" "codename:          bookworm" "--check 输出 codename"
assert_no_file "$R/etc/apt/sources.list" "--check 不修改文件"

R=$(new_root debian-bookworm)
OUT=$(run "$R" x86_64 -- --list)
assert_str_contains "$OUT" "ustc"   "--list 输出镜像列表"
assert_str_contains "$OUT" "aliyun" "--list 含 aliyun"

# 非交互无 --mirror
R=$(new_root debian-bookworm)
EXIT=0; OUT=$(run "$R" x86_64 -- --yes) || EXIT=$?
assert_exit_nonzero "$EXIT" "非交互且无 --mirror 时报错退出"
assert_str_contains "$OUT" "--mirror" "错误信息提到 --mirror"

# VII.3 / VII.4: 无参数 + 无 tty -> help, exit 0, 不修改 (管道执行)
R=$(new_root debian-bookworm)
EXIT=0; OUT=$(run "$R" x86_64 --) || EXIT=$?
assert_exit_zero "$EXIT" "VII.3 无参数无 tty 退出码 0"
assert_str_contains "$OUT" "用法:" "VII.3 无参数无 tty 显示帮助"
assert_no_file "$R/etc/apt/sources.list" "VII.3 无参数无 tty 不修改文件"

R=$(new_root debian-bookworm)
EXIT=0; OUT=$(printf 'garbage\n' | ROOT_DIR="$R" MIRRORSH_FAKE_ARCH=x86_64 MIRRORSH_NO_TTY=1 sh "$SCRIPT") || EXIT=$?
assert_str_contains "$OUT" "用法:" "VII.4 cat mirrorsh | sh 不卡住, 显示帮助"

# VII.7: 未 --yes 且非 dry-run 且无 tty -> 报错, 确认前不写文件
R=$(new_root debian-bookworm)
EXIT=0; OUT=$(run "$R" x86_64 -- --mirror ustc --no-update) || EXIT=$?
assert_exit_nonzero "$EXIT" "VII.7 无 --yes 无 tty 时报错 (不卡住)"
assert_no_file "$R/etc/apt/sources.list" "VII.7 最终确认前不写文件"

# 镜像不支持当前发行版
R=$(new_root openwrt)
EXIT=0; run "$R" mips -- --mirror 163 --yes --no-update >/dev/null 2>&1 || EXIT=$?
assert_exit_nonzero "$EXIT" "163 不支持 OpenWrt 时报错退出"

# ===========================================================================
section "Sourced 单元测试 (协议判定 / 回退 / 备份唯一性)"

U=$(new_root debian-bookworm)
( MIRRORSH_NO_MAIN=1 ROOT_DIR="$U" . "$SCRIPT"
  # debian_comp across codenames (IV.1/2/3)
  CODENAME=bullseye; DISTRO_VERSION=11; [ "$(debian_comp)" = "main contrib non-free" ] && echo COMP_BULLSEYE_OK
  CODENAME=bookworm; [ "$(debian_comp)" = "main contrib non-free non-free-firmware" ] && echo COMP_BOOKWORM_OK
  CODENAME=trixie;   [ "$(debian_comp)" = "main contrib non-free non-free-firmware" ] && echo COMP_TRIXIE_OK
  CODENAME=sid;      [ "$(debian_comp)" = "main contrib non-free non-free-firmware" ] && echo COMP_SID_OK
  CODENAME=forky;    [ "$(debian_comp)" = "main contrib non-free non-free-firmware" ] && echo COMP_FORKY_OK

  # tls_error
  tls_error "gpgv: x509 certificate has expired" && echo TLS_HIT
  tls_error "E: Failed to fetch ... 404 Not Found" || echo NON_TLS_OK

  # decide_scheme: VI.4/VI.5 forced
  PROTOCOL=http;  [ "$(decide_scheme)" = http ]  && echo FORCE_HTTP_OK
  PROTOCOL=https; [ "$(decide_scheme)" = https ] && echo FORCE_HTTPS_OK

  # VI.1: auto + no CA -> http
  PROTOCOL=auto;  [ "$(decide_scheme)" = http ]  && echo AUTO_NOCA_HTTP_OK

  # VI.3: auto + CA present + year ok -> https
  mkdir -p "$U/etc/ssl/certs"; : > "$U/etc/ssl/certs/ca-certificates.crt"
  PROTOCOL=auto;  [ "$(decide_scheme)" = https ] && echo AUTO_CA_HTTPS_OK

  # VI.2: auto + CA present + year < 2020 -> http
  system_year() { printf '2019'; }
  PROTOCOL=auto;  [ "$(decide_scheme)" = http ]  && echo AUTO_OLDYEAR_HTTP_OK
) > "$U/out.txt" 2>&1
OUT=$(cat "$U/out.txt")
assert_str_contains "$OUT" "COMP_BULLSEYE_OK"     "IV.2 bullseye 组件无 firmware"
assert_str_contains "$OUT" "COMP_BOOKWORM_OK"     "IV.1 bookworm 组件含 firmware"
assert_str_contains "$OUT" "COMP_TRIXIE_OK"       "IV.1 trixie 组件含 firmware"
assert_str_contains "$OUT" "COMP_SID_OK"          "IV.3 sid 组件含 firmware"
assert_str_contains "$OUT" "COMP_FORKY_OK"        "IV.3 forky 组件含 firmware"
assert_str_contains "$OUT" "TLS_HIT"              "tls_error 命中 TLS 关键词"
assert_str_contains "$OUT" "NON_TLS_OK"           "tls_error 忽略 404"
assert_str_contains "$OUT" "FORCE_HTTP_OK"        "VI.4 --protocol http 强制 http"
assert_str_contains "$OUT" "FORCE_HTTPS_OK"       "VI.5 --protocol https 强制 https"
assert_str_contains "$OUT" "AUTO_NOCA_HTTP_OK"    "VI.1 auto 无 CA -> http"
assert_str_contains "$OUT" "AUTO_CA_HTTPS_OK"     "VI.3 auto + CA + 年份正常 -> https"
assert_str_contains "$OUT" "AUTO_OLDYEAR_HTTP_OK" "VI.2 auto + 年份<2020 -> http"

# 备份目录同秒唯一性 (II.7) — 固定 timestamp, 连续两次 backup_init
U=$(new_root debian-bookworm)
( MIRRORSH_NO_MAIN=1 ROOT_DIR="$U" . "$SCRIPT"
  timestamp() { printf '20260610-120000'; }
  backup_init; d1="$BACKUP_DIR"
  backup_init; d2="$BACKUP_DIR"
  [ "$d1" != "$d2" ] && echo UNIQUE_OK || echo UNIQUE_BAD
  printf 'D1=%s\nD2=%s\n' "$d1" "$d2"
) > "$U/out.txt" 2>&1
OUT=$(cat "$U/out.txt")
assert_str_contains "$OUT" "UNIQUE_OK"            "II.7 同秒两次备份目录不冲突"
assert_str_contains "$OUT" "20260610-120000-1"    "II.7 冲突时追加 -1 后缀"

# VI.6/VI.7: auto + HTTPS update TLS 失败 -> 回退 HTTP 重试, 改写 http, 不自动 restore
FB=$(new_root debian-bookworm)
CNT="$FB/counter"; echo 0 > "$CNT"
( MIRRORSH_NO_MAIN=1 ROOT_DIR="$FB" MIRRORSH_FAKE_ARCH=x86_64 . "$SCRIPT"
  setup_colors; detect_system
  MIRROR=ustc; PROTOCOL=auto; SCHEME=https; DO_UPDATE=1; YES=1
  run_update() {
    n=$(cat "$CNT"); n=$((n + 1)); echo "$n" > "$CNT"
    if [ "$n" = 1 ]; then echo "Err: SSL certificate problem: certificate has expired"; return 1; fi
    echo "Reading package lists... Done"; return 0
  }
  build_plan; apply_plan >/dev/null
  run_update_with_fallback >/dev/null 2>&1
  echo "FINAL_SCHEME=$SCHEME"
) > "$FB/out.txt" 2>&1
OUT=$(cat "$FB/out.txt")
assert_str_contains "$OUT" "FINAL_SCHEME=http" "VI.6 TLS 失败后回退 HTTP"
assert_contains "$FB/etc/apt/sources.list" "deb http://mirrors.ustc.edu.cn/debian"      "VI.7 回退后主源改写为 http"
assert_contains "$FB/etc/apt/sources.list" "http://security.debian.org/debian-security" "VI.7 回退后 security 也是 http (IV.4)"
assert_file_exists "$FB/etc/apt/sources.list" "VI.8 回退失败不自动 restore (文件仍在)"

# VI.5: --protocol https + TLS 失败 -> 不回退
NF=$(new_root debian-bookworm)
( MIRRORSH_NO_MAIN=1 ROOT_DIR="$NF" MIRRORSH_FAKE_ARCH=x86_64 . "$SCRIPT"
  setup_colors; detect_system
  MIRROR=ustc; PROTOCOL=https; SCHEME=https; DO_UPDATE=1; YES=1
  run_update() { echo "SSL certificate problem: certificate has expired"; return 1; }
  build_plan; apply_plan >/dev/null
  run_update_with_fallback >/dev/null 2>&1
  echo "FINAL_SCHEME=$SCHEME"
) > "$NF/out.txt" 2>&1
OUT=$(cat "$NF/out.txt")
assert_str_contains "$OUT" "FINAL_SCHEME=https" "VI.5 强制 https 时 TLS 失败不回退"
assert_contains "$NF/etc/apt/sources.list" "deb https://mirrors.ustc.edu.cn/debian" "VI.5 强制 https 源保持 https"

# VI.8: 回退后仍失败 -> 提示备份路径与 --restore, 不自动 restore
HINT=$(new_root debian-bookworm)
( MIRRORSH_NO_MAIN=1 ROOT_DIR="$HINT" MIRRORSH_FAKE_ARCH=x86_64 . "$SCRIPT"
  setup_colors; detect_system
  MIRROR=ustc; PROTOCOL=auto; SCHEME=https; DO_UPDATE=1; YES=1
  run_update() { echo "TLS handshake failure"; return 1; }   # 一直失败
  build_plan; apply_plan >/dev/null
  run_update_with_fallback 2>&1
) > "$HINT/out.txt" 2>&1
OUT=$(cat "$HINT/out.txt")
assert_str_contains "$OUT" "--restore"   "VI.8 仍失败时提示 --restore"
assert_str_contains "$OUT" "备份目录"     "VI.8 仍失败时提示备份目录"
assert_file_exists "$HINT/etc/apt/sources.list" "VI.8 仍失败时不自动 restore"

# ===========================================================================
section "清华 TUNA 镜像"

R=$(new_root debian-bookworm)
run "$R" x86_64 -- --mirror tuna --protocol https --yes --no-update >/dev/null
assert_contains "$R/etc/apt/sources.list" "deb https://mirrors.tuna.tsinghua.edu.cn/debian bookworm" "tuna 生成 Debian 源"
assert_contains "$R/etc/apt/sources.list" "https://security.debian.org/debian-security" "tuna 不改 Debian security (仍官方)"

R=$(new_root ubuntu-noble-amd64)
run "$R" x86_64 -- --mirror tuna --protocol https --yes --no-update >/dev/null
assert_contains "$R/etc/apt/sources.list" "https://mirrors.tuna.tsinghua.edu.cn/ubuntu noble" "tuna 生成 Ubuntu 源 (/ubuntu)"

R=$(new_root ubuntu-noble-arm64)
run "$R" aarch64 -- --mirror tuna --protocol https --yes --no-update >/dev/null
assert_contains "$R/etc/apt/sources.list" "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports noble" "tuna 生成 Ubuntu Ports 源"

R=$(new_root alpine-3.19)
run "$R" x86_64 -- --mirror tuna --protocol https --yes --no-update >/dev/null
assert_contains "$R/etc/apk/repositories" "https://mirrors.tuna.tsinghua.edu.cn/alpine/v3.19/main" "tuna 生成 Alpine 源"

R=$(new_root openwrt)
run "$R" mips -- --mirror tuna --protocol https --yes --no-update >/dev/null
assert_contains     "$R/etc/opkg/distfeeds.conf" "https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/23.05.5/targets/ramips/mt7621/packages" "tuna 生成 OpenWrt 源, 保留路径"
assert_not_contains "$R/etc/opkg/distfeeds.conf" "openwrt/openwrt" "tuna OpenWrt 无重复路径"

# OpenWrt 从 TUNA 切到其他镜像: 只替换基础地址, 保留 releases/.../snapshots/...
R=$(new_root openwrt)
{
	printf 'src/gz openwrt_base https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/23.05.5/packages/aarch64_cortex-a53/base\n'
	printf 'src/gz openwrt_snap https://mirrors.tuna.tsinghua.edu.cn/openwrt/snapshots/targets/qualcommax/ipq807x/packages\n'
} > "$R/etc/opkg/distfeeds.conf"
run "$R" mips -- --mirror ustc --protocol https --yes --no-update >/dev/null
assert_contains     "$R/etc/opkg/distfeeds.conf" "https://mirrors.ustc.edu.cn/openwrt/releases/23.05.5/packages/aarch64_cortex-a53/base" "TUNA->USTC 保留 releases 路径"
assert_contains     "$R/etc/opkg/distfeeds.conf" "https://mirrors.ustc.edu.cn/openwrt/snapshots/targets/qualcommax/ipq807x/packages" "TUNA->USTC 保留 snapshots 路径"
assert_not_contains "$R/etc/opkg/distfeeds.conf" "tuna" "TUNA 基础地址已被替换"

R=$(new_root debian-bookworm)
OUT=$(run "$R" x86_64 -- --list)
assert_str_contains "$OUT" "tuna" "--list 包含 tuna"
assert_str_contains "$OUT" "清华 TUNA" "--list 显示 tuna 中文名"

# ===========================================================================
section "交互菜单逻辑单测 (resolve_menu_choice)"

U=$(new_root debian-bookworm)
( MIRRORSH_NO_MAIN=1 ROOT_DIR="$U" . "$SCRIPT"
  [ "$(resolve_menu_choice 1 1:ustc 2:tuna 3:aliyun 4:official)" = ustc ]     && echo CHOICE_1_OK
  [ "$(resolve_menu_choice 2 1:ustc 2:tuna 3:aliyun 4:official)" = tuna ]     && echo CHOICE_TUNA_OK
  [ "$(resolve_menu_choice 4 1:ustc 2:tuna 3:aliyun 4:official)" = official ] && echo CHOICE_4_OK
  [ "$(resolve_menu_choice 9 1:ustc 2:tuna)" = invalid ]   && echo CHOICE_BAD_OK
  [ "$(resolve_menu_choice abc 1:ustc 2:tuna)" = invalid ] && echo CHOICE_NONNUM_OK
  [ "$(resolve_menu_choice '' 1:ustc 2:tuna)" = invalid ]  && echo CHOICE_EMPTY_OK
  if ! resolve_menu_choice 9 1:ustc 2:tuna >/dev/null; then echo CHOICE_BAD_RC_OK; fi
) > "$U/out.txt" 2>&1
OUT=$(cat "$U/out.txt")
assert_str_contains "$OUT" "CHOICE_1_OK"      "menu 1 -> 第一个国内镜像 (ustc)"
assert_str_contains "$OUT" "CHOICE_TUNA_OK"   "menu tuna 对应编号 -> tuna"
assert_str_contains "$OUT" "CHOICE_4_OK"      "menu 选 official"
assert_str_contains "$OUT" "CHOICE_BAD_OK"    "menu 越界编号 -> invalid"
assert_str_contains "$OUT" "CHOICE_NONNUM_OK" "menu 非数字 -> invalid"
assert_str_contains "$OUT" "CHOICE_EMPTY_OK"  "menu 空输入 -> invalid"
assert_str_contains "$OUT" "CHOICE_BAD_RC_OK" "menu 无效输入返回非零"

# ===========================================================================
printf '\n=====================================\n'
printf '  PASS: %s   FAIL: %s\n' "$PASS" "$FAIL"
printf '=====================================\n'
[ "$FAIL" = 0 ]
