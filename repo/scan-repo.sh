#!/usr/bin/env bash
# scan-repo.sh <repo-dir>: scan a git repo BEFORE npm install, builds, tests or opening it
# in an editor. Uses only git, grep, find and perl; nothing from the repo runs.
# Works on macOS, Linux and Windows (Git Bash).
#
# It checks every branch, remote branch, tag and the stash, plus the working tree,
# for known backdoor markers and for the "padding" trick (code pushed off-screen by
# 300+ spaces on one line), and lists everything that would run code on install or open.
#
# Exit codes: 0 no payload found (still read the REVIEW lines), 1 payload found, 64 usage.
#
# Part of stayclean: https://github.com/SoroushOsivand/stayclean
# Author: Soroush Osivand. MIT License.

set -u
R="${1:-}"
if [ -z "$R" ] || ! git -C "$R" rev-parse --git-dir >/dev/null 2>&1; then
  echo "usage: $(basename "$0") <git repo dir>"; exit 64
fi
cd "$R" || exit 64
# Never let the repo's own config run anything while we look at it.
export GIT_CONFIG_NOSYSTEM=1 GIT_ATTR_NOSYSTEM=1
G() { git -c core.fsmonitor=false -c core.hooksPath=/dev/null "$@"; }

bad=0
hit()    { echo "PAYLOAD  $*"; bad=1; }
review() { echo "REVIEW   $*"; }

# Split so this file does not match its own search.
MARKERS=( "global.i='8""-" "global.o='8""-" "global['e""']='" "global['_V""']='8-" "global['!""']='8-" "C2605""21A" "RS2606""05" )
GM=(); for m in "${MARKERS[@]}"; do GM+=(-e "$m"); done
CODE_RE='\.(c|m)?(j|t)sx?$|\.json$|rc$|\.vue$|\.svelte$'
is_worktree() { [ "$(G rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; }

# Every commit worth checking: branches, remote branches, tags, and the stash with its
# index (^2) and untracked-files (^3) commits.
REFS=$(G for-each-ref --format='%(refname)' refs/heads refs/remotes refs/tags | grep -v '/HEAD$')
if G rev-parse -q --verify refs/stash >/dev/null; then
  for s in refs/stash refs/stash^2 refs/stash^3; do G rev-parse -q --verify "$s^{commit}" >/dev/null && REFS="$REFS
$s"; done
fi
REFS=$(printf '%s\n' "$REFS" | grep .)
echo "scanning $(printf '%s\n' "$REFS" | grep -c .) refs in $(pwd)"

# 1. Known markers in history (fixed strings).
if [ -n "$REFS" ]; then
  while read -r f; do [ -n "$f" ] && hit "marker in $f"; done < <(G grep -lF "${GM[@]}" $REFS 2>/dev/null)
fi

# 2. Padding trick in history: each distinct file version is checked once.
if [ -n "$REFS" ]; then
  list=$(mktemp)
  # "<blob> <ref>:<path>" for code files, first occurrence of each blob only
  for ref in $REFS; do
    G ls-tree -r "$ref" 2>/dev/null | awk -v ref="$ref" -F'\t' '{ split($1, m, " "); if (m[2] == "blob") print m[3] " " ref ":" $2 }'
  done | awk '!seen[$1]++' | grep -E "$CODE_RE" > "$list"
  # stream all of them through one git process
  hits=$(cut -d' ' -f1 "$list" | G cat-file --batch 2>/dev/null | perl -e '
    binmode STDIN;
    while (my $h = <STDIN>) {
      my ($sha, $type, $size) = split / /, $h; next unless defined $size;
      my $buf = ""; read(STDIN, $buf, $size); <STDIN>;
      print "$sha\n" if $buf =~ / {300,}\S/;
    }')
  for sha in $hits; do hit "300+ space padding in $(grep -m1 "^$sha " "$list" | cut -d' ' -f2-)"; done
  rm -f "$list"
fi

# 3. Build configs that are suspiciously large (clean ones are usually well under 3 KB).
if [ -n "$REFS" ]; then
  for ref in $REFS; do
    G ls-tree -r -l "$ref" | awk '{print $4, $5}' |
      grep -E '(^| )(.*/)?(babel|postcss|next|jest|rollup|vite|webpack|metro|tailwind|eslint|prettier|vitest|nuxt|svelte|astro)\.config\.(c|m)?(j|t)s$|\.babelrc(\.js)?$' |
      while read -r size f; do [ "$size" -gt 3000 ] && echo "$f ${size}B"; done
  done | sort -u | while read -r f s; do review "large build config $f ($s): open it and look for a very long line"; done
fi

# 4. Working tree: markers and padding (including node_modules, if installed).
if is_worktree; then
  grep -rlF --exclude-dir=.git "${GM[@]}" . 2>/dev/null | head -20 | while read -r f; do echo "PAYLOAD  marker in working tree $f"; done > /tmp/sr.$$
  find . -name .git -prune -o -type f \( -name '*.js' -o -name '*.cjs' -o -name '*.mjs' -o -name '*.ts' -o -name '*.tsx' -o -name '*.jsx' -o -name '*.json' -o -name '*rc' \) -size -5M -print0 2>/dev/null |
    xargs -0 perl -ne 'if (/ {300,}\S/) { print "PAYLOAD  300+ space padding in working tree $ARGV\n"; close ARGV }' 2>/dev/null | head -20 >> /tmp/sr.$$
  [ -s /tmp/sr.$$ ] && { cat /tmp/sr.$$; bad=1; }
  rm -f /tmp/sr.$$

  # 5. Things that run code on install, on open, or when an AI agent starts in this folder.
  find . -name package.json -not -path '*/node_modules/*' -not -path './.git/*' | while read -r p; do
    perl -0ne 'while (/"(preinstall|install|postinstall|prepare|prepublish|preprepare|postprepare)"\s*:\s*"([^"]*)"/g) { print "REVIEW   lifecycle script in '"$p"': $1 = $2\n" }' "$p"
  done
  for f in .claude .mcp.json CLAUDE.md AGENTS.md .cursor .windsurf .npmrc .yarnrc .yarnrc.yml .pnpmfile.cjs \
           .vscode/tasks.json .vscode/settings.json .vscode/launch.json .devcontainer .husky .githooks .envrc .gitattributes; do
    find . -path ./node_modules -prune -o -path "./$f" -print -o -path "*/$f" -not -path '*/node_modules/*' -print 2>/dev/null |
      while read -r x; do review "runs or configures code: $x"; done
  done
  grep -rhoE '"allow"[^]]*(Bash\((node|npm|npx|curl|python3?|bash|sh)[^)]*\))' --include='settings*.json' . 2>/dev/null | head -1 |
    grep -q . && review "an AI agent settings file pre-approves shell commands (node/npm/curl/python): check .claude/settings*.json"
  find . \( -name package-lock.json -o -name yarn.lock -o -name pnpm-lock.yaml \) -not -path '*/node_modules/*' | while read -r l; do
    grep -oE '(resolved|tarball)["]?:? ?"?(https?|git[^:]*)://[^"]+' "$l" | grep -vE 'registry\.npmjs\.org|registry\.yarnpkg\.com' |
      sort -u | head -5 | while read -r u; do review "non-registry dependency in $l: $u"; done
  done
  grep -qE '^\s*yarnPath:' .yarnrc.yml 2>/dev/null && review "yarnPath in .yarnrc.yml runs a checked-in yarn binary on every yarn command"
fi

echo
if [ $bad = 0 ]; then echo "RESULT   no payload found in $(pwd)"
else echo "RESULT   PAYLOAD FOUND in $(pwd): do not install, build or open this repo"; fi
exit $bad
