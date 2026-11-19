# Builds the Windows release with Velopack: an installer
# (PiumaMail-win-Setup.exe) for a first install, and the packages the
# app's updater downloads, with the changelog inside. It never publishes:
# the "Release" workflow (.github/workflows/release.yml) runs it in two
# jobs with no write access, and a separate job uploads what it made.
#
# Needs Flutter, Visual Studio (see CONTRIBUTING.md) and Velopack's CLI:
#   dotnet tool install -g vpk --version 1.2.161
#
# Usage:
#   powershell -File tools\windows-release.ps1 [-Arch x64|arm64]
#       [-Stage all|build|pack] [-Channel beta|canary] [-Build N] [-Notes notes.md]
#
#   -Stage build   only `flutter build windows` (the workflow's build job,
#                  which holds no secret)
#   -Stage pack    only packaging and signing, from a build already in
#                  app\build\windows\<arch>\runner\Release (the workflow's
#                  pack job, which runs no compiler)
#   -Stage all     both (the default, for a local build)
#
# Results, in app\build\releases: what vpk pack made, and in its
# "publish" folder exactly the files a GitHub release needs (vpk upload
# local: the packages, the installer and releases.<channel>.json).
#
# From the environment, never the repository:
#   PIUMA_UPDATE_URL       the repository or web folder the app checks for
#                          updates; unset, the GitHub repository being built
#                          (GITHUB_REPOSITORY, else the "origin" remote)
#   PIUMA_REPORT_RELAY     a fork's report relay, read when the engine
#                          compiles; unset, the project's relay
#   PIUMA_UPDATE_CHANNEL   "beta" (GitHub prereleases, the default) or
#                          "stable" (full releases only)
#   PIUMA_SIGN_PARAMS      signtool parameters for Authenticode, e.g.
#                          "/fd sha256 /td sha256 /tr <timestamp url> /sha1 <thumbprint>"
#   PIUMA_AZURE_SIGN_FILE  or: the metadata.json of an Azure Trusted Signing
#                          account (with AZURE_TENANT_ID, AZURE_CLIENT_ID and
#                          AZURE_CLIENT_SECRET set)
#                          Without either the packages are unsigned, and the
#                          script says so.
#   GITHUB_TOKEN           optional, read-only: only to fetch the previous
#                          release for the delta package without GitHub's
#                          anonymous rate limit
#
# The version is 0.1.0-beta.N, N = commits on this branch + 700 (or -Build):
# releases made before the repository moved reached beta.679, and Velopack
# would not update to a lower number.
#
# -Arch arm64 builds for Windows on ARM; Flutter does that only on an
# ARM64 machine. It goes in Velopack's "win-arm64" channel
# (PiumaMail-win-arm64-Setup.exe, releases.win-arm64.json), next to x64's
# default "win" one. An installed app follows the channel it was installed
# from, so each machine keeps its own build.
# -Channel canary packs into "win-canary" / "win-arm64-canary": early
# releases, which installed apps follow only when the user turns on
# Settings > Help & feedback > Updates > Early releases.
param(
  [ValidateSet("x64", "arm64")][string]$Arch = "x64",
  [ValidateSet("all", "build", "pack")][string]$Stage = "all",
  [ValidateSet("beta", "canary")][string]$Channel = "beta",
  [int]$Build = 0,
  [string]$Notes = ""
)
$ErrorActionPreference = "Stop"

$root = Resolve-Path "$PSScriptRoot\.."
# The feed: PIUMA_UPDATE_URL, else the GitHub repository this runs for
# (GITHUB_REPOSITORY on Actions, else the "origin" remote), so a fork's
# build follows the fork; the upstream repository only as a last resort.
$feed = $env:PIUMA_UPDATE_URL
if (-not $feed -and $env:GITHUB_REPOSITORY) { $feed = "https://github.com/$env:GITHUB_REPOSITORY" }
if (-not $feed) {
  $origin = ""
  try { $origin = git -C $root remote get-url origin 2>$null } catch { }
  if ($origin -match 'github\.com[:/]([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(\.git)?$') {
    $feed = "https://github.com/$($Matches[1])/$($Matches[2])"
  }
}
if (-not $feed) { $feed = "https://github.com/piuma-mail/piuma-mail" }
Write-Host "Update feed: $feed"
$updateChannel = if ($env:PIUMA_UPDATE_CHANNEL) { $env:PIUMA_UPDATE_CHANNEL } else { "beta" }

if (-not $Build) { $Build = [int](git -C $root rev-list --count HEAD).Trim() + 700 }
$version = "0.1.0-beta.$Build"
$out = "$root\app\build\releases"
$appDir = "$root\app\build\windows\$Arch\runner\Release"

# x64 keeps Velopack's defaults (channel "win", architecture read from
# the exe), as in the releases already installed.
$vpkChannel = if ($Arch -eq "arm64") { "win-arm64" } else { "win" }
if ($Channel -eq "canary") { $vpkChannel = "$vpkChannel-canary" }
$channelArgs = @()
if ($vpkChannel -ne "win") { $channelArgs = @("--channel", $vpkChannel) }

if ($Stage -ne "pack") {
  Push-Location "$root\app"
  try {
    flutter build windows --release --build-name 0.1.0 --build-number $Build `
      --dart-define=PIUMA_BUILD=$Build --dart-define=PIUMA_UPDATE_URL=$feed `
      --dart-define=PIUMA_UPDATE_CHANNEL=$updateChannel
    if ($LASTEXITCODE) { throw "flutter build failed" }
  } finally { Pop-Location }
  Write-Host "Piuma Mail $version ($Arch) built in $appDir"
  if ($Stage -eq "build") { exit 0 }
}

if (-not (Test-Path "$appDir\piuma_mail.exe")) { throw "No build in ${appDir}; run -Stage build first." }

# Fresh each time: a package left by an earlier run of the same build
# would stop vpk pack.
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $out | Out-Null

if (-not $Notes) {
  $Notes = "$out\notes-$Build.md"
  # Listed, not described: git describe writes to stderr when there is no
  # tag yet, and Windows PowerShell stops on that. This version's own tag
  # is skipped.
  $since = git -C $root tag --list "v*" --merged HEAD --sort=-creatordate |
    Where-Object { $_ -ne "v$version" } | Select-Object -First 1
  $range = if ($since) { "$since..HEAD" } else { "HEAD~20..HEAD" }
  # The pull requests merged into main, by their titles (each merge's
  # first body line); branch catch-ups, sign-offs and links stay out.
  $lines = git -C $root log --first-parent --merges --grep="^Merge pull request" --format="%H" $range |
    ForEach-Object {
      $title = git -C $root log -1 --format="%b" $_ | Where-Object { $_ -match "\S" } | Select-Object -First 1
      if ($title) { "- $title" }
    }
  if (-not $lines) { $lines = @("- Small fixes and improvements.") }
  Set-Content -Encoding utf8 $Notes $lines
}

# The last release of this channel, so the new one also ships as a small
# delta (the first time there is none, and that is fine). Only reads.
if ($feed.StartsWith("https://github.com/")) {
  $tokenArgs = @()
  if ($env:GITHUB_TOKEN) { $tokenArgs = @("--token", $env:GITHUB_TOKEN) }
  $pre = @()
  if ($updateChannel -ne "stable") { $pre = @("--pre") }
  vpk download github --repoUrl $feed @tokenArgs @pre @channelArgs -o $out
  if ($LASTEXITCODE) { Write-Warning "No earlier release downloaded: this one ships without a delta." }
}

# Authenticode, when the environment has a certificate; never a secret in
# the repository.
$sign = @()
if ($env:PIUMA_SIGN_PARAMS) {
  $sign = @("--signParams", $env:PIUMA_SIGN_PARAMS)
  Write-Host "Signing with signtool."
} elseif ($env:PIUMA_AZURE_SIGN_FILE) {
  $sign = @("--azureTrustedSignFile", $env:PIUMA_AZURE_SIGN_FILE)
  Write-Host "Signing with Azure Trusted Signing."
} else {
  Write-Warning "No signing certificate (PIUMA_SIGN_PARAMS or PIUMA_AZURE_SIGN_FILE): the packages are UNSIGNED."
}

$runtime = @()
if ($Arch -eq "arm64") { $runtime = @("--runtime", "win-arm64") }
vpk pack --packId PiumaMail --packVersion $version --packTitle "Piuma Mail" `
  --packDir $appDir --mainExe piuma_mail.exe `
  --icon "$root\app\windows\runner\resources\app_icon.ico" `
  --shortcuts StartMenuRoot,Desktop --aumid Piuma.PiumaMail `
  --releaseNotes $Notes @channelArgs @runtime @sign -o $out
if ($LASTEXITCODE) { throw "vpk pack failed" }

if ($sign) {
  $setup = Get-ChildItem $out -Filter "*-Setup.exe" | Select-Object -First 1
  $status = (Get-AuthenticodeSignature $setup.FullName).Status
  if ($status -ne "Valid") { throw "$($setup.Name) is not validly signed ($status)." }
}

# Exactly what a GitHub release carries, for the workflow's publish job:
# the new packages, the installer and the channel's releases file. That
# job only uploads them; it runs neither vpk nor anything from here.
$publish = "$out\publish"
New-Item -ItemType Directory -Force $publish | Out-Null
vpk upload local -o $out --path $publish @channelArgs
if ($LASTEXITCODE) { throw "vpk upload local failed" }
Write-Host "Piuma Mail $version ($Arch, channel $vpkChannel) packed in $publish"
