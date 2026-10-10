#!/usr/bin/env bash
set -euo pipefail

SC_ROOT="${SC_ROOT:-/opt/sc}"
CLOUD_DIR="$SC_ROOT/cloud"
HUB_EXE="$CLOUD_DIR/Hub.exe"
CLOUD_XML="$CLOUD_DIR/data/cloud.xml"
COMMON_LOCAL_CFG="$CLOUD_DIR/data/common_local.cfg"

SERVER_HOST="${SERVER_HOST:-127.0.0.1}"
SERVER_PORT="${SERVER_PORT:-3850}"
MONGO_HOST="${MONGO_HOST:-mongo}"
MONGO_PORT="${MONGO_PORT:-27017}"
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
SSH_PORT_HUB="${SSH_PORT_HUB:-2222}"
SSH_PASSWD="${SSH_PASSWD:-}"
SSH_PASSWD_FILE="/logs/.hub_ssh_passwd"
HUB_LOCAL_CFG="$CLOUD_DIR/data/hub_local.cfg"
HUB_LOG="/logs/hub.log"

mkdir -p /logs

echo "[sc] WINEPREFIX=$WINEPREFIX WINEARCH=$WINEARCH"
echo "[sc] server=$SERVER_HOST:$SERVER_PORT mongo=$MONGO_HOST:$MONGO_PORT redis=$REDIS_HOST:$REDIS_PORT"

FAKE_IF="dummy-pub"
FAKE_IF_MODE="${FAKE_IF_MODE:-dummy}"
FAKE_HOSTS="${FAKE_HOSTS:-1}"
if [[ "$SERVER_HOST" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$SERVER_HOST" != "127.0.0.1" ]]; then
  if ip -4 addr show | grep -qwF "$SERVER_HOST"; then
    echo "[sc] $SERVER_HOST уже есть в контейнере"
  elif [[ "$FAKE_IF_MODE" == "none" ]]; then
    echo "[sc] FAKE_IF_MODE=none: интерфейс не трогаю"
  elif ip link show 2>/dev/null | grep -Eq '^[0-9]+: (wg[0-9a-zA-Z]*|tailscale[0-9a-zA-Z]*|tun[0-9a-zA-Z]*):'; then
    echo "[sc][WARN] вижу VPN-интерфейс и host-сеть: НЕ создаю $FAKE_IF (убил бы VPN)." >&2
    echo "[sc][WARN] убери '-f docker-compose.prod.yml' чтобы IP создался в netns контейнера." >&2
  elif [[ "$FAKE_IF_MODE" == "eth0" ]]; then
    ETHDEV="$(ip route show default 2>/dev/null | awk '{print $5; exit}')"
    ETHDEV="${ETHDEV:-eth0}"
    if ! ip -4 addr show dev "$ETHDEV" | grep -qwF "$SERVER_HOST"; then
      echo "[sc] add $SERVER_HOST/32 to $ETHDEV (вторичный, внутри контейнера)..."
      ip addr add "$SERVER_HOST/32" dev "$ETHDEV" 2>&1 || \
        echo "[sc][WARN] не смог повесить $SERVER_HOST на $ETHDEV — проверь cap_add: [NET_ADMIN]" >&2
    else
      echo "[sc] $SERVER_HOST уже есть на $ETHDEV"
    fi
  else
    if ! ip link show "$FAKE_IF" &>/dev/null; then
      echo "[sc] создаю $FAKE_IF (только внутри контейнера)..."
      if ! ip link add "$FAKE_IF" type dummy 2>&1; then
        echo "[sc] dummy недоступен, пробую veth..."
        ip link add "$FAKE_IF" type veth peer name "${FAKE_IF}-peer" 2>&1 || true
      fi
    fi
    if ip link show "$FAKE_IF" &>/dev/null; then
      ip link set "$FAKE_IF" up 2>&1 || true
      if ! ip -4 addr show dev "$FAKE_IF" | grep -qwF "$SERVER_HOST"; then
        echo "[sc] add $SERVER_HOST/32 to $FAKE_IF..."
        if ! ip addr add "$SERVER_HOST/32" dev "$FAKE_IF" 2>&1; then
          echo "[sc][WARN] не смог повесить $SERVER_HOST — проверь cap_add: [NET_ADMIN] у sc-server" >&2
        fi
      fi
    else
      echo "[sc][WARN] не смог создать $FAKE_IF (нет NET_ADMIN?)" >&2
    fi
  fi
  if [[ "$FAKE_HOSTS" == "1" ]]; then
    HNAME="$(hostname)"
    if [[ "$(getent hosts "$HNAME" 2>/dev/null | awk '{print $1; exit}')" != "$SERVER_HOST" ]]; then
      echo "[sc] point $HNAME -> $SERVER_HOST first in /etc/hosts..."
      grep -vE "[[:space:]]$HNAME([[:space:]]|$)" /etc/hosts > /tmp/sc-hosts.new || true
      { echo "$SERVER_HOST $HNAME"; cat /tmp/sc-hosts.new; } > /tmp/sc-hosts.out
      cat /tmp/sc-hosts.out > /etc/hosts || \
        echo "[sc][WARN] не смог переписать /etc/hosts" >&2
    else
      echo "[sc] $HNAME уже резолвится в $SERVER_HOST первым"
    fi
  else
    echo "[sc] FAKE_HOSTS=0: /etc/hosts не трогаю"
  fi
fi

if [[ ! -f "$HUB_EXE" ]]; then
  echo "[sc][FATAL] не найден $HUB_EXE — запусти scripts/sync-game.sh чтобы наполнить ./game/" >&2
  exit 1
fi

echo "[sc] patch addr-assert (if needed)..."
python3 /opt/entry/patch-addr-assert.py "$CLOUD_DIR"

if [[ "${PATCH_SECURITY:-0}" == "1" ]]; then
  echo "[sc] patch security-check (if needed)..."
  python3 /opt/entry/patch-security-check.py "$CLOUD_DIR"
else
  echo "[sc] PATCH_SECURITY=0: security-check пропущен"
fi

if [[ ! -f "$WINEPREFIX/system.reg" ]]; then
  echo "[sc] init wine prefix..."
  wineboot --init >/dev/null 2>&1 || true
fi

if [[ -f "$CLOUD_XML" ]]; then
  echo "[sc] patch cloud.xml Node address -> ${SERVER_HOST}:${SERVER_PORT}"
  SERVER_HOST="$SERVER_HOST" SERVER_PORT="$SERVER_PORT" CLOUD_XML="$CLOUD_XML" python3 - <<'EOF'
import os, re
p = os.environ["CLOUD_XML"]
with open(p, encoding="utf-8") as f:
    s = f.read()
new = f'address="{os.environ["SERVER_HOST"]}:{os.environ["SERVER_PORT"]}"'
s2, n = re.subn(r'address="[^"]*:\d+"', new, s, count=1)
if n == 0:
    s2, n = re.subn(r'<Node\b', f'<Node address="{os.environ["SERVER_HOST"]}:{os.environ["SERVER_PORT"]}"', s, count=1)
with open(p, "w", encoding="utf-8") as f:
    f.write(s2)
print(f"cloud.xml patched: {n} replacement(s)")
EOF
else
  echo "[sc][WARN] нет $CLOUD_XML" >&2
fi

cat > "$COMMON_LOCAL_CFG" <<EOF
set db_mongoHosts "${MONGO_HOST}:${MONGO_PORT}"
set db_redisHost "${REDIS_HOST}:${REDIS_PORT}|connpool=5"
EOF
echo "[sc] wrote $COMMON_LOCAL_CFG"

if [[ -n "$SSH_PASSWD" ]]; then
  echo -n "$SSH_PASSWD" > "$SSH_PASSWD_FILE"
  chmod 600 "$SSH_PASSWD_FILE"
elif [[ -f "$SSH_PASSWD_FILE" ]]; then
  SSH_PASSWD="$(cat "$SSH_PASSWD_FILE")"
else
  SSH_PASSWD="$(python3 -c 'import secrets, string; print("".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(16)))')"
  echo -n "$SSH_PASSWD" > "$SSH_PASSWD_FILE"
  chmod 600 "$SSH_PASSWD_FILE"
fi
cat > "$HUB_LOCAL_CFG" <<EOF
set ssh_port "${SSH_PORT_HUB}"
set ssh_passwd "${SSH_PASSWD}"
set ssh_privateKeyFile "Z:\\logs\\ssh_host_rsa"
set ssh_publicKeyFile "Z:\\logs\\ssh_host_rsa.pub"
EOF
echo "[sc] Hub SSH console on port ${SSH_PORT_HUB}, passwd in $SSH_PASSWD_FILE"
echo "[sc] Hub SSH password: ${SSH_PASSWD}"
if [[ ! -f /logs/ssh_host_rsa ]]; then
  echo "[sc] generating SSH host key..."
  ssh-keygen -t rsa -b 2048 -m PEM -N "" -f /logs/ssh_host_rsa -C "starconflict-hub" >/dev/null 2>&1
  chmod 600 /logs/ssh_host_rsa
fi

echo "[sc] wait mongo $MONGO_HOST:$MONGO_PORT (120s)..."
for i in $(seq 1 120); do
  if nc -z "$MONGO_HOST" "$MONGO_PORT" 2>/dev/null; then echo "[sc] mongo up"; break; fi
  sleep 1
  if [[ "$i" -eq 120 ]]; then echo "[sc][FATAL] mongo недоступен" >&2; exit 1; fi
done
echo "[sc] wait redis $REDIS_HOST:$REDIS_PORT (60s)..."
for i in $(seq 1 60); do
  if nc -z "$REDIS_HOST" "$REDIS_PORT" 2>/dev/null; then echo "[sc] redis up"; break; fi
  sleep 1
  if [[ "$i" -eq 60 ]]; then echo "[sc][FATAL] redis недоступен" >&2; exit 1; fi
done

shutdown() {
  echo "[sc] SIGTERM — останавливаю сервер..."
  wineserver -k || true
  echo "[sc] stopped."
  exit 0
}
trap shutdown TERM INT

echo "[sc] start Hub.exe..."
cd "$CLOUD_DIR"
wine "$HUB_EXE" 2>&1 | tee "$HUB_LOG" &
HUB_PID=$!
echo "[sc] Hub pid=$HUB_PID, log: $HUB_LOG"
wait "$HUB_PID"
