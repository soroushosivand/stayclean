<#
.SYNOPSIS
  stayclean-win: check a Windows developer machine for JavaScript supply-chain backdoors.

.DESCRIPTION
  Read-only. Uses only built-in PowerShell. It never runs node, npm or anything from the
  things it scans, so it is safe to run on a machine you don't trust yet.
  Exit codes: 0 clean, 1 infected (BAD lines), 2 warnings only.

  Part of stayclean: https://github.com/SoroushOsivand/stayclean
  Author: Soroush Osivand. MIT License.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\stayclean-win.ps1
  powershell -ExecutionPolicy Bypass -File .\stayclean-win.ps1 -Report -Notify
  powershell -ExecutionPolicy Bypass -File .\stayclean-win.ps1 -InstallSchedule
#>
[CmdletBinding()]
param(
  [switch]$Report,
  [string]$ReportDir = (Join-Path $env:USERPROFILE ".stayclean\reports"),
  [switch]$Notify,
  [switch]$Quiet,
  [switch]$Color,
  [switch]$InstallSchedule,
  [switch]$UninstallSchedule,
  [switch]$Version
)

$ErrorActionPreference = "SilentlyContinue"
$StayVersion = "0.1.1"
$TaskName = "stayclean daily scan"
if ($Version) { $StayVersion; exit 0 }

if ($InstallSchedule) {
  $action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Report -Notify -Quiet"
  $trigger = New-ScheduledTaskTrigger -Daily -At 9am
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Description "stayclean: daily supply-chain backdoor scan" -Force | Out-Null
  "Scheduled daily at 09:00 as task '$TaskName'."
  if (-not (Test-Path (Join-Path $env:USERPROFILE ".stayclean\env"))) { "Tip: put STAYCLEAN_NTFY_TOPIC=... in $env:USERPROFILE\.stayclean\env to get phone alerts." }
  exit 0
}
if ($UninstallSchedule) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false; "Daily run removed."; exit 0 }

# Optional settings for scheduled runs (plain KEY=value lines; never executed as code).
$envFile = Join-Path $env:USERPROFILE ".stayclean\env"
if (Test-Path $envFile) {
  foreach ($line in Get-Content $envFile) {
    if ($line -match '^(STAYCLEAN_NTFY_TOPIC|STAYCLEAN_NTFY_URL)=(.*)$') { Set-Item -Path "env:$($Matches[1])" -Value $Matches[2] }
  }
}

# ---------------------------------------------------------------- indicators
# Split so this file does not match its own search.
$Markers = @(
  ("global.i='8" + "-"), ("global.o='8" + "-"), ("global['e" + "']='"), ("global['_V" + "']='8-"), ("global['!" + "']='8-"),
  ("C2605" + "21A"), ("RS2606" + "05")
)
$MarkerRe = ($Markers | ForEach-Object { [regex]::Escape($_) }) -join '|'
$PadRe = ' {300,}\S'

# ---------------------------------------------------------------- output
$script:bad = 0; $script:warn = 0; $script:lines = New-Object System.Collections.Generic.List[string]
function Say([string]$s) { $script:lines.Add($s); if ($Quiet -and ($s.StartsWith("ok") -or $s.StartsWith("=="))) { return }; Write-Output $s }
function Ok([string]$s)   { Say "ok    $s" }
function Warn([string]$s) { Say "WARN  $s"; $script:warn++ }
function Bad([string]$s)  { Say "BAD   $s"; $script:bad++ }
function Section([string]$s) { Say "== $s" }

# markers + padding in JS files under a folder; returns up to 5 findings
function Scan-Dir([string]$dir) {
  if (-not (Test-Path $dir)) { return @() }
  $found = @()
  $files = Get-ChildItem -Path $dir -Recurse -File -Force -Include *.js,*.cjs,*.mjs,*.json |
           Where-Object { $_.Length -lt 5MB }
  foreach ($f in $files) {
    if ($found.Count -ge 5) { break }
    $hit = Select-String -Path $f.FullName -Pattern $Markers -SimpleMatch -List
    if ($hit) { $found += "marker: $($f.FullName)"; continue }
    if ($f.Extension -ne ".json") {
      $pad = Select-String -Path $f.FullName -Pattern $PadRe -List
      if ($pad) { $found += "padding: $($f.FullName)" }
    }
  }
  return $found
}

# ---------------------------------------------------------------- checks
Section "Node.js installs (npm CLI integrity)"
$nodeDirs = @()
$candidates = @(
  (Join-Path $env:APPDATA "npm\node_modules"),
  (Join-Path $env:ProgramFiles "nodejs\node_modules"),
  (Join-Path ${env:ProgramFiles(x86)} "nodejs\node_modules")
)
if ($env:NVM_HOME) { $candidates += Get-ChildItem $env:NVM_HOME -Directory | ForEach-Object { Join-Path $_.FullName "node_modules" } }
if ($env:VOLTA_HOME) { $candidates += Get-ChildItem (Join-Path $env:VOLTA_HOME "tools\image\node") -Directory | ForEach-Object { Join-Path $_.FullName "node_modules" } }
$candidates += Get-ChildItem (Join-Path $env:APPDATA "fnm\node-versions") -Directory | ForEach-Object { Join-Path $_.FullName "installation\node_modules" }
foreach ($d in $candidates) { if ($d -and (Test-Path $d)) { $nodeDirs += $d } }
if ($nodeDirs.Count -eq 0) { Ok "no global node_modules found" }
foreach ($d in $nodeDirs) {
  $cli = Join-Path $d "npm\lib\cli.js"
  if (Test-Path $cli) {
    $size = (Get-Item $cli).Length
    if ($size -gt 2000) { Bad "$cli is $size bytes (a clean one is ~400). The npm CLI itself is modified." } else { Ok "$cli ${size}B" }
  }
  $hits = Scan-Dir $d
  if ($hits.Count) { $hits | ForEach-Object { Bad "global packages: $_" } }
  else { Ok "global packages clean: $d ($((Get-ChildItem $d -Directory).Name -join ' '))" }
}

Section "npx cache and editor extensions"
foreach ($d in @(
  (Join-Path $env:LOCALAPPDATA "npm-cache\_npx"),
  (Join-Path $env:USERPROFILE ".vscode\extensions"), (Join-Path $env:USERPROFILE ".vscode-insiders\extensions"),
  (Join-Path $env:USERPROFILE ".cursor\extensions"), (Join-Path $env:USERPROFILE ".windsurf\extensions"))) {
  if (-not (Test-Path $d)) { continue }
  $checked = $true
  $hits = Scan-Dir $d
  if ($hits.Count) { $hits | ForEach-Object { Bad $_ } } else { Ok "clean: $d" }
}
if (-not $checked) { Ok "nothing to check (no npx cache or editor extensions yet)" }

Section "Electron apps"
$asars = @()
foreach ($root in @((Join-Path $env:LOCALAPPDATA "Programs"), $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
  if ($root -and (Test-Path $root)) {
    $asars += Get-ChildItem $root -Directory | ForEach-Object { Get-ChildItem $_.FullName -Filter app.asar -Recurse -Depth 3 -File }
  }
}
foreach ($a in $asars) {
  if (Select-String -Path $a.FullName -Pattern $Markers -SimpleMatch -List) { Bad "marker in app: $($a.FullName)" }
}
Ok "Electron apps checked: $($asars.Count)"

Section "Hidden malware staging folders in your user folder"
$staging = Get-ChildItem $env:USERPROFILE -Directory -Force | Where-Object { $_.Name -like ".*" } | ForEach-Object {
  if ($_.Name -like "*node_module*") { $_ }
  Get-ChildItem $_.FullName -Directory -Force | Where-Object { $_.Name -like "*node_module*" }
}
if ($staging) {
  foreach ($s in $staging) {
    if ($s.Parent.FullName -eq $env:USERPROFILE -and $s.Name -in @(".node_module", ".node_modules")) { Bad "hidden staging folder: $($s.FullName)" }
    else { Warn "node_modules inside a hidden folder: $($s.FullName) (fine if you know what put it there)" }
  }
} else { Ok "none" }

Section "Running processes"
$procs = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine }
$payload = $procs | Where-Object { $_.CommandLine -match $MarkerRe }
if ($payload) { $payload | ForEach-Object { Bad "payload process $($_.ProcessId): $($_.CommandLine.Substring(0, [Math]::Min(200, $_.CommandLine.Length)))" } }
else { Ok "no payload processes" }
$procs | Where-Object { $_.Name -eq "node.exe" -and $_.CommandLine.Length -gt 1500 } |
  ForEach-Object { Warn "node process $($_.ProcessId) has a very long command line (inline code?)" }

Section "Things that start automatically"
$runtimeRe = '(?i)\b(node|npm|npx|bun|deno)(\.exe|\.cmd)?\b|node_modules|-enc(odedcommand)?\s|mshta|wscript|cscript|frombase64string|iwr\s|invoke-webrequest|curl\s.*\|'
foreach ($key in @("HKCU:\Software\Microsoft\Windows\CurrentVersion\Run", "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
                   "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce", "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce")) {
  $props = Get-ItemProperty $key
  if ($props) {
    foreach ($p in $props.PSObject.Properties) {
      if ($p.Name -like "PS*") { continue }
      if ("$($p.Value)" -match $runtimeRe) { Warn "startup entry runs a script runtime: $key\$($p.Name) = $($p.Value)" }
    }
  }
}
# Windows' own tasks legitimately use cscript/wscript; there, flag only runtimes Windows doesn't ship.
$nonWindowsRe = '(?i)\b(node|npm|npx|bun|deno)(\.exe|\.cmd)?\b|node_modules|-enc(odedcommand)?\s|mshta|frombase64string|iwr\s|invoke-webrequest|curl\s.*\|'
foreach ($t in Get-ScheduledTask) {
  if ($t.TaskName -eq $TaskName) { continue }
  $re = if ($t.TaskPath -like '\Microsoft\Windows\*') { $nonWindowsRe } else { $runtimeRe }
  foreach ($a in $t.Actions) {
    if ("$($a.Execute) $($a.Arguments)" -match $re) { Warn "scheduled task runs a script runtime: $($t.TaskPath)$($t.TaskName): $($a.Execute) $($a.Arguments)" }
  }
}
foreach ($dir in @([Environment]::GetFolderPath("Startup"), [Environment]::GetFolderPath("CommonStartup"))) {
  Get-ChildItem $dir -File | Where-Object { $_.Extension -in ".js", ".vbs", ".bat", ".cmd", ".ps1" } |
    ForEach-Object { Warn "script in Startup folder: $($_.FullName)" }
}
Ok "startup items reviewed"
$profilePaths = @($PROFILE.CurrentUserAllHosts, $PROFILE.CurrentUserCurrentHost) | Where-Object { $_ -and (Test-Path $_) }
foreach ($pp in $profilePaths) {
  Select-String -Path $pp -Pattern 'iex|Invoke-Expression|FromBase64String|node -e|DownloadString' |
    ForEach-Object { Warn "PowerShell profile runs downloaded or inline code: $($pp):$($_.LineNumber)" }
}

Section "Protection settings"
$mp = Get-MpComputerStatus
if ($mp) {
  if ($mp.RealTimeProtectionEnabled) { Ok "Defender real-time protection on" } else { Warn "Defender real-time protection is off" }
  if ($mp.AntivirusSignatureAge -gt 3) { Warn "Defender signatures are $($mp.AntivirusSignatureAge) days old" } else { Ok "Defender signatures current" }
} else { Warn "could not read Microsoft Defender status (another antivirus may be installed)" }
$fw = Get-NetFirewallProfile | Where-Object { -not $_.Enabled }
if ($fw) { Warn "firewall off for: $(($fw.Name) -join ', ')" } else { Ok "firewall on for all profiles" }
$bl = Get-BitLockerVolume -MountPoint $env:SystemDrive
if ($bl) { if ($bl.ProtectionStatus -eq "On") { Ok "BitLocker on" } else { Warn "BitLocker is off on $env:SystemDrive" } }
else { Say "info  BitLocker status needs an admin shell (skipped)" }
$npmrc = Join-Path $env:USERPROFILE ".npmrc"
if ((Test-Path $npmrc) -and (Select-String -Path $npmrc -Pattern '^\s*ignore-scripts\s*=\s*true' -Quiet)) { Ok "npm ignore-scripts=true" }
elseif ($nodeDirs.Count -gt 0) { Warn "npm runs install scripts (set: npm config set ignore-scripts true)" }

# ---------------------------------------------------------------- result
if ($script:bad -gt 0) { $result = "INFECTED"; $code = 1 } elseif ($script:warn -gt 0) { $result = "warnings"; $code = 2 } else { $result = "clean"; $code = 0 }
$summary = "stayclean $($env:COMPUTERNAME): $result ($($script:bad) bad, $($script:warn) warnings) $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Write-Output ""
# Big block-letter banner, in color, only in an interactive console.
$showBanner = $false
$color = @{ 0 = "Green"; 1 = "Red"; 2 = "Yellow" }[$code]
if ($Color -or (-not [Console]::IsOutputRedirected -and -not $env:NO_COLOR)) {
  $G = @{
    A = " ### |#   #|#####|#   #|#   #"; C = " ####|#    |#    |#    | ####"; D = "#### |#   #|#   #|#   #|#### "
    E = "#####|#    |#### |#    |#####"; F = "#####|#    |#### |#    |#    "; G = " ####|#    |#  ##|#   #| ####"
    I = "#####|  #  |  #  |  #  |#####"; L = "#    |#    |#    |#    |#####"; N = "#   #|##  #|# # #|#  ##|#   #"
    R = "#### |#   #|#### |#  # |#   #"; S = " ####|#    | ### |    #|#### "; T = "#####|  #  |  #  |  #  |  #  "
    W = "#   #|#   #|# # #|## ##|#   #"
  }
  $word = @{ 0 = "CLEAN"; 1 = "INFECTED"; 2 = "WARNINGS" }[$code]
  $showBanner = $true
  # Each risky step is its own try so a console quirk can never hide the RESULT line.
  try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
  try {
    for ($row = 0; $row -lt 5; $row++) {
      $line = "  " + (($word.ToCharArray() | ForEach-Object { $G["$_"].Split("|")[$row].Replace("#", [string][char]0x2588) }) -join " ")
      Write-Host $line -ForegroundColor $color
    }
  } catch { }
}
$resultLine = "RESULT $result  ($($script:bad) bad, $($script:warn) warnings)"
if ($showBanner) { Write-Host $resultLine -ForegroundColor $color } else { Write-Output $resultLine }
if ($code -eq 1) { Write-Output "Stop: don't run npm, node or builds on this machine. See README, 'If it says INFECTED'." }

if ($Report) {
  New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
  $file = Join-Path $ReportDir ("stayclean-" + (Get-Date -Format "yyyy-MM-dd-HHmm") + ".md")
  $body = @("# stayclean report: $($env:COMPUTERNAME)", "", "**Result: $result** ($($script:bad) bad, $($script:warn) warnings). $(Get-Date). stayclean-win $StayVersion, Windows $([Environment]::OSVersion.Version).", "", '```') + $script:lines + '```'
  $body | Set-Content -Path $file -Encoding UTF8
  Write-Output "Report: $file"
}

if ($Notify) {
  if ($env:STAYCLEAN_NTFY_TOPIC) {
    $base = if ($env:STAYCLEAN_NTFY_URL) { $env:STAYCLEAN_NTFY_URL } else { "https://ntfy.sh" }
    $pri = @{ 0 = "default"; 1 = "urgent"; 2 = "high" }[$code]
    try {
      Invoke-RestMethod -Method Post -Uri "$base/$($env:STAYCLEAN_NTFY_TOPIC)" -Body $summary -Headers @{ Title = "stayclean $result"; Priority = $pri } -TimeoutSec 15 | Out-Null
      Write-Output "Notification sent."
    } catch { Write-Output "Notification failed." }
  } else { Write-Output "-Notify: set STAYCLEAN_NTFY_TOPIC (in $envFile) to get alerts." }
}
exit $code
