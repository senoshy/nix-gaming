#!/usr/bin/env bash
# Download the PokeOne client from the official update server.
#
# The Windows launcher keeps its files in sync using two manifests:
#   <base>/files    -> the game files, served from <base>/request/<path>
#   <base>/updater  -> Launcher.exe, served from <base>/request_updater/<path>
#
# Every file is served as a single-entry zip archive, which this script
# extracts. It is used both by the Nix fixed-output derivation and by
# update.sh, so the resulting directory is always laid out like the official
# installer (C:\PokeOne):
#
#   Launcher.exe
#   Launcher.exe.config
#   files/...
set -euo pipefail

out="${1:?usage: fetch-game.sh OUTDIR}"
base="${POKEONE_UPDATE_SERVER:-http://update.poke.one}"

mkdir -p "$out/files"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

curl -fsSL --retry 3 "$base/files" | tr -d '\r' > "$work/files.manifest"
curl -fsSL --retry 3 "$base/updater" | tr -d '\r' > "$work/updater.manifest"

# Turn a manifest into a curl config (parallel downloads) and a job list
# describing where each archive should be extracted.
#
# manifest lines look like:
#   PokeOne_Data\StreamingAssets\adata>MD5>FILETIME>UNCOMPRESSED>COMPRESSED
prepare() {
  local manifest="$1" name="$2" endpoint="$3" destprefix="$4"
  local n=0 path _md5 _filetime size _csize rel url

  mkdir -p "$work/$name"
  : > "$work/$name.jobs"
  : > "$work/$name.cfg"

  while IFS='>' read -r path _md5 _filetime size _csize; do
    [ -n "$path" ] || continue
    rel="$(printf '%s' "$path" | tr '\\' '/')"
    url="${rel// /%20}"
    n=$((n + 1))
    {
      printf 'url = "%s/%s/%s"\n' "$base" "$endpoint" "$url"
      printf 'output = "%s/%s/%s.zip"\n' "$work" "$name" "$n"
    } >> "$work/$name.cfg"
    printf '%s|%s|%s|%s\n' "$destprefix" "$rel" "$n" "$size" >> "$work/$name.jobs"
  done < "$manifest"
}

prepare "$work/files.manifest" files request "files/"
prepare "$work/updater.manifest" updater request_updater ""

# Download everything in parallel. --fail makes curl exit non-zero on HTTP
# errors, and the size checks below catch truncated files. The speed limit
# makes stalled connections retry instead of hanging forever.
curl --fail --silent --show-error --location \
  --connect-timeout 30 --retry 5 --retry-delay 2 \
  --speed-limit 1024 --speed-time 30 \
  --parallel --parallel-max 8 \
  --config "$work/files.cfg" \
  --config "$work/updater.cfg"

unpack() {
  local name="$1" destprefix rel n size dest
  while IFS='|' read -r destprefix rel n size; do
    [ -n "$rel" ] || continue
    dest="$out/$destprefix$rel"
    mkdir -p "$(dirname "$dest")"
    unzip -p "$work/$name/$n.zip" > "$dest"
    if [ "$(stat -c %s "$dest")" != "$size" ]; then
      echo "error: size mismatch for $rel (expected $size, got $(stat -c %s "$dest"))" >&2
      return 1
    fi
  done < "$work/$name.jobs"
}

unpack files
unpack updater
