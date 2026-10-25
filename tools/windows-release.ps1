# Builds the Windows release and publishes it to the update feed: an
# installer (PiumaMail-win-Setup.exe) for a first install, and the
# packages the app's updater downloads, with the changelog attached.
#
# Needs Flutter, Visual Studio (see CONTRIBUTING.md) and Velopack's CLI:
#   dotnet tool install -g vpk --version 1.2.161
#
# The feed and its keys come from the environment, never the repository:
#   PIUMA_UPDATE_URL   the feed's public address, built into the app
#                      (e.g. https://updates.piumamail.app/windows)
#   PIUMA_S3_ENDPOINT  the bucket's S3 endpoint
#                      (https://<account>.r2.cloudflarestorage.com)
#   PIUMA_S3_BUCKET    the bucket, "piuma-updates" when unset
#   PIUMA_S3_PREFIX    the folder in the bucket, "windows" when unset
#   PIUMA_S3_KEY_ID    an R2 API token's access key id...
#   PIUMA_S3_SECRET    ...and its secret
# Without the S3 variables the release is only built, into app\build\releases.
#
# Usage: powershell -File tools\windows-release.ps1 [-Notes notes.md]
# Without -Notes the changelog lists the pull requests merged since the
# last release built here (the local tag windows-release).
# The version is 0.1.0-beta.N, N = commits on this branch, as on Android.
param([string]$Notes = "")
$ErrorActionPreference = "Stop"

$root = Resolve-Path "$PSScriptRoot\.."
$feed = $env:PIUMA_UPDATE_URL
if (-not $feed) { throw "PIUMA_UPDATE_URL must be set: the app checks it for updates." }

$build = (git -C $root rev-list --count HEAD).Trim()
$version = "0.1.0-beta.$build"
$out = "$root\app\build\releases"
# Fresh each time: a package left by an earlier run of the same build
# would stop vpk pack.
Remove-Item -Recurse -Force $out -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $out | Out-Null

if (-not $Notes) {
  $Notes = "$out\notes-$build.md"
  $since = git -C $root rev-parse -q --verify windows-release 2>$null
  $range = if ($since) { "windows-release..HEAD" } else { "HEAD~20..HEAD" }
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

$s3 = $env:PIUMA_S3_ENDPOINT -and $env:PIUMA_S3_KEY_ID -and $env:PIUMA_S3_SECRET
$bucket = if ($env:PIUMA_S3_BUCKET) { $env:PIUMA_S3_BUCKET } else { "piuma-updates" }
$prefix = if ($env:PIUMA_S3_PREFIX) { $env:PIUMA_S3_PREFIX } else { "windows" }
$keys = @("--bucket", $bucket, "--prefix", $prefix, "--endpoint", $env:PIUMA_S3_ENDPOINT,
  "--keyId", $env:PIUMA_S3_KEY_ID, "--secret", $env:PIUMA_S3_SECRET, "--region", "auto")

# The last release, so the new one also ships as a small delta (the
# first time there is none, and that is fine).
if ($s3) { vpk download s3 -o $out @keys }

vpk pack --packId PiumaMail --packVersion $version --packTitle "Piuma Mail" `
  --packDir "$root\app\build\windows\x64\runner\Release" --mainExe piuma_mail.exe `
  --icon "$root\app\windows\runner\resources\app_icon.ico" `
  --shortcuts StartMenuRoot,Desktop --aumid Piuma.PiumaMail `
  --releaseNotes $Notes -o $out
if ($LASTEXITCODE) { throw "vpk pack failed" }

if ($s3) {
  vpk upload s3 -o $out @keys --keepMaxReleases 10
  if ($LASTEXITCODE) { throw "vpk upload failed" }
  git -C $root tag -f windows-release HEAD | Out-Null
  Write-Host "Piuma Mail $version published: $feed/PiumaMail-win-Setup.exe"
} else {
  Write-Host "Piuma Mail $version built in $out (not published: no S3 keys)."
}
