#!/bin/sh
# mirrorsh release preflight — run every gate before tagging a release.
# POSIX sh. Read-only: never modifies the system (the test suite uses sandboxes).
#
#   sh tests/preflight.sh
#
# Required checks (failure => nonzero exit):
#   sh -n mirror.sh
#   sh -n tests/run-tests.sh
#   sh tests/run-tests.sh
# Optional checks (missing tool => "skipped", never a failure):
#   - dash tests/run-tests.sh
#   - busybox sh tests/run-tests.sh
#   - shellcheck linting of all three shell files

set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
REPO=$(cd -- "$HERE/.." && pwd)
cd "$REPO" || { echo "无法进入仓库目录: $REPO" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

FAIL=0
RESULTS=""

record() { RESULTS="${RESULTS}${1}|${2}
"; }

run_required() { # <name> <cmd...>
	name=$1; shift
	printf '\n>>> [required] %s\n' "$name"
	if "$@"; then record "$name" "pass"; else record "$name" "FAIL"; FAIL=1; fi
}

run_optional() { # <name> <tool> <cmd...>
	name=$1; tool=$2; shift 2
	if have "$tool"; then
		printf '\n>>> [optional] %s\n' "$name"
		if "$@"; then record "$name" "pass"; else record "$name" "FAIL"; FAIL=1; fi
	else
		printf '\n>>> [optional] %s  (%s 未安装)\n' "$name" "$tool"
		record "$name" "skipped"
	fi
}

printf '=== mirrorsh preflight (repo: %s) ===\n' "$REPO"

run_required "shell syntax: mirror.sh"       sh -n mirror.sh
run_required "shell syntax: run-tests.sh"    sh -n tests/run-tests.sh
run_required "shell syntax: preflight.sh"    sh -n tests/preflight.sh
run_required "sh tests"                      sh tests/run-tests.sh

run_optional "dash tests"        dash      dash tests/run-tests.sh
run_optional "busybox sh tests"  busybox   busybox sh tests/run-tests.sh
run_optional "shellcheck"        shellcheck shellcheck -s sh mirror.sh tests/run-tests.sh tests/preflight.sh

printf '\n=====================================\n'
printf ' preflight summary\n'
printf '=====================================\n'
printf '%s' "$RESULTS" | while IFS='|' read -r n s; do
	[ -n "$n" ] || continue
	printf '  %-28s %s\n' "$n" "$s"
done
printf '=====================================\n'

if [ "$FAIL" = 0 ]; then
	printf 'RESULT: PASS (所有必需项通过)\n'
else
	printf 'RESULT: FAIL (存在必需项失败)\n'
fi
exit "$FAIL"
