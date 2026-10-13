#!/usr/bin/env bash
# Hub SSH console login. Usage:
#   scripts/hub-console.sh           # interactive console
#   scripts/hub-console.sh "uptime"  # single command (args forwarded to ssh)
set -euo pipefail
PASS="$(docker run --rm -v starconflict_sc-logs:/logs --platform linux/amd64 debian:bookworm-slim cat /logs/.hub_ssh_passwd 2>/dev/null || true)"
if [[ -z "$PASS" ]]; then
  echo "Пароль ещё не создан (сервер стартует?) либо volume пуст." >&2
  echo "Свой пароль можно задать через SSH_PASSWD в окружении sc-server." >&2
  exit 1
fi
# Hub's SSH is 2015-era: explicit legacy algorithms for modern clients.
SSH_OPTS=(-p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
  -o KexAlgorithms=+diffie-hellman-group1-sha1 -o HostKeyAlgorithms=+ssh-rsa
  -o Ciphers=+aes128-cbc -o MACs=+hmac-sha1)
# The old server sometimes negotiates a DH key with <512 significant bits,
# which modern clients reject ("key bits do not match") — just retry.
if command -v sshpass >/dev/null 2>&1; then
  for i in 1 2 3 4; do
    if sshpass -p "$PASS" ssh "${SSH_OPTS[@]}" hub@127.0.0.1 "$@"; then
      exit 0
    fi
    sleep 1
  done
  exec sshpass -p "$PASS" ssh "${SSH_OPTS[@]}" hub@127.0.0.1 "$@"
else
  echo "Пароль Hub-консоли: $PASS  (установи sshpass для автовхода: brew install sshpass)"
  for i in 1 2 3 4; do
    if ssh "${SSH_OPTS[@]}" hub@127.0.0.1 "$@"; then
      exit 0
    fi
    sleep 1
  done
  exec ssh "${SSH_OPTS[@]}" hub@127.0.0.1 "$@"
fi
