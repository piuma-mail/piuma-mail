# Builds the Windows release and publishes it to the update feed: an
# installer (PiumaMail-win-Setup.exe) for a first install, and the
# packages the app's updater downloads, with the changelog attached.
#
# Needs Flutter, Visual Studio (see CONTRIBUTING.md) and Velopack's CLI:
#   dotnet tool install -g vpk --version 1.2.161
#
# The feed and credentials come from the environment, never the repository:
#   PIUMA_UPDATE_URL   the feed's public address, built into the app
#                      (default: https://github.com/piuma-mail/piuma-mail)
#   PIUMA_PUBLISH      where to upload: "github" (default), "s3", or "none"
#   GITHUB_TOKEN       token with release write permissions (for github)
#   PIUMA_GITHUB_REPO  repository URL if different from PIUMA_UPDATE_URL
#                      (default: https://github.com/piuma-mail/piuma-mail)
#   PIUMA_S3_ENDPOINT  the bucket's S3 endpoint (when PIUMA_PUBLISH is "s3")
#                      (https://<account>.r2.cloudflarestorage.com)
#   PIUMA_S3_BUCKET    the bucket, "piuma-updates" when unset
#   PIUMA_S3_PREFIX    the folder in the bucket, "windows" when unset
#   PIUMA_S3_KEY_ID    an R2 API token's access key id...
#   PIUMA_S3_SECRET    ...and its secret
# When PIUMA_PUBLISH is "none" (or credentials are missing for local runs),
# the release is only built, into app\build\releases.
#
# Usage: powershell -File tools\windows-release.ps1 [-Notes notes.md]
# Without -Notes the changelog lists the pull requests merged since the
# last release built here (the local tag windows-release, or latest v* tag).
# The version is 0.1.0-beta.N, N = commits on this branch + 700, as on
# Android: releases made before the repository moved reached beta.679,
# and Velopack would not update to a lower number.
param([string]$Notes = "")
$ErrorActionPreference = "Stop"

$root = Resolve-Path "$PSScriptRoot\.."
$feed = if ($env:PIUMA_UPDATE_URL) { $env:PIUMA_UPDATE_URL } else { "https://github.com/piuma-mail/piuma-mail" }

$publish = if ($env:PIUMA_PUBLISH) { $env:PIUMA_PUBLISH.ToLower() } else { "github" }
if ($publish -notin @("github", "s3", "none")) {
  throw "Unknown PIUMA_PUBLISH target '$publish': expected 'github', 's3', or 'none'."
}

$build = [int](git -C $root rev-list --count HEAD).Trim() + 700
$version = "0.1.0-beta.$build"
$out = "$root\app\build\releases"
# Fresh each time: a package left by an earlier run of the same build
# would stop vpk pack.
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $out | Out-Null

if (-not $Notes) {
  $Notes = "$out\notes-$build.md"
  $since = git -C $root rev-parse -q --verify windows-release 2>$null
  if (-not $since) {
    $tag = git -C $root describe --tags --abbrev=0 --match "v*" 2>$null
    if ($tag) {
      $since = git -C $root rev-parse -q --verify "$tag^{commit}" 2>$null
    }
  }
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

$repoUrl = if ($env:PIUMA_GITHUB_REPO) {
  $env:PIUMA_GITHUB_REPO
} elseif ($feed -and $feed.StartsWith("https://github.com/")) {
  $feed
} else {
  "https://github.com/piuma-mail/piuma-mail"
}

$token = $env:GITHUB_TOKEN

$s3 = $env:PIUMA_S3_ENDPOINT -and $env:PIUMA_S3_KEY_ID -and $env:PIUMA_S3_SECRET
$bucket = if ($env:PIUMA_S3_BUCKET) { $env:PIUMA_S3_BUCKET } else { "piuma-updates" }
$prefix = if ($env:PIUMA_S3_PREFIX) { $env:PIUMA_S3_PREFIX } else { "windows" }
$s3Keys = @("--bucket", $bucket, "--prefix", $prefix, "--endpoint", $env:PIUMA_S3_ENDPOINT,
  "--keyId", $env:PIUMA_S3_KEY_ID, "--secret", $env:PIUMA_S3_SECRET, "--region", "auto")

# The last release, so the new one also ships as a small delta (the
# first time there is none, and that is fine).
if ($publish -eq "github") {
  $ghDownload = @("download", "github", "--repoUrl", $repoUrl, "-o", $out, "--pre")
  if ($token) { $ghDownload += @("--token", $token) }
  vpk @ghDownload
} elseif ($publish -eq "s3" -and $s3) {
  vpk download s3 -o $out @s3Keys
}

vpk pack --packId PiumaMail --packVersion $version --packTitle "Piuma Mail" `
  --packDir "$root\app\build\windows\x64\runner\Release" --mainExe piuma_mail.exe `
  --icon "$root\app\windows\runner\resources\app_icon.ico" `
  --shortcuts StartMenuRoot,Desktop --aumid Piuma.PiumaMail `
  --releaseNotes $Notes -o $out
if ($LASTEXITCODE) { throw "vpk pack failed" }

if ($publish -eq "github") {
  if ($token) {
    vpk upload github -o $out --repoUrl $repoUrl --token $token --publish --pre `
      --tag "v$version" --releaseName "Piuma Mail $version"
    if ($LASTEXITCODE) { throw "vpk upload failed" }
    git -C $root tag -f windows-release HEAD | Out-Null
    Write-Host "Piuma Mail $version published: $repoUrl/releases/tag/v$version"
  } else {
    if ($env:PIUMA_PUBLISH -eq "github" -or $env:CI) {
      throw "GITHUB_TOKEN must be set to publish to GitHub Releases."
    }
    Write-Host "Piuma Mail $version built in $out (not published: GITHUB_TOKEN not set)."
  }
} elseif ($publish -eq "s3") {
  if ($s3) {
    vpk upload s3 -o $out @s3Keys --keepMaxReleases 10
    if ($LASTEXITCODE) { throw "vpk upload failed" }
    git -C $root tag -f windows-release HEAD | Out-Null
    Write-Host "Piuma Mail $version published: $feed/PiumaMail-win-Setup.exe"
  } else {
    if ($env:PIUMA_PUBLISH -eq "s3" -or $env:CI) {
      throw "PIUMA_S3_ENDPOINT, PIUMA_S3_KEY_ID, and PIUMA_S3_SECRET must be set to publish to S3."
    }
    Write-Host "Piuma Mail $version built in $out (not published: no S3 keys)."
  }
} else {
  Write-Host "Piuma Mail $version built in $out (not published: PIUMA_PUBLISH=none)."
}
