# Builds the Windows release and publishes it to GitHub Releases as a
# prerelease: an installer (PiumaMail-win-Setup.exe) for a first install,
# and the packages the app's updater downloads, with the changelog attached.
# The "Release" workflow (.github/workflows/release.yml) runs it.
#
# Needs Flutter, Visual Studio (see CONTRIBUTING.md) and Velopack's CLI:
#   dotnet tool install -g vpk --version 1.2.161
#
# From the environment, never the repository:
#   GITHUB_TOKEN       a token that can write the repository's releases;
#                      without it the release is only built, into
#                      app\build\releases
#   PIUMA_UPDATE_URL   the repository the app checks for updates
#                      (https://github.com/piuma-mail/piuma-mail when unset)
#
# Usage: powershell -File tools\windows-release.ps1 [-Arch x64|arm64] [-Notes notes.md]
# Without -Notes the changelog lists the pull requests merged since the
# last v* tag.
# The version is 0.1.0-beta.N, N = commits on this branch + 700, as on
# Android: releases made before the repository moved reached beta.679,
# and Velopack would not update to a lower number.
#
# -Arch arm64 builds for Windows on ARM; Flutter does that only on an
# ARM64 machine. It goes in Velopack's "win-arm64" channel
# (PiumaMail-win-arm64-Setup.exe, releases.win-arm64.json), next to x64's
# default "win" one, and is added to the release the x64 build published
# for the same commit, so run it after that. An installed app follows the
# channel it was installed from, so each machine keeps its own build.
param(
  [ValidateSet("x64", "arm64")][string]$Arch = "x64",
  [string]$Notes = ""
)
$ErrorActionPreference = "Stop"

$root = Resolve-Path "$PSScriptRoot\.."
$feed = if ($env:PIUMA_UPDATE_URL) { $env:PIUMA_UPDATE_URL } else { "https://github.com/piuma-mail/piuma-mail" }
$token = $env:GITHUB_TOKEN
if ($env:CI -and -not $token) { throw "GITHUB_TOKEN must be set to publish the release." }

$build = [int](git -C $root rev-list --count HEAD).Trim() + 700
$version = "0.1.0-beta.$build"
$out = "$root\app\build\releases"
# x64 keeps Velopack's defaults (channel "win", architecture read from
# the exe), as in the releases already installed.
$channel = @()
if ($Arch -eq "arm64") { $channel = @("--channel", "win-arm64") }
# Fresh each time: a package left by an earlier run of the same build
# would stop vpk pack.
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $out | Out-Null

if (-not $Notes) {
  $Notes = "$out\notes-$build.md"
  # Listed, not described: git describe writes to stderr when there is no
  # tag yet, and Windows PowerShell stops on that. This version's own tag
  # is skipped: the arm64 build runs once x64 has published it.
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

Push-Location "$root\app"
try {
  flutter build windows --release --build-name 0.1.0 --build-number $build `
    --dart-define=PIUMA_BUILD=$build --dart-define=PIUMA_UPDATE_URL=$feed
  if ($LASTEXITCODE) { throw "flutter build failed" }
} finally { Pop-Location }

# The last release of this channel, so the new one also ships as a small
# delta (the first time there is none, and that is fine).
if ($token) { vpk download github --repoUrl $feed --token $token --pre @channel -o $out }

$runtime = @()
if ($Arch -eq "arm64") { $runtime = @("--runtime", "win-arm64") }
vpk pack --packId PiumaMail --packVersion $version --packTitle "Piuma Mail" `
  --packDir "$root\app\build\windows\$Arch\runner\Release" --mainExe piuma_mail.exe `
  --icon "$root\app\windows\runner\resources\app_icon.ico" `
  --shortcuts StartMenuRoot,Desktop --aumid Piuma.PiumaMail `
  --releaseNotes $Notes @channel @runtime -o $out
if ($LASTEXITCODE) { throw "vpk pack failed" }

if ($token) {
  # arm64 joins the release x64 created (--merge); its files and its
  # releases.win-arm64.json have their own names, so nothing is replaced.
  $merge = @()
  if ($Arch -eq "arm64") { $merge = @("--merge") }
  vpk upload github -o $out --repoUrl $feed --token $token --publish --pre @channel @merge `
    --tag "v$version" --releaseName "Piuma Mail $version"
  if ($LASTEXITCODE) { throw "vpk upload failed" }
  Write-Host "Piuma Mail $version ($Arch) published: $feed/releases/tag/v$version"
} else {
  Write-Host "Piuma Mail $version ($Arch) built in $out (not published: no GITHUB_TOKEN)."
}
