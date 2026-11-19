#!/bin/sh
# Checks that every ABI an APK carries has the app's own native libraries.
# Android picks the ABI from the folders under lib/: one that holds only a
# plugin's prebuilt library (CameraX, jni) but not libflutter.so or the
# engine makes the app install and then crash at launch
# (UnsatisfiedLinkError: dlopen failed: library "libpiuma_bridge.so").
#
# Usage: sh tools/check-apk-abis.sh app.apk [library.so ...]
# libflutter.so and libapp.so are always required; name more (the phone
# app needs libpiuma_bridge.so). Expected ABIs can be pinned with
# PIUMA_APK_ABIS="arm64-v8a" (space-separated): any other is an error.
set -eu

apk=${1:?usage: check-apk-abis.sh app.apk [library.so ...]}
shift
[ -f "$apk" ] || { echo "No such APK: $apk" >&2; exit 1; }

listing=$(unzip -Z1 "$apk")
abis=$(printf '%s\n' "$listing" | sed -n 's|^lib/\([^/]*\)/[^/]*$|\1|p' | sort -u)
if [ -z "$abis" ]; then
  echo "$apk: no native libraries at all." >&2
  exit 1
fi

status=0
for abi in $abis; do
  for lib in libflutter.so libapp.so "$@"; do
    if ! printf '%s\n' "$listing" | grep -qxF "lib/$abi/$lib"; then
      echo "$apk: lib/$abi/ has no $lib: a device that picks $abi would crash at launch." >&2
      status=1
    fi
  done
done

if [ -n "${PIUMA_APK_ABIS:-}" ]; then
  want=$(printf '%s\n' $PIUMA_APK_ABIS | sort -u)
  if [ "$want" != "$abis" ]; then
    echo "$apk: carries ABIs [$(echo $abis)], expected [$(echo $want)]." >&2
    status=1
  fi
fi

[ "$status" = 0 ] && echo "$apk: ABIs $(echo $abis), each with every library."
exit "$status"
