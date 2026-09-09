#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIRECTORY="${BASH_SOURCE[0]%/*}"
if [[ "$SCRIPT_DIRECTORY" == "${BASH_SOURCE[0]}" ]]; then SCRIPT_DIRECTORY='.'; fi
PROJECT_ROOT="$(cd -- "$SCRIPT_DIRECTORY" && pwd -P)"
MANIFEST="$PROJECT_ROOT/config/profiles.json"
USER_HOME="${HOME:-/tmp}"
COMMAND="doctor"
PROFILE="base"
SOURCE="official"
ENVIRONMENT_ROOT="${XDG_DATA_HOME:-${USER_HOME}/.local/share}/modelready/envs"
REPORT_ROOT="${XDG_STATE_HOME:-${USER_HOME}/.local/state}/modelready/reports"
DRY_RUN=false
ASSUME_YES=false
NO_REPORT=false

usage() {
  cat <<'EOF'
ModelReady — Linux/WSL mathematical-modeling environment manager

Usage:
  ./modelready.sh <command> [options]

Commands:
  doctor      Check the selected environment without changing it
  install     Install a profile and run verification
  repair      Repair/update a profile and run verification
  verify      Run reproducible functional checks
  launch      Start JupyterLab from the selected profile
  uninstall   Remove only the selected Python environment
  profiles    List available profiles
  version     Print the ModelReady version

Options:
  --profile <base|optimization|ml|paper|full>
  --source <official|china>
  --environment-root <path>
  --report-root <path>
  --dry-run
  --yes
  --no-report
EOF
}

if (($# > 0)) && [[ "$1" != -* ]]; then
  COMMAND="$1"
  shift
fi
while (($# > 0)); do
  case "$1" in
    --profile) PROFILE="${2:?missing value for --profile}"; shift 2 ;;
    --source) SOURCE="${2:?missing value for --source}"; shift 2 ;;
    --environment-root) ENVIRONMENT_ROOT="${2:?missing value for --environment-root}"; shift 2 ;;
    --report-root) REPORT_ROOT="${2:?missing value for --report-root}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --yes) ASSUME_YES=true; shift ;;
    --no-report) NO_REPORT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$COMMAND" in doctor|install|repair|verify|launch|uninstall|profiles|version) ;; *) echo "Unknown command: $COMMAND" >&2; exit 2 ;; esac
case "$PROFILE" in base|optimization|ml|paper|full) ;; *) echo "Unknown profile: $PROFILE" >&2; exit 2 ;; esac
case "$SOURCE" in official|china) ;; *) echo "Unknown source: $SOURCE" >&2; exit 2 ;; esac

command_exists() { command -v "$1" >/dev/null 2>&1; }

run_command() {
  printf '> '
  printf '%q ' "$@"
  printf '\n'
  if [[ "$DRY_RUN" == true ]]; then return 0; fi
  "$@"
}

run_privileged() {
  if [[ "${EUID}" -eq 0 ]]; then
    run_command "$@"
  elif command_exists sudo; then
    run_command sudo "$@"
  elif [[ "$DRY_RUN" == true ]]; then
    run_command sudo "$@"
  else
    echo "ModelReady failed: root privileges or sudo are required for apt." >&2
    return 1
  fi
}

manifest_value() {
  python3 "$PROJECT_ROOT/scripts/manifest_query.py" --manifest "$MANIFEST" --profile "$PROFILE" --field "$1"
}

profile_has_paper() {
  [[ "$PROFILE" == "paper" || "$PROFILE" == "full" ]]
}

print_result() {
  local status="$1" area="$2" item="$3" detail="$4"
  local color='' reset=''
  if [[ -t 1 ]]; then
    reset=$'\033[0m'
    case "$status" in PASS) color=$'\033[32m' ;; MISSING|FAIL) color=$'\033[31m' ;; WARN) color=$'\033[33m' ;; INFO) color=$'\033[90m' ;; esac
  fi
  printf '%s[%-7s]%s %s / %s — %s\n' "$color" "$status" "$reset" "$area" "$item" "$detail"
}

add_doctor_result() {
  local status="$1" area="$2" item="$3" required="$4" detail="$5"
  detail="${detail//$'\t'/ }"
  detail="${detail//$'\n'/ }"
  print_result "$status" "$area" "$item" "$detail"
  printf '%s\t%s\t%s\t%s\t%s\n' "$status" "$area" "$item" "$required" "$detail" >>"$DOCTOR_TSV"
  if [[ "$required" == true && ( "$status" == MISSING || "$status" == FAIL ) ]]; then
    DOCTOR_MISSING=$((DOCTOR_MISSING + 1))
  fi
}

detect_platform() {
  DISTRO_ID="unknown"
  DISTRO_VERSION="unknown"
  PLATFORM_KIND="linux"
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_VERSION="${VERSION_ID:-unknown}"
  fi
  if grep -qi 'microsoft-standard-WSL2' /proc/sys/kernel/osrelease 2>/dev/null; then PLATFORM_KIND="wsl2"
  elif grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then PLATFORM_KIND="wsl"; fi
}

platform_supported() {
  case "$DISTRO_ID:$DISTRO_VERSION" in
    ubuntu:22.04|ubuntu:24.04|debian:12) return 0 ;;
    *) return 1 ;;
  esac
}

doctor() {
  mkdir -p "$REPORT_ROOT" || { echo "Cannot create report directory: $REPORT_ROOT" >&2; return 1; }
  DOCTOR_TSV="$(mktemp "$REPORT_ROOT/.doctor.XXXXXX.tsv")"
  DOCTOR_MISSING=0
  trap 'rm -f -- "$DOCTOR_TSV"' RETURN
  detect_platform

  if [[ "$(uname -s)" == Linux ]] && platform_supported; then
    add_doctor_result PASS System Platform true "$DISTRO_ID $DISTRO_VERSION ($PLATFORM_KIND, $(uname -m))"
  else
    add_doctor_result MISSING System Platform true "Supported: Ubuntu 22.04/24.04, Debian 12, or WSL2 based on them"
  fi

  local required_disk=12
  if command_exists python3; then required_disk="$(manifest_value disk)"; fi
  local free_kb free_gb
  free_kb="$(df -Pk "${HOME:-/}" | awk 'NR==2 {print $4}')"
  free_gb=$((free_kb / 1024 / 1024))
  if ((free_gb >= required_disk)); then
    add_doctor_result PASS System Disk true "${free_gb} GB available; ${required_disk} GB recommended"
  else
    add_doctor_result MISSING System Disk true "${free_gb} GB available; ${required_disk} GB recommended"
  fi

  for tool in curl uv python3 code; do
    if command_exists "$tool"; then
      add_doctor_result PASS Tools "$tool" false "$(command -v "$tool")"
    else
      add_doctor_result INFO Tools "$tool" false "not found"
    fi
  done
  if command_exists uv || command_exists curl || command_exists wget; then
    add_doctor_result PASS Tools Bootstrap true "uv, curl, or wget is available"
  else
    add_doctor_result MISSING Tools Bootstrap true "curl or wget is required to bootstrap uv"
  fi

  if profile_has_paper; then
    for spec in 'pandoc:pandoc' 'graphviz:dot'; do
      local label="${spec%%:*}" binary="${spec##*:}"
      if command_exists "$binary"; then add_doctor_result PASS 'System tools' "$label" true "$(command -v "$binary")"
      else add_doctor_result MISSING 'System tools' "$label" true 'installable through apt'; fi
    done
    if command_exists xelatex || command_exists typst; then
      add_doctor_result PASS 'System tools' 'latex-or-typst' true "$(command -v xelatex 2>/dev/null || command -v typst)"
    else
      add_doctor_result MISSING 'System tools' 'latex-or-typst' true 'installable through apt (XeLaTeX)'
    fi
  fi

  local environment_python="$ENVIRONMENT_ROOT/$PROFILE/bin/python"
  if [[ -x "$environment_python" ]]; then
    add_doctor_result PASS Environment "$PROFILE Python" true "$environment_python"
  else
    add_doctor_result MISSING Environment "$PROFILE Python" true 'not installed'
  fi
  for tool in matlab gurobi_cl copt_cmd; do
    if command_exists "$tool"; then add_doctor_result PASS 'Commercial (optional)' "$tool" false "$(command -v "$tool")"
    else add_doctor_result INFO 'Commercial (optional)' "$tool" false 'not found; never auto-installed'; fi
  done

  if [[ "$NO_REPORT" != true && -x "$(command -v python3 2>/dev/null || true)" ]]; then
    local stamp report_base
    stamp="$(date +%Y%m%d-%H%M%S)"
    report_base="$REPORT_ROOT/doctor-$PROFILE-$stamp"
    python3 "$PROJECT_ROOT/scripts/render_report.py" --profile "$PROFILE" --kind doctor --output-base "$report_base" --input-tsv "$DOCTOR_TSV"
  fi
  rm -f -- "$DOCTOR_TSV"
  trap - RETURN
  if ((DOCTOR_MISSING > 0)); then echo "Warning: $DOCTOR_MISSING required item(s) are not ready." >&2; fi
}

apt_packages() {
  local packages=(ca-certificates curl python3 fonts-noto-cjk)
  if [[ "$PROFILE" == ml || "$PROFILE" == full ]]; then packages+=(libgomp1); fi
  if profile_has_paper; then
    packages+=(pandoc graphviz texlive-xetex texlive-lang-chinese texlive-latex-extra latexmk)
  fi
  printf '%s\n' "${packages[@]}"
}

install_system_packages() {
  mapfile -t packages < <(apt_packages)
  run_privileged apt-get update || return 1
  run_privileged apt-get install -y --no-install-recommends "${packages[@]}"
}

resolve_uv() {
  if command_exists uv; then command -v uv; return 0; fi
  if [[ -x "${USER_HOME}/.local/bin/uv" ]]; then printf '%s\n' "${USER_HOME}/.local/bin/uv"; return 0; fi
  if [[ "$DRY_RUN" == true ]]; then printf '%s\n' uv; return 0; fi

  local uv_version uv_sha installer_url temporary_installer actual_sha
  uv_version="$(manifest_value uv-version)"
  uv_sha="$(manifest_value uv-linux-sha256)"
  installer_url="https://astral.sh/uv/$uv_version/install.sh"
  temporary_installer="$(mktemp "${TMPDIR:-/tmp}/modelready-uv.XXXXXX.sh")"
  if command_exists curl; then curl -fsSL "$installer_url" -o "$temporary_installer"
  elif command_exists wget; then wget -q "$installer_url" -O "$temporary_installer"
  else echo 'ModelReady failed: curl or wget is required.' >&2; rm -f -- "$temporary_installer"; return 1; fi
  actual_sha="$(sha256sum "$temporary_installer" | awk '{print $1}')"
  if [[ "$actual_sha" != "$uv_sha" ]]; then
    echo "ModelReady failed: uv installer SHA-256 mismatch; refusing to execute." >&2
    rm -f -- "$temporary_installer"
    return 1
  fi
  echo 'uv installer SHA-256 verified.' >&2
  env UV_NO_MODIFY_PATH=1 sh "$temporary_installer" >&2
  local installer_status=$?
  rm -f -- "$temporary_installer"
  if ((installer_status != 0)); then return "$installer_status"; fi
  if [[ -x "${USER_HOME}/.local/bin/uv" ]]; then printf '%s\n' "${USER_HOME}/.local/bin/uv"; return 0; fi
  echo 'ModelReady failed: uv installer completed but uv was not found.' >&2
  return 1
}

confirm_install() {
  if [[ "$ASSUME_YES" == true || "$DRY_RUN" == true ]]; then return 0; fi
  read -r -p "Install profile '$PROFILE' and modify the user environment? Type YES: " answer
  [[ "$answer" == YES ]]
}

install_profile() {
  detect_platform
  if [[ "$(uname -s)" != Linux ]] || ! platform_supported; then
    echo 'ModelReady failed: supported systems are Ubuntu 22.04/24.04, Debian 12, and WSL2 based on them.' >&2
    return 1
  fi
  if ! confirm_install; then echo 'Installation cancelled.' >&2; return 1; fi
  install_system_packages || return 1
  if [[ "$DRY_RUN" == true ]] && ! command_exists python3; then
    echo '[DRY-RUN] manifest will be read after python3 is installed'
    return 0
  fi
  local uv_command python_version environment environment_python index_url lock_path product_version
  uv_command="$(resolve_uv)" || return 1
  python_version="$(manifest_value python-version)"
  product_version="$(manifest_value version)"
  environment="$ENVIRONMENT_ROOT/$PROFILE"
  environment_python="$environment/bin/python"
  index_url='https://pypi.org/simple'
  if [[ "$SOURCE" == china ]]; then index_url='https://pypi.tuna.tsinghua.edu.cn/simple'; fi
  mapfile -t python_packages < <(manifest_value packages)
  if ((${#python_packages[@]} == 0)); then echo 'ModelReady failed: profile contains no Python packages.' >&2; return 1; fi

  run_command "$uv_command" python install "$python_version" || return 1
  if [[ "$DRY_RUN" == true || ! -x "$environment_python" ]]; then
    run_command "$uv_command" venv --python "$python_version" "$environment" || return 1
  else
    echo "[SKIP] Environment already exists: $environment"
  fi
  run_command "$uv_command" pip install --python "$environment_python" --index-url "$index_url" "${python_packages[@]}" || return 1
  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] write exact package list: $environment/modelready.lock.txt"
    return 0
  fi
  lock_path="$environment/modelready.lock.txt"
  "$uv_command" pip freeze --python "$environment_python" >"$lock_path" || return 1
  python3 "$PROJECT_ROOT/scripts/write_install_state.py" --path "$environment/modelready-installation.json" \
    --product-version "$product_version" --profile "$PROFILE" --source "$SOURCE" \
    --python-version "$python_version" --environment "$environment" --lock-file "$lock_path" || return 1
  verify_profile
}

verify_profile() {
  local environment_python="$ENVIRONMENT_ROOT/$PROFILE/bin/python"
  if [[ ! -x "$environment_python" ]]; then echo "ModelReady failed: profile '$PROFILE' is not installed." >&2; return 1; fi
  local output_dir="$REPORT_ROOT/artifacts" python_result system_result stamp report_base
  mkdir -p "$output_dir" "$REPORT_ROOT"
  "$environment_python" "$PROJECT_ROOT/scripts/verify_environment.py" --profile "$PROFILE" --output-dir "$output_dir"
  local python_status=$?
  local paper_argument=()
  if profile_has_paper; then paper_argument=(--paper); fi
  "$environment_python" "$PROJECT_ROOT/scripts/verify_system.py" --profile "$PROFILE" --output-dir "$output_dir" "${paper_argument[@]}"
  local system_status=$?
  python_result="$output_dir/verify-$PROFILE.json"
  system_result="$output_dir/verify-system-$PROFILE.json"
  if [[ "$NO_REPORT" != true ]]; then
    stamp="$(date +%Y%m%d-%H%M%S)"
    report_base="$REPORT_ROOT/verify-$PROFILE-$stamp"
    "$environment_python" "$PROJECT_ROOT/scripts/render_report.py" --profile "$PROFILE" --kind verify \
      --output-base "$report_base" --json-files "$python_result" "$system_result"
  fi
  if ((python_status != 0 || system_status != 0)); then
    echo 'ModelReady failed: one or more functional checks failed.' >&2
    return 1
  fi
  echo 'ModelReady environment passed all required checks.'
}

launch_profile() {
  local environment_python="$ENVIRONMENT_ROOT/$PROFILE/bin/python"
  if [[ ! -x "$environment_python" ]]; then echo "ModelReady failed: profile '$PROFILE' is not installed." >&2; return 1; fi
  if [[ "$DRY_RUN" == true ]]; then echo "[DRY-RUN] $environment_python -m jupyter lab"; return 0; fi
  echo 'Starting JupyterLab; press Ctrl+C to stop.'
  "$environment_python" -m jupyter lab
}

uninstall_profile() {
  local root_full target_full expected_prefix
  root_full="$(realpath -m -- "$ENVIRONMENT_ROOT")"
  target_full="$(realpath -m -- "$root_full/$PROFILE")"
  if [[ "$root_full" == / || "$target_full" == "$root_full" ]]; then
    echo 'ModelReady failed: environment root is too broad.' >&2; return 1
  fi
  expected_prefix="$root_full/"
  if [[ "$target_full" != "$expected_prefix"* ]]; then
    echo 'ModelReady failed: target is outside EnvironmentRoot.' >&2; return 1
  fi
  if [[ ! -e "$target_full" ]]; then echo "Profile '$PROFILE' is not installed: $target_full"; return 0; fi
  if [[ "$DRY_RUN" == true ]]; then echo "[DRY-RUN] remove environment: $target_full"; return 0; fi
  if [[ "$ASSUME_YES" != true ]]; then
    read -r -p "Permanently remove profile '$PROFILE'? Type UNINSTALL: " answer
    if [[ "$answer" != UNINSTALL ]]; then echo 'Uninstall cancelled.' >&2; return 1; fi
  fi
  rm -rf -- "$target_full"
  echo "Removed environment: $target_full"
  echo 'System packages were not removed.'
}

show_profiles() {
  if command_exists python3; then
    python3 - "$MANIFEST" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print("PROFILE\tDISK\tDESCRIPTION")
for name, item in data["profiles"].items():
    print(f"{name}\t{item['estimatedDiskGB']} GB\t{item['description']}")
PY
  else
    printf 'base\noptimization\nml\npaper\nfull\n'
  fi
}

show_version() {
  if command_exists python3; then echo "ModelReady $(manifest_value version)"
  else echo 'ModelReady 0.3.0'; fi
}

case "$COMMAND" in
  doctor) doctor ;;
  install|repair) install_profile ;;
  verify) verify_profile ;;
  launch) launch_profile ;;
  uninstall) uninstall_profile ;;
  profiles) show_profiles ;;
  version) show_version ;;
esac
