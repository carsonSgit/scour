#!/bin/sh
set -eu

repo=${SCOUR_REPOSITORY:-carsonSgit/scour}
version=${SCOUR_VERSION:-latest}
install_dir=${SCOUR_INSTALL_DIR:-"$HOME/.local/bin"}
uname_s=${SCOUR_UNAME_S:-$(uname -s)}
uname_m=${SCOUR_UNAME_M:-$(uname -m)}

if [ "$version" = latest ]; then
  version=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" |
    sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  [ -n "$version" ] || {
    echo "scour: could not resolve latest release version" >&2
    exit 1
  }
fi
case "$version" in
  v*) ;;
  *) version="v$version" ;;
esac
release_path="download/$version"

case "$uname_s:$uname_m" in
  Linux:x86_64|Linux:amd64) target=linux-x86_64 ;;
  Linux:aarch64|Linux:arm64) target=linux-aarch64 ;;
  Darwin:x86_64) target=macos-x86_64 ;;
  Darwin:arm64|Darwin:aarch64) target=macos-aarch64 ;;
  MINGW*:x86_64|MSYS*:x86_64|CYGWIN*:x86_64) target=windows-x86_64 ;;
  *) echo "scour: unsupported platform: $uname_s $uname_m" >&2; exit 1 ;;
esac

case "$target" in
  windows-*) archive="scour-${version}-${target}.zip"; binary=scour.exe ;;
  *) archive="scour-${version}-${target}.tar.gz"; binary=scour ;;
esac
checksums="scour-${version}-checksums.txt"
base_url="https://github.com/$repo/releases/$release_path"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

curl -fsSL "$base_url/$archive" -o "$tmp_dir/$archive"
curl -fsSL "$base_url/$checksums" -o "$tmp_dir/$checksums"
expected=$(grep "  $archive\$" "$tmp_dir/$checksums" | awk '{print $1}')
[ -n "$expected" ] || {
  echo "scour: checksum missing for $archive" >&2
  exit 1
}
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$tmp_dir/$archive" | awk '{print $1}')
else
  actual=$(shasum -a 256 "$tmp_dir/$archive" | awk '{print $1}')
fi
[ "$expected" = "$actual" ] || {
  echo "scour: checksum verification failed for $archive" >&2
  exit 1
}
case "$archive" in
  *.zip)
    command -v unzip >/dev/null 2>&1 || {
      echo "scour: unzip is required to install $archive" >&2
      exit 1
    }
    unzip -q "$tmp_dir/$archive" -d "$tmp_dir"
    ;;
  *) tar -xzf "$tmp_dir/$archive" -C "$tmp_dir" ;;
esac
chmod +x "$tmp_dir/$binary"
mkdir -p "$install_dir"
install "$tmp_dir/$binary" "$install_dir/$binary.tmp"
mv "$install_dir/$binary.tmp" "$install_dir/$binary"
echo "Installed scour to $install_dir/$binary"
