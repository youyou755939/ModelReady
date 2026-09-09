#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY="${BASH_SOURCE[0]%/*}"
ROOT="$(cd -- "$SCRIPT_DIRECTORY/.." && pwd -P)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/modelready-test.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

bash -n "$ROOT/modelready.sh"
python3 -m py_compile "$ROOT"/scripts/*.py
[[ "$(bash "$ROOT/modelready.sh" version)" == 'ModelReady 0.4.0' ]]
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

ROLLBACK_STATE="$TEST_ROOT/rollback-state"
ROLLBACK_BOUNDARY="$TEST_ROOT/rollback-payload"
ROLLBACK_TARGET="$ROLLBACK_BOUNDARY/environment"
mkdir -p "$ROLLBACK_STATE" "$ROLLBACK_TARGET"
printf 'temporary rollback fixture\n' >"$ROLLBACK_TARGET/marker.txt"
printf 'must survive rollback\n' >"$ROLLBACK_BOUNDARY/user-file.txt"
printf '# ModelReady rollback journal v1\nempty-directory\tnone\t%s\t%s\nenvironment\tnone\t%s\t%s\n' \
  "$ROLLBACK_BOUNDARY" "$TEST_ROOT" "$ROLLBACK_TARGET" "$ROLLBACK_BOUNDARY" >"$ROLLBACK_STATE/rollback-journal.tsv"
MODELREADY_STATE_ROOT="$ROLLBACK_STATE" bash "$ROOT/modelready.sh" rollback --dry-run --yes
[[ -d "$ROLLBACK_TARGET" ]]
MODELREADY_STATE_ROOT="$ROLLBACK_STATE" bash "$ROOT/modelready.sh" rollback --yes
[[ ! -e "$ROLLBACK_TARGET" ]]
[[ -f "$ROLLBACK_BOUNDARY/user-file.txt" ]]
[[ ! -e "$ROLLBACK_STATE/rollback-journal.tsv" ]]

UNSAFE_STATE="$TEST_ROOT/unsafe-state"
mkdir -p "$UNSAFE_STATE"
printf '# ModelReady rollback journal v1\ndirectory\tnone\t/\t/\n' >"$UNSAFE_STATE/rollback-journal.tsv"
if MODELREADY_STATE_ROOT="$UNSAFE_STATE" bash "$ROOT/modelready.sh" rollback --yes; then
  echo 'unsafe root rollback was not rejected' >&2
  exit 1
fi
[[ -f "$UNSAFE_STATE/rollback-journal.tsv" ]]

echo 'ModelReady Linux smoke tests passed.'
