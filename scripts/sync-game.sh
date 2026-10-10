#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Использование: $0 <папка star conflict из Steam>" >&2
  echo "Примеры путей:" >&2
  echo "  Linux: ~/.steam/steam/steamapps/common/star conflict" >&2
  echo "  macOS: ~/Library/Application Support/Steam/steamapps/common/star conflict" >&2
  exit 1
fi

SRC="$1"
DST="$(cd "$(dirname "$0")/.." && pwd)/game"

echo "SRC=$SRC"
echo "DST=$DST"

if [[ ! -d "$SRC/cloud" ]]; then echo "FATAL: нет $SRC/cloud" >&2; exit 1; fi

mkdir -p "$DST"
rsync -a --delete \
  --exclude 'cloud/mongodb/data/' \
  --exclude 'cloud/Exceptions/' \
  --exclude 'win64/' \
  --exclude 'EmptySteamDepot/' \
  "$SRC/cloud/" "$DST/cloud/"
rsync -a --delete "$SRC/data/" "$DST/data/"
rsync -a --delete "$SRC/sys_data/" "$DST/sys_data/"

echo "--- result ---"
du -sh "$DST"/* | sort
echo "OK. Дальше: cp .env.example .env, правь SERVER_HOST, затем docker compose build && docker compose up"
