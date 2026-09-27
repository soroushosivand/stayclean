#!/usr/bin/env bash
# stayclean-mac.sh: check a macOS developer machine for JavaScript supply-chain backdoors.
#
# Read-only. Uses only bash, grep, perl, find, ps and built-in macOS tools. It never runs
# node, npm or anything from the things it scans, so it is safe to run on a machine you
# don't trust yet.
#
# Exit codes: 0 clean, 1 infected (BAD lines), 2 warnings only, 64 usage error.
#
# Part of stayclean: https://github.com/SoroushOsivand/stayclean
# Author: Soroush Osivand. MIT License.

set -u
VERSION="0.1.1"
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
LABEL="com.github.soroushosivand.stayclean"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
REPORT_DIR=""
NOTIFY=0
QUIET=0

usage() {
  cat <<EOF
stayclean-mac $VERSION: scan this Mac for JavaScript supply-chain backdoors.

Usage: $(basename "$0") [options]
  --report [DIR]        also write a Markdown report (default DIR: ~/.stayclean/reports)
  --notify              send a one-line summary to ntfy (needs STAYCLEAN_NTFY_TOPIC)
  --quiet               print only BAD/WARN lines and the result
  --install-schedule    run daily at 09:00 with --report --notify (LaunchAgent)
  --uninstall-schedule  remove the daily run
  --version | --help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --report) REPORT_DIR="$HOME/.stayclean/reports"; if [ $# -gt 1 ] && [ "${2#-}" = "$2" ]; then REPORT_DIR="$2"; shift; fi ;;
    --notify) NOTIFY=1 ;;
    --quiet) QUIET=1 ;;
    --install-schedule)
      mkdir -p "$(dirname "$PLIST")" "$HOME/.stayclean"
      cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$SELF</string><string>--report</string><string>--notify</string><string>--quiet</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>0</integer></dict>
  <key>StandardOutPath</key><string>$HOME/.stayclean/last-run.log</string>
  <key>StandardErrorPath</key><string>$HOME/.stayclean/last-run.log</string>
</dict></plist>
EOF
      launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
      launchctl bootstrap "gui/$(id -u)" "$PLIST" && echo "Scheduled daily at 09:00: $PLIST"
      [ -f "$HOME/.stayclean/env" ] || echo "Tip: put STAYCLEAN_NTFY_TOPIC=... in ~/.stayclean/env to get phone alerts."
      exit 0 ;;
    --uninstall-schedule)
      launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null; rm -f "$PLIST"; echo "Daily run removed."; exit 0 ;;
    --version) echo "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 64 ;;
  esac
  shift
done

# Optional settings for scheduled runs (plain KEY=value lines; never executed as code).
if [ -f "$HOME/.stayclean/env" ]; then
  while IFS='=' read -r k v; do
    case "$k" in STAYCLEAN_NTFY_TOPIC|STAYCLEAN_NTFY_URL) export "$k=$v" ;; esac
  done < "$HOME/.stayclean/env"
fi

# ---------------------------------------------------------------- indicators
# Known markers of the "padded build-config" npm backdoor family (2026). They are split in
# the source so this file does not match its own search.
MARKERS=(
  "global.i='8""-" "global.o='8""-" "global['e""']='" "global['_V""']='8-" "global['!""']='8-"
  "C2605""21A" "RS2606""05"
)
GREP_M=(); for m in "${MARKERS[@]}"; do GREP_M+=(-e "$m"); done
PS_RE="global\.[io]='8""-|global\['e'\]=|global\['(_V|!)'\]='8""-"
# The hiding trick: payload pushed off-screen by 300+ spaces on one line.
PAD_RE=' {300,}\S'

# ---------------------------------------------------------------- output
bad=0; warn=0; LINES=()
# Colors only in a real terminal (reports, logs and pipes stay plain; NO_COLOR is honored).
if [ -n "${FORCE_COLOR:-}" ] || { [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; }; then
  C_OK=$'\033[32m' C_WARN=$'\033[1;33m' C_BAD=$'\033[1;31m' C_HEAD=$'\033[1m' C_DIM=$'\033[2m' C_OFF=$'\033[0m'
else
  C_OK="" C_WARN="" C_BAD="" C_HEAD="" C_DIM="" C_OFF=""
fi
say()  {
  LINES+=("$1")
  case "$1" in
    ok*) [ $QUIET = 1 ] && return; echo "${C_OK}ok${C_OFF}${1:2}" ;;
    ==*) [ $QUIET = 1 ] && return; echo "${C_HEAD}$1${C_OFF}" ;;
    WARN*) echo "${C_WARN}WARN${C_OFF}${1:4}" ;;
    BAD*) echo "${C_BAD}BAD${C_OFF}${1:3}" ;;
    *) echo "$1" ;;
  esac
}

# Big block-letter banner for the result (5 rows per letter).
glyph() { # glyph <letter> <row 1-5>
  local g
  case "$1" in
    A) g=" ███ |█   █|█████|█   █|█   █" ;; C) g=" ████|█    |█    |█    | ████" ;;
    D) g="████ |█   █|█   █|█   █|████ " ;; E) g="█████|█    |████ |█    |█████" ;;
    F) g="█████|█    |████ |█    |█    " ;; G) g=" ████|█    |█  ██|█   █| ████" ;;
    I) g="█████|  █  |  █  |  █  |█████" ;; L) g="█    |█    |█    |█    |█████" ;;
    N) g="█   █|██  █|█ █ █|█  ██|█   █" ;; R) g="████ |█   █|████ |█  █ |█   █" ;;
    S) g=" ████|█    | ███ |    █|████ " ;; T) g="█████|  █  |  █  |  █  |  █  " ;;
    W) g="█   █|█   █|█ █ █|██ ██|█   █" ;; *) g="     |     |     |     |     " ;;
  esac
  echo "$g" | cut -d'|' -f"$2"
}
big_banner() { # big_banner <WORD> <color>
  local row i line
  echo
  for row in 1 2 3 4 5; do
    line="  "
    for (( i=0; i<${#1}; i++ )); do line="$line$(glyph "${1:$i:1}" "$row") "; done
    echo "$2$line${C_OFF}"
  done
}
ok()   { say "ok    $*"; }
warn() { say "WARN  $*"; warn=$((warn+1)); }
bad()  { say "BAD   $*"; bad=$((bad+1)); }
section() { say "== $*"; }

# markers + padding in JS files under a directory; prints matching files (max 5)
scan_dir() {
  local d="$1"
  [ -d "$d" ] || return 0
  grep -rlaF "${GREP_M[@]}" --include='*.js' --include='*.cjs' --include='*.mjs' --include='*.json' --include='*.asar' "$d" 2>/dev/null | head -5 | sed 's/^/marker: /'
  find "$d" -type f \( -name '*.js' -o -name '*.cjs' -o -name '*.mjs' \) -size -5M -print0 2>/dev/null |
    xargs -0 perl -ne 'if (/ {300,}\S/) { print "padding: $ARGV\n"; close ARGV }' 2>/dev/null | head -5
}

# ---------------------------------------------------------------- checks
section "Node.js installs (npm CLI integrity)"
NODE_DIRS=()
for d in /opt/homebrew/lib/node_modules /usr/local/lib/node_modules "$HOME"/.nvm/versions/node/*/lib/node_modules \
         "$HOME"/.volta/tools/image/node/*/lib/node_modules "$HOME"/.local/share/fnm/node-versions/*/installation/lib/node_modules \
         "$HOME"/.asdf/installs/nodejs/*/lib/node_modules "$HOME"/.nodenv/versions/*/lib/node_modules; do
  [ -d "$d" ] && NODE_DIRS+=("$d")
done
if [ ${#NODE_DIRS[@]} = 0 ]; then ok "no global node_modules found"; fi
for d in ${NODE_DIRS[@]+"${NODE_DIRS[@]}"}; do
  cli="$d/npm/lib/cli.js"
  if [ -f "$cli" ]; then
    s=$(stat -f %z "$cli")
    if [ "$s" -gt 2000 ]; then bad "$cli is ${s} bytes (a clean one is ~400). The npm CLI itself is modified."
    else ok "$cli ${s}B"; fi
  fi
  hits=$(scan_dir "$d")
  if [ -n "$hits" ]; then while read -r h; do bad "global packages: $h"; done <<< "$hits"
  else
    n=$(ls "$d" | wc -l | tr -d ' '); [ "$n" = 1 ] && pk=package || pk=packages
    ok "global packages clean: $d ($n $pk: $(ls "$d" | tr '\n' ' ' | sed 's/ $//'))"
  fi
done

section "npx cache and editor extensions"
for d in "$HOME/.npm/_npx" "$HOME/.vscode/extensions" "$HOME/.vscode-insiders/extensions" "$HOME/.cursor/extensions" \
         "$HOME/.windsurf/extensions" "$HOME/.vscode-oss/extensions"; do
  [ -d "$d" ] || continue
  checked=1
  hits=$(scan_dir "$d")
  if [ -n "$hits" ]; then while read -r h; do bad "$h"; done <<< "$hits"; else ok "clean: $d"; fi
done
[ -z "${checked:-}" ] && ok "nothing to check (no npx cache or editor extensions yet)"

section "Electron apps in /Applications"
n=0
for a in /Applications/*.app "$HOME"/Applications/*.app; do
  r="$a/Contents/Resources"
  [ -e "$r/app.asar" ] || [ -d "$r/app" ] || continue
  n=$((n+1))
  hits=$(grep -rlaF "${GREP_M[@]}" "$r/app.asar" "$r/app" 2>/dev/null | head -2)
  [ -n "$hits" ] && while read -r h; do bad "marker in app: $h"; done <<< "$hits"
done
ok "$n Electron apps checked"

section "Hidden malware staging folders in your home folder"
found=0
while read -r d; do
  [ -z "$d" ] && continue
  case "$d" in
    "$HOME/.node_module"|"$HOME/.node_modules") bad "hidden staging folder: $d"; found=1 ;;
    *) warn "node_modules inside a hidden folder: $d (fine if you know what put it there)"; found=1 ;;
  esac
done < <(find "$HOME" -maxdepth 2 \( -path "$HOME/Library" -o -path "$HOME/.Trash" \) -prune -o -type d -name '*node_module*' -path "$HOME/.*" -print 2>/dev/null)
[ $found = 0 ] && ok "none"

section "Running processes"
p=$(ps -axo pid=,command= | grep -E "$PS_RE" | grep -v grep)
if [ -n "$p" ]; then while read -r l; do bad "payload process: ${l:0:200}"; done <<< "$p"; else ok "no payload processes"; fi
long=$(ps -axo pid=,command= | awk '$2 ~ /(^|\/)node$/ && length($0) > 1500 { print $1 }')
for pid in $long; do warn "node process $pid has a very long command line (inline code?). Inspect: ps -o command= -p $pid"; done

section "Things that start automatically"
for d in "$HOME/Library/LaunchAgents" /Library/LaunchAgents /Library/LaunchDaemons; do
  [ -d "$d" ] || continue
  for f in "$d"/*.plist; do
    [ -f "$f" ] || continue
    c=$(plutil -p "$f" 2>/dev/null)
    if printf '%s' "$c" | grep -qE "(/|\")(node|npm|npx|bun|deno)\"|node_module|curl .*\| *(ba|z)?sh|base64 -(d|D)|python3? -c|osascript -e"; then
      [ "$f" = "$PLIST" ] && continue
      warn "startup item runs a script runtime: $f"
    fi
  done
done
ok "LaunchAgents/Daemons reviewed"
for f in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zshenv" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
  [ -f "$f" ] || continue
  while read -r l; do
    [ -n "$l" ] && warn "shell startup file runs downloaded or inline code: $f:${l:0:160}"
  done < <(grep -nE 'node -e|curl [^#]*\| *(ba|z)?sh|wget [^#]*\| *(ba|z)?sh|base64 -(d|D)|eval "\$\(curl' "$f" 2>/dev/null)
done
ok "shell startup files reviewed"

section "Protection settings"
fdesetup status 2>/dev/null | grep -q "On" && ok "FileVault on" || warn "FileVault is off"
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -qE "enabled|State = [12]" && ok "firewall on" || warn "firewall is off"
csrutil status 2>/dev/null | grep -q enabled && ok "System Integrity Protection on" || warn "System Integrity Protection is off"
spctl --status 2>/dev/null | grep -q enabled && ok "Gatekeeper on" || warn "Gatekeeper is off"
if pgrep -xq LuLu || pgrep -fq 'com.objective-see.lulu'; then ok "LuLu outbound firewall running"
else warn "no outbound firewall detected (LuLu recommended: objective-see.org)"; fi
if [ -f "$HOME/.npmrc" ] && grep -qE '^\s*ignore-scripts\s*=\s*true' "$HOME/.npmrc"; then ok "npm ignore-scripts=true"
elif [ ${#NODE_DIRS[@]} -gt 0 ]; then warn "npm runs install scripts (set: npm config set ignore-scripts true)"; fi

# ---------------------------------------------------------------- result
if [ $bad -gt 0 ]; then RESULT="INFECTED"; CODE=1
elif [ $warn -gt 0 ]; then RESULT="warnings"; CODE=2
else RESULT="clean"; CODE=0; fi
HOST=$(scutil --get ComputerName 2>/dev/null || hostname)
SUMMARY="stayclean $HOST: $RESULT ($bad bad, $warn warnings) $(date '+%Y-%m-%d %H:%M')"
echo
case $CODE in 0) RC=$'\033[1;32m' W=CLEAN ;; 1) RC=$'\033[1;31m' W=INFECTED ;; *) RC=$'\033[1;33m' W=WARNINGS ;; esac
[ -n "$C_OFF" ] || RC=""
[ -n "$C_OFF" ] && big_banner "$W" "$RC"
echo "${RC}RESULT $RESULT  ($bad bad, $warn warnings)${C_OFF}"
[ $CODE = 1 ] && echo "${C_BAD}Stop: don't run npm, node or builds on this machine. See README, 'If it says INFECTED'.${C_OFF}"

if [ -n "$REPORT_DIR" ]; then
  mkdir -p "$REPORT_DIR"
  R="$REPORT_DIR/stayclean-$(date +%Y-%m-%d-%H%M).md"
  { echo "# stayclean report: $HOST"; echo; echo "**Result: $RESULT** ($bad bad, $warn warnings). $(date). stayclean-mac $VERSION, macOS $(sw_vers -productVersion)."; echo
    echo '```'; printf '%s\n' "${LINES[@]}"; echo '```'; } > "$R"
  echo "Report: $R"
fi

if [ $NOTIFY = 1 ]; then
  if [ -n "${STAYCLEAN_NTFY_TOPIC:-}" ]; then
    pri=default; [ $CODE = 1 ] && pri=urgent; [ $CODE = 2 ] && pri=high
    curl -fsS -m 15 -H "Title: stayclean $RESULT" -H "Priority: $pri" -d "$SUMMARY" \
      "${STAYCLEAN_NTFY_URL:-https://ntfy.sh}/$STAYCLEAN_NTFY_TOPIC" >/dev/null && echo "Notification sent." || echo "Notification failed."
  else echo "--notify: set STAYCLEAN_NTFY_TOPIC (in ~/.stayclean/env) to get alerts."; fi
fi
exit $CODE
