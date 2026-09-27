# stayclean

**Check your dev machine and your repos for JavaScript supply-chain backdoors, before they run.**

stayclean is a set of small, read-only scanners for **macOS**, **Windows** and **git repos**.
They look for the tricks used by real npm backdoors: a tampered npm CLI, poisoned editor
extensions, hidden staging folders, and malicious code hidden in build configs behind hundreds
of spaces. They never run `node`, `npm` or anything from what they scan, so they're safe to use
on a machine you don't trust yet.

> Built after a real backdoor lived for weeks on a developer's Mac, hid inside the global npm and
> VS Code, and **survived a full wipe** because the machine was restored from infected sources.
> These are the checks that finally found it, turned into tools anyone can use.

## What it checks

| | macOS | Windows | Repo |
|---|:-:|:-:|:-:|
| npm CLI tampering (`npm/lib/cli.js` size) for Homebrew, nvm, volta, fnm, asdf, nodenv, nvm-windows | ✅ | ✅ | |
| Known backdoor markers in global packages, the npx cache, VS Code / Cursor / Windsurf extensions | ✅ | ✅ | |
| The **padding trick**: code pushed off-screen by 300+ spaces on one line | ✅ | ✅ | ✅ |
| Electron apps (`app.asar`) carrying markers | ✅ | ✅ | |
| Hidden staging folders like `~/.node_module` and `~/.node_modules` | ✅ | ✅ | |
| Running payload processes, and `node` processes with huge inline code | ✅ | ✅ | |
| Startup items that launch node, npx, base64 or `curl \| sh` (LaunchAgents, Run keys, scheduled tasks, shell profiles) | ✅ | ✅ | |
| Protection settings: FileVault/BitLocker, firewall, SIP, Gatekeeper, Defender, outbound firewall, `npm ignore-scripts` | ✅ | ✅ | |
| Every **branch, remote branch, tag and the stash**, plus the working tree and `node_modules` | | | ✅ |
| Things that run code on install or open: lifecycle scripts, `.husky`, `.githooks`, `.vscode` tasks, `.npmrc`, `yarnPath`, non-registry dependencies, suspiciously large build configs | | | ✅ |
| AI-agent settings (`.claude/`, `.cursor/`, `CLAUDE.md`, `AGENTS.md`, `.mcp.json`) that run hooks or **pre-approve shell commands** | | | ✅ |

Results are one of **`clean`**, **`warnings`** (worth a look, often settings) or **`INFECTED`**.
In a terminal the result is shown as a big colored banner (green, yellow or red). Reports, logs and
piped output stay plain. Use `NO_COLOR=1` to turn colors off, or `FORCE_COLOR=1` (macOS) / `-Color` (Windows) to force them.

## Quick start

**macOS**
```bash
git clone https://github.com/SoroushOsivand/stayclean.git ~/stayclean
bash ~/stayclean/mac/stayclean-mac.sh
```

**Windows** (PowerShell)
```powershell
git clone https://github.com/SoroushOsivand/stayclean.git $HOME\stayclean
powershell -ExecutionPolicy Bypass -File $HOME\stayclean\windows\stayclean-win.ps1
```

**Scan a repo before `npm install`, a build, or opening it in an editor** (macOS, Linux, or Git Bash on Windows)
```bash
bash ~/stayclean/repo/scan-repo.sh path/to/repo
```
A `PAYLOAD` line means stop: don't install, build or open that repo. `REVIEW` lines are things
that *can* run code. Read them before you install.

A safe install order for a repo you just cloned:
1. `scan-repo.sh` → no `PAYLOAD`, and you've read the `REVIEW` lines
2. `npm ci --ignore-scripts`
3. `scan-repo.sh` again (now it covers `node_modules` too)
4. `npm rebuild` only if the project needs its packages' build steps
5. The machine scan again

Tip: run `npm config set ignore-scripts true` once, so nothing runs on install unless you allow it.

## Daily checks and alerts on your other devices

Run a scan every day at 09:00, save a Markdown report, and get a push notification on your
phone or another computer:

```bash
bash ~/stayclean/mac/stayclean-mac.sh --install-schedule          # macOS
```
```powershell
powershell -ExecutionPolicy Bypass -File $HOME\stayclean\windows\stayclean-win.ps1 -InstallSchedule   # Windows
```

Alerts use [ntfy](https://ntfy.sh), a free and open-source push service with apps for iOS,
Android and desktop:
1. Install the ntfy app on your phone and subscribe to a **long random topic name**
   (for example `stayclean-7f3k9x2q8w`). Anyone who knows the name can read it, so make it
   unguessable, or [self-host ntfy](https://docs.ntfy.sh/install/).
2. Put it in `~/.stayclean/env` (Windows: `%USERPROFILE%\.stayclean\env`):
   ```
   STAYCLEAN_NTFY_TOPIC=stayclean-7f3k9x2q8w
   # STAYCLEAN_NTFY_URL=https://ntfy.example.com   (if self-hosted)
   ```

Only a one-line summary is sent, like `stayclean MacBook: clean (0 bad, 0 warnings)`. Never file
paths or report contents. Full reports stay local in `~/.stayclean/reports/`. Remove the schedule
with `--uninstall-schedule` / `-UninstallSchedule`.

## In CI (GitHub Action)

Fail any pull request that adds the padding trick or a known marker, on any branch or tag:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
- uses: SoroushOsivand/stayclean@v0.1.1
```

## With Claude Code (or another AI coding agent)

`skills/stayclean/SKILL.md` teaches an agent to scan first, report instead of "fixing", and never
run npm or node in a repo before it passes. Install it for Claude Code:

```bash
mkdir -p ~/.claude/skills && cp -R ~/stayclean/skills/stayclean ~/.claude/skills/
```

Then ask: *"Is this machine clean?"* or *"Scan this repo before we install."* Other agents can
use the same file as a prompt.

## If it says INFECTED

1. **Stop** running npm, node, builds and editors on that machine. Don't type passwords into it.
2. **From another, clean device:** revoke GitHub/npm/cloud tokens, sign out all sessions,
   add a passkey, and rotate every secret that was on the machine (`.env`, keystores, API keys).
3. **Take your code, not the machine.** Move repos as `git bundle` files (history only, no
   hooks or config) and scan each one with `scan-repo.sh` on the clean side. Leave behind
   `node_modules`, apps, dotfolders, `~/Library`, build outputs and editor extensions.
4. **Reinstall from scratch.** Don't use Migration Assistant, Time Machine or a backup of the
   infected machine, because that's how backdoors survive a wipe.
5. Run stayclean on the new machine, then daily.

## Limits

stayclean is a focused tripwire, not an antivirus. It finds a known family of JavaScript
supply-chain tricks and the places they hide. A `clean` result doesn't prove a machine is safe.
Keep your OS protections on, use an outbound firewall
([LuLu](https://objective-see.org/products/lulu.html) on macOS), and never run a "test task"
repo from a stranger on your main machine. Use a throwaway VM.

Found a new marker or hiding place? Please open an issue or see [SECURITY.md](SECURITY.md).

## Author

Made by **Soroush Osivand**. If stayclean helped you, a ⭐ or a shout-out means a lot.

- GitHub: [@SoroushOsivand](https://github.com/SoroushOsivand)
- LinkedIn: [linkedin.com/in/SoroushOsivand](https://www.linkedin.com/in/SoroushOsivand)
- X: [@SoroushOsivand](https://x.com/SoroushOsivand)

Licensed under the [MIT License](LICENSE).
