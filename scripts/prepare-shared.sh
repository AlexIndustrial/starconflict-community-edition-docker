#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== run prepareSharedData in container =="
docker exec -w /opt/sc/cloud starconflict-server \
  bash -c 'export WINEDEBUG=-all; wine DedicatedServer.exe -logFileName prepare_shared.log -nullCon -prepareSharedData -ds datasources_defs_build.txt 2>&1 | tail -n 5'

echo "== prepare_shared.log tail =="
docker exec starconflict-server tail -n 8 "/opt/wineprefix/drive_c/users/root/AppData/Local/Targem/StarConflict/cloud/StarConflict DedicatedServer/prepare_shared.log" 2>&1
echo "DONE"
