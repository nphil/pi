#!/bin/bash
# Runs as root: starts sshd (the only root process) and drops Cody to the
# omp user via gosu. tini is PID 1; if either dies we exit so the restart
# policy brings the pair back.
set -e

# Cody refuses a non-loopback bind without a password (username: cody). Fail
# loudly here instead of leaving a silent restart loop to diagnose.
if [ -z "${CODY_PASSWORD:-${OMP_WEB_PASSWORD:-}}" ] && [ "${CODY_ALLOW_NO_AUTH:-}" != "1" ]; then
  echo "[entrypoint] CODY_PASSWORD is not set; Cody will refuse to listen on ${CODY_HOSTNAME:-0.0.0.0}. Set it in the template." >&2
  exit 1
fi

mkdir -p /data/home /data/config /data/workspace /data/ssh /data/home/.omp/agent /run/sshd
chown omp:users /data /data/home /data/config /data/workspace /data/home/.omp /data/home/.omp/agent

# SSH host keys persist so clients never see them change across image updates.
[ -f /data/ssh/ssh_host_ed25519_key ] || ssh-keygen -q -t ed25519 -f /data/ssh/ssh_host_ed25519_key -N ""
[ -f /data/ssh/ssh_host_rsa_key ] || ssh-keygen -q -t rsa -b 4096 -f /data/ssh/ssh_host_rsa_key -N ""
chown root:root /data/ssh/ssh_host_* && chmod 600 /data/ssh/ssh_host_*_key

if [ -n "${OMP_SSH_PASSWORD:-}" ]; then
  echo "omp:${OMP_SSH_PASSWORD}" | chpasswd
  sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config.d/omp.conf
fi

# Seed model providers and role assignments once. Both are user data after
# that: edit them in place, or from the web UI, and they survive updates.
# omp migrates a models.json into models.yml itself on first read.
if [ ! -f /data/home/.omp/agent/models.yml ] && [ ! -f /data/home/.omp/agent/models.json ]; then
  cp /usr/local/share/omp-seeds/models.json /data/home/.omp/agent/models.json
  chown omp:users /data/home/.omp/agent/models.json
fi
if [ ! -f /data/home/.omp/agent/config.yml ]; then
  cp /usr/local/share/omp-seeds/config.yml /data/home/.omp/agent/config.yml
  chown omp:users /data/home/.omp/agent/config.yml
fi

# SSH sessions get a fresh environment; hand them what the TUI needs.
{
  echo "export CODY_OMP_BIN=${CODY_OMP_BIN:-/usr/local/bin/omp}"
  echo "export NPM_CONFIG_PREFIX=${NPM_CONFIG_PREFIX:-/data/home/.npm-global}"
  echo "export PIP_BREAK_SYSTEM_PACKAGES=1"
  echo 'export PATH=/data/home/.npm-global/bin:/data/home/.local/bin:$PATH'
} > /etc/profile.d/00-omp-env.sh

# First boot only: SSH lands in the omp TUI, quitting omp drops to bash.
# Yours to edit afterwards, it lives in /data.
if [ ! -f /data/home/.bash_profile ]; then
  cat > /data/home/.bash_profile <<'PROFILE'
# SSH lands in the omp TUI; quitting omp drops to this bash shell.
# This file is yours (persisted in /data/home). Edit or delete to change it.
[ -f ~/.bashrc ] && . ~/.bashrc
if [[ $- == *i* && -z "$OMP_TUI_DONE" ]]; then
  export OMP_TUI_DONE=1
  cd /data/workspace
  omp
  echo "omp TUI closed. You are in bash now; exit to disconnect."
fi
PROFILE
  chown omp:users /data/home/.bash_profile
fi

# Root-level provisioning that must survive image updates goes here.
if [ ! -f /data/on-boot.sh ]; then
  cat > /data/on-boot.sh <<'ONBOOT'
#!/bin/bash
# Runs as root at every container start, AFTER the image's own setup.
# Put apt installs and other system-level provisioning here so they survive
# image updates (everything outside /data resets when the image updates).
#   apt-get update && apt-get install -y --no-install-recommends imagemagick
# Tools that prove durable belong in omp/Dockerfile at github.com/nphil/pi.
ONBOOT
  chmod +x /data/on-boot.sh
  chown omp:users /data/on-boot.sh
fi
[ -x /data/on-boot.sh ] && { echo "[entrypoint] running /data/on-boot.sh"; /data/on-boot.sh || echo "[entrypoint] on-boot.sh exited nonzero; continuing"; }

/usr/sbin/sshd -D -e &
SSHD_PID=$!

gosu omp env HOME=/data/home cody -H "${CODY_HOSTNAME:-0.0.0.0}" -p "${CODY_PORT:-30177}" --no-open &
WEB_PID=$!

trap 'kill -TERM $SSHD_PID $WEB_PID 2>/dev/null; wait' TERM INT

wait -n
kill -TERM $SSHD_PID $WEB_PID 2>/dev/null || true
exit 1
