# PI: pi coding agent (earendil-works/pi) + PI WEB browser client
# (jmfederico/pi-web), merged into one container for Unraid.
#
# The env contract (HOME/XDG under /data, PI_WEB_SESSIOND_SOCKET,
# PI_CODING_AGENT_DIR) mirrors pi-web's own docker packaging, so everything
# the app persists lands in the single /data volume. Versions come from
# versions.json via build args; CI bumps them as upstream releases.
FROM node:24-bookworm-slim

# Agent working tools plus the toolchain node-pty (browser terminals) and any
# node-gyp pi package need. procps for the entrypoint's process management.
# openssh-server + gosu: direct SSH into the container (Termius lands in the
# pi TUI); sshd runs as root, everything else drops to the pi user via gosu.
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl git gosu jq less nano openssh-client openssh-server procps ripgrep tini unzip \
    python3 make g++ \
 && rm -rf /var/lib/apt/lists/*

ARG PI_VERSION
ARG PI_WEB_VERSION

# pi-web first with peer deps (pulls a compatible pi), then pin pi explicitly
# so versions.json is the single source of truth for both.
# No smoke-test invocations here: pi-web-server has no exiting --help and
# would serve forever inside the RUN layer (this hung the first CI build for
# half an hour). Binary presence is verified without executing anything.
RUN npm install -g --omit=dev --include=peer --no-audit --no-fund \
      "@jmfederico/pi-web@${PI_WEB_VERSION}" \
 && npm install -g --ignore-scripts --no-audit --no-fund \
      "@earendil-works/pi-coding-agent@${PI_VERSION}" \
 && npm cache clean --force \
 && test -x "$(command -v pi)" && test -x "$(command -v pi-web-server)" && test -x "$(command -v pi-web-sessiond)"

# Unraid convention: nobody:users. The agent, the terminals, the SSH logins,
# and every file written run as this user; root exists at runtime only for
# sshd and the entrypoint's privilege drop.
ARG PUID=99
ARG PGID=100
RUN groupadd -g ${PGID} -o pi 2>/dev/null || true \
 && useradd -u ${PUID} -g ${PGID} -o -m -s /bin/bash pi \
 && usermod -d /data/home pi \
 && mkdir -p /data && chown ${PUID}:${PGID} /data

# SSH: key auth against /data/home/.ssh/authorized_keys; password auth only
# if the entrypoint is handed PI_SSH_PASSWORD. Host keys live in /data/ssh so
# clients never see the key change across image updates.
RUN printf '%s\n' \
      'Port 22' \
      'HostKey /data/ssh/ssh_host_ed25519_key' \
      'HostKey /data/ssh/ssh_host_rsa_key' \
      'PermitRootLogin no' \
      'AllowUsers pi' \
      'PubkeyAuthentication yes' \
      'PasswordAuthentication no' \
      'X11Forwarding no' \
      'PrintMotd no' \
      > /etc/ssh/sshd_config.d/pi.conf

ENV HOME=/data/home \
    XDG_CONFIG_HOME=/data/config \
    PI_WEB_HOST=0.0.0.0 \
    PI_WEB_PORT=8504 \
    PI_WEB_DATA_DIR=/data/pi-web \
    PI_WEB_SESSIOND_SOCKET=/data/pi-web/sessiond.sock \
    PI_CODING_AGENT_DIR=/data/pi-agent \
    PI_TELEMETRY=0 \
    PI_SKIP_VERSION_CHECK=1 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    SHELL=/bin/bash \
    TERM=xterm-256color

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

WORKDIR /data/workspace
EXPOSE 8504 22

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8504/api/pi-web/runtime >/dev/null || exit 1

ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
