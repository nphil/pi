#!/bin/bash
# Runs as root: starts sshd (the only root process), drops everything else to
# the pi user via gosu. tini is PID 1; if any of the three processes dies we
# exit so the restart policy brings the set back.
set -e

SOCK="${PI_WEB_SESSIOND_SOCKET:-/data/pi-web/sessiond.sock}"

mkdir -p /data/home /data/config /data/pi-web /data/pi-agent /data/workspace /data/ssh /run/sshd
chown pi:users /data /data/home /data/config /data/pi-web /data/pi-agent /data/workspace

# SSH host keys persist across image updates so clients never see them change.
[ -f /data/ssh/ssh_host_ed25519_key ] || ssh-keygen -q -t ed25519 -f /data/ssh/ssh_host_ed25519_key -N ""
[ -f /data/ssh/ssh_host_rsa_key ] || ssh-keygen -q -t rsa -b 4096 -f /data/ssh/ssh_host_rsa_key -N ""
chown root:root /data/ssh/ssh_host_* && chmod 600 /data/ssh/ssh_host_*_key

# Optional password login (template variable, masked). Without it: keys only,
# via /data/home/.ssh/authorized_keys.
if [ -n "${PI_SSH_PASSWORD:-}" ]; then
  echo "pi:${PI_SSH_PASSWORD}" | chpasswd
  sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/pi.conf
fi

# SSH sessions start with a fresh environment; hand them the pi variables so
# the TUI shares state with the web sessions, and the persistence paths so
# their installs land in /data/home like everything else.
{
  echo "export PI_CODING_AGENT_DIR=${PI_CODING_AGENT_DIR}"
  echo "export PI_WEB_SESSIOND_SOCKET=${SOCK}"
  echo "export PI_TELEMETRY=${PI_TELEMETRY:-0}"
  echo "export PI_SKIP_VERSION_CHECK=${PI_SKIP_VERSION_CHECK:-1}"
  echo "export NPM_CONFIG_PREFIX=${NPM_CONFIG_PREFIX:-/data/home/.npm-global}"
  echo "export PIP_BREAK_SYSTEM_PACKAGES=1"
  echo 'export PATH=/data/home/.npm-global/bin:/data/home/.local/bin:$PATH'
} > /etc/profile.d/00-pi-env.sh

# First boot only: SSH logins land in the pi TUI, and quitting pi drops to
# bash. The file lives in /data/home and belongs to the user; edit or delete
# it there to change the behavior.
if [ ! -f /data/home/.bash_profile ]; then
  cat > /data/home/.bash_profile <<'PROFILE'
# SSH lands in the pi TUI; quitting pi drops to this bash shell.
# This file is yours (persisted in /data/home). Edit or delete to change it.
[ -f ~/.bashrc ] && . ~/.bashrc
if [[ $- == *i* && -z "$PI_TUI_DONE" ]]; then
  export PI_TUI_DONE=1
  cd /data/workspace
  pi
  echo "pi TUI closed. You are in bash now; exit to disconnect."
fi
PROFILE
  chown pi:users /data/home/.bash_profile
fi

# First boot only: seed the re-provision hook. Agents (and you) append apt
# installs and other root-level setup here; it runs as root on every container
# start, so overlay-level changes come back after image updates.
if [ ! -f /data/on-boot.sh ]; then
  cat > /data/on-boot.sh <<'ONBOOT'
#!/bin/bash
# Runs as root at every container start, AFTER the image's own setup.
# Put apt installs and other system-level provisioning here so they survive
# image updates (the container filesystem outside /data resets on every
# update). Example:
#   apt-get update && apt-get install -y --no-install-recommends imagemagick
# Tools that prove durable belong in the Dockerfile at github.com/nphil/pi.
ONBOOT
  chmod +x /data/on-boot.sh
  chown pi:users /data/on-boot.sh
fi

if [ -x /data/on-boot.sh ]; then
  echo "[entrypoint] running /data/on-boot.sh"
  /data/on-boot.sh || echo "[entrypoint] on-boot.sh exited nonzero; continuing"
fi

rm -f "$SOCK" 2>/dev/null || true

/usr/sbin/sshd -D -e &
SSHD_PID=$!

gosu pi pi-web-sessiond &
SESSIOND_PID=$!

trap 'kill -TERM $SSHD_PID $SESSIOND_PID $SERVER_PID 2>/dev/null; wait' TERM INT

for _ in $(seq 1 50); do
  [ -S "$SOCK" ] && break
  sleep 0.2
done

gosu pi pi-web-server &
SERVER_PID=$!

wait -n
kill -TERM $SSHD_PID $SESSIOND_PID $SERVER_PID 2>/dev/null || true
exit 1
