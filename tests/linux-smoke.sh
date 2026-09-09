#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY="${BASH_SOURCE[0]%/*}"
ROOT="$(cd -- "$SCRIPT_DIRECTORY/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/modelready-test.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

bash -n "$ROOT/modelready.sh"
python3 -m py_compile "$ROOT"/scripts/*.py
[[ "$(bash "$ROOT/modelready.sh" version)" == 'ModelReady 0.3.0' ]]
python3 "$ROOT/scripts/manifest_query.py" --manifest "$ROOT/config/profiles.json" --profile full --field packages | grep -q '^cvxpy'

bash "$ROOT/modelready.sh" doctor --profile base --environment-root "$TEST_ROOT/envs" --report-root "$TEST_ROOT/reports" --no-report

FAKE_ENV="$TEST_ROOT/envs/base"
mkdir -p "$FAKE_ENV/bin"
printf '#!/usr/bin/env sh\nexit 0\n' >"$FAKE_ENV/bin/python"
chmod +x "$FAKE_ENV/bin/python"
bash "$ROOT/modelready.sh" launch --profile base --environment-root "$TEST_ROOT/envs" --report-root "$TEST_ROOT/reports" --dry-run
bash "$ROOT/modelready.sh" uninstall --profile base --environment-root "$TEST_ROOT/envs" --dry-run --yes
[[ -d "$FAKE_ENV" ]]
bash "$ROOT/modelready.sh" uninstall --profile base --environment-root "$TEST_ROOT/envs" --yes
[[ ! -e "$FAKE_ENV" ]]

if bash "$ROOT/modelready.sh" uninstall --profile base --environment-root / --dry-run --yes; then
  echo 'unsafe root uninstall was not rejected' >&2
  exit 1
fi

echo 'ModelReady Linux smoke tests passed.'

