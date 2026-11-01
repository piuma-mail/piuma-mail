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
# Usage: powershell -File tools\windows-release.ps1 [-Notes notes.md]
# Without -Notes the changelog lists the pull requests merged since the
# last v* tag.
# The version is 0.1.0-beta.N, N = commits on this branch + 700, as on
# Android: releases made before the repository moved reached beta.679,
# and Velopack would not update to a lower number.
param([string]$Notes = "")
$ErrorActionPreference = "Stop"

$root = Resolve-Path "$PSScriptRoot\.."
$feed = if ($env:PIUMA_UPDATE_URL) { $env:PIUMA_UPDATE_URL } else { "https://github.com/piuma-mail/piuma-mail" }
$token = $env:GITHUB_TOKEN
if ($env:CI -and -not $token) { throw "GITHUB_TOKEN must be set to publish the release." }

$build = [int](git -C $root rev-list --count HEAD).Trim() + 700
$version = "0.1.0-beta.$build"
$out = "$root\app\build\releases"
# Fresh each time: a package left by an earlier run of the same build
# would stop vpk pack.
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $out | Out-Null

if (-not $Notes) {
  $Notes = "$out\notes-$build.md"
  # Listed, not described: git describe writes to stderr when there is no
  # tag yet, and Windows PowerShell stops on that.
  $since = git -C $root tag --list "v*" --merged HEAD --sort=-creatordate | Select-Object -First 1
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

# The last release, so the new one also ships as a small delta (the
# first time there is none, and that is fine).
if ($token) { vpk download github --repoUrl $feed --token $token --pre -o $out }

vpk pack --packId PiumaMail --packVersion $version --packTitle "Piuma Mail" `
  --packDir "$root\app\build\windows\x64\runner\Release" --mainExe piuma_mail.exe `
  --icon "$root\app\windows\runner\resources\app_icon.ico" `
  --shortcuts StartMenuRoot,Desktop --aumid Piuma.PiumaMail `
  --releaseNotes $Notes -o $out
if ($LASTEXITCODE) { throw "vpk pack failed" }

if ($token) {
  vpk upload github -o $out --repoUrl $feed --token $token --publish --pre `
    --tag "v$version" --releaseName "Piuma Mail $version"
  if ($LASTEXITCODE) { throw "vpk upload failed" }
  Write-Host "Piuma Mail $version published: $feed/releases/tag/v$version"
} else {
  Write-Host "Piuma Mail $version built in $out (not published: no GITHUB_TOKEN)."
}
