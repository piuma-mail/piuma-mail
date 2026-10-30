#!/bin/sh
# Builds the Android beta: a release APK for 64-bit ARM phones, signed
# with the project's beta key so each new build installs over the last.
#
# The key comes from the environment, never from the repository:
#   PIUMA_KEYSTORE_B64       the keystore (PKCS12 or JKS), base64
#   PIUMA_KEYSTORE_PASSWORD  its password (also the key's, unless
#                            PIUMA_KEY_PASSWORD is set)
#   PIUMA_KEY_ALIAS          the key's alias, "piuma" when unset
#
# Usage: sh tools/android-beta.sh [output.apk]
# The version is 0.1.0, build number = commits on this branch + 700:
# builds made before the repository moved reached 709, and a lower
# number would not install over them.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$root/app/build/piuma-mail-beta.apk}

if [ -z "${PIUMA_KEYSTORE_B64:-}" ] || [ -z "${PIUMA_KEYSTORE_PASSWORD:-}" ]; then
  echo "PIUMA_KEYSTORE_B64 and PIUMA_KEYSTORE_PASSWORD must be set." >&2
  echo "Without the beta key each build would need the app uninstalled first." >&2
  exit 1
fi

keystore=$(mktemp)
trap 'rm -f "$keystore"' EXIT
printf '%s' "$PIUMA_KEYSTORE_B64" | base64 -d > "$keystore"

build=$(( $(git -C "$root" rev-list --count HEAD) + 700 ))
cd "$root/app"
PIUMA_KEYSTORE_FILE=$keystore flutter build apk --release \
  --target-platform android-arm64 \
  --build-name 0.1.0 --build-number "$build" \
  --dart-define=PIUMA_BUILD="$build"
mkdir -p "$(dirname "$out")"
cp build/app/outputs/flutter-apk/app-release.apk "$out"
echo "Piuma Mail 0.1.0 ($build): $out"
