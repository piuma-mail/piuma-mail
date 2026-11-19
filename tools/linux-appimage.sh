#!/bin/sh
# Packs a Linux release build into an AppImage: one file that runs on
# most x86_64 distributions without installing anything.
#
#   cd app && flutter build linux --release ...
#   sh tools/linux-appimage.sh [output.AppImage]
#
# Why an AppImage and not a Flatpak bundle: it is a single download from
# the GitHub release, like the APK and the Windows installer, and the app's
# "new version" notice points at it; a Flatpak bundle needs Flatpak and the
# GNOME runtime installed first, and a Flatpak build has no network, so
# every Rust crate and Dart package would have to be listed in a manifest.
# A Flathub listing can come later and reuse the same build.
#
# The AppImage carries the app (the Flutter bundle) but not GTK, WebKitGTK
# or libsecret: they come from the system (Ubuntu 24.04, Debian 13,
# Fedora 40 or newer; see CONTRIBUTING.md). It is not signed.
#
# appimagetool and the AppImage runtime are downloaded at fixed versions
# and checked against their SHA-256 before they run.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
arch=$(uname -m)
out=${1:-$root/app/build/PiumaMail-linux-$arch.AppImage}
bundle=$root/app/build/linux/x64/release/bundle
[ "$arch" = aarch64 ] && bundle=$root/app/build/linux/arm64/release/bundle

if [ "$arch" != x86_64 ]; then
  echo "Only x86_64 AppImages for now (the tools below are pinned for it)." >&2
  exit 1
fi
if [ ! -x "$bundle/piuma_mail" ]; then
  echo "No Linux release build in $bundle: run flutter build linux --release first." >&2
  exit 1
fi

TOOL_URL=https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
TOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
RUNTIME_URL=https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64
RUNTIME_SHA256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
curl -fsSL --retry 3 -o "$work/appimagetool" "$TOOL_URL"
curl -fsSL --retry 3 -o "$work/runtime" "$RUNTIME_URL"
echo "$TOOL_SHA256  $work/appimagetool" | sha256sum -c -
echo "$RUNTIME_SHA256  $work/runtime" | sha256sum -c -
chmod +x "$work/appimagetool"

app=$work/PiumaMail.AppDir
mkdir -p "$app"
cp -a "$bundle/." "$app/"
cat > "$app/AppRun" <<'RUN'
#!/bin/sh
here=$(dirname "$(readlink -f "$0")")
exec "$here/piuma_mail" "$@"
RUN
chmod +x "$app/AppRun"
cat > "$app/mail.piuma.piuma_mail.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Piuma Mail
Comment=Mail, made light
Exec=piuma_mail %U
Icon=piuma-mail
Categories=Network;Email;
MimeType=x-scheme-handler/mailto;
StartupWMClass=mail.piuma.piuma_mail
DESKTOP
cp "$root/app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png" "$app/piuma-mail.png"
ln -s piuma-mail.png "$app/.DirIcon"

# No FUSE on CI runners: appimagetool unpacks itself instead.
mkdir -p "$(dirname "$out")"
APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 "$work/appimagetool" --no-appstream \
  --runtime-file "$work/runtime" "$app" "$out"
echo "Piuma Mail AppImage: $out"
