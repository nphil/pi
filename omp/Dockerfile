# OMP: the oh-my-pi coding agent (can1357/oh-my-pi) + the ompweb browser UI
# (kahme247/ompweb), merged into one container for Unraid.
#
# Two runtimes on purpose: omp is Bun-only (engines.bun >=1.3.14, and it ships
# raw TypeScript rather than compiled JS), while ompweb is a Node/Next app.
# They are not coupled the way pi and PI WEB are: ompweb spawns the `omp`
# binary as a subprocess (execFile / --mode rpc, resolved via OMP_WEB_OMP_BIN),
# so their versions move independently and neither can break the other's API.
#
# This is a SIBLING of the PI container, not a replacement. PI (pi + PI WEB)
# stays exactly as it is; the two agents keep separate state and addresses.
FROM node:24-bookworm-slim

# Same agentic-coding toolbox as PI, so an agent here can actually work:
# python + venv/pipx/uv, native build chain, git + gh, search tools, plus
# openssh-server for SSH-into-the-TUI and gosu/sudo for the privilege model.
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates curl file git gosu htop jq less nano openssh-client openssh-server \
    procps rsync ripgrep fd-find sqlite3 sudo tini tree unzip wget xz-utils zip \
    python3 python3-pip python3-venv pipx \
    make g++ pkg-config \
 && ln -s "$(command -v fdfind)" /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p -m 755 /etc/apt/keyrings \
 && wget -qO /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/* \
 && curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Bun, required by omp. BUN_INSTALL=/usr/local puts the binary and every
# `bun install -g` shim on the system PATH instead of a user's home.
ENV BUN_INSTALL=/usr/local
ARG BUN_VERSION=1.3.14
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" \
 && bun --version

ARG OMP_VERSION
ARG OMPWEB_VERSION

# omp through Bun (it is a Bun package), ompweb through npm (a Node app).
# Verified with `test -x`, never by running them: the servers do not exit.
RUN bun install -g "@oh-my-pi/pi-coding-agent@${OMP_VERSION}" \
 && npm install -g --no-audit --no-fund "@kahme247/ompweb@${OMPWEB_VERSION}" \
 && npm cache clean --force \
 && test -x "$(command -v omp)" && test -x "$(command -v ompweb)"

# Unraid convention: nobody:users. sshd is the only root process at runtime.
ARG PUID=99
ARG PGID=100
RUN groupadd -g ${PGID} -o omp 2>/dev/null || true \
 && useradd -u ${PUID} -g ${PGID} -o -m -s /bin/bash omp \
 && usermod -d /data/home omp \
 && mkdir -p /data && chown ${PUID}:${PGID} /data \
 && echo "omp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/omp \
 && chmod 0440 /etc/sudoers.d/omp

RUN printf '%s\n' \
      'Port 22' \
      'HostKey /data/ssh/ssh_host_ed25519_key' \
      'HostKey /data/ssh/ssh_host_rsa_key' \
      'PermitRootLogin no' \
      'AllowUsers omp' \
      'PubkeyAuthentication yes' \
      'PasswordAuthentication no' \
      'X11Forwarding no' \
      'PrintMotd no' \
      > /etc/ssh/sshd_config.d/omp.conf

# HOME under /data is what puts omp's own state (~/.omp/agent: models.yml,
# config.yml, auth.json, sessions) inside the single persistent volume.
# User-level installs persist the same way they do in the PI image.
ENV HOME=/data/home \
    XDG_CONFIG_HOME=/data/config \
    OMP_WEB_HOSTNAME=0.0.0.0 \
    OMP_WEB_PORT=30177 \
    OMP_WEB_NO_OPEN=1 \
    OMP_WEB_OMP_BIN=/usr/local/bin/omp \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    NPM_CONFIG_PREFIX=/data/home/.npm-global \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PATH=/data/home/.npm-global/bin:/data/home/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    SHELL=/bin/bash \
    TERM=xterm-256color

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY config-seeds/ /usr/local/share/omp-seeds/
RUN chmod 0755 /usr/local/bin/entrypoint.sh

WORKDIR /data/workspace
EXPOSE 30177 22

# The UI sits behind Basic Auth, so an unauthenticated probe gets 401 from a
# perfectly healthy server: 401 is proof of life here, only a refused
# connection or a 5xx means trouble.
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD sh -c 'c=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:30177/) && { [ "$c" = "200" ] || [ "$c" = "401" ]; }' || exit 1

ENTRYPOINT ["tini", "--", "/usr/local/bin/entrypoint.sh"]
