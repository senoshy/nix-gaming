#!/usr/bin/env bash
# Refresh info.json from the current state of the official PokeOne update
# server. Run this after the game has been updated upstream.
set -euo pipefail

cd "$(dirname "$0")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bash ./fetch-game.sh "$tmp"

hash="$(nix hash path --algo sha256 "$tmp")"
updated="$(date -u +%Y-%m-%d)"

cat > info.json <<EOF
{
  "hash": "$hash",
  "updated": "$updated"
}
EOF

echo "Updated info.json: $hash"
