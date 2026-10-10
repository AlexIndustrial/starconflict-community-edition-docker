#!/usr/bin/env bash
set -euo pipefail
PASS="$(docker run --rm -v starconflict_sc-logs:/logs --platform linux/amd64 debian:bookworm-slim cat /logs/.hub_ssh_passwd 2>/dev/null || true)"
if [[ -z "$PASS" ]]; then
  echo "Пароль ещё не создан (сервер стартует?) либо volume пуст." >&2
  echo "Свой пароль можно задать через SSH_PASSWD в окружении sc-server." >&2
  exit 1
fi
if command -v sshpass >/dev/null 2>&1; then
  exec sshpass -p "$PASS" ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null hub@127.0.0.1
else
  echo "Пароль Hub-консоли: $PASS  (установи sshpass для автовхода: brew install sshpass)"
  exec ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null hub@127.0.0.1
fi
