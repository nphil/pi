# OMP: the oh-my-pi coding agent (can1357/oh-my-pi) + the Cody browser UI
# (nphil/cody, the ompweb successor), merged into one container for Unraid.
#
# Two runtimes on purpose: omp is Bun-only (engines.bun >=1.3.14, and it ships
# raw TypeScript rather than compiled JS), while Cody is a Node/Next app.
# They stay in ONE container by necessity: Cody spawns `omp --mode rpc-ui` as
# a child process over stdio and shares its filesystem (agent dir, workspace),
# so they cannot be split. Their versions still move independently.
#
# Cody is not on npm; it is built from a pinned commit of github.com/nphil/cody
# in this stage and only the built app is copied into the runtime image.
FROM node:24-bookworm AS cody-build
ARG CODY_REF=main
RUN git clone https://github.com/nphil/cody /src && git -C /src checkout "${CODY_REF}"
WORKDIR /src
# next build needs devDependencies; prune after. mkdir public: the repo has no
# public/ dir today but the package layout expects one.
RUN npm ci --no-audit --no-fund \
 && npm run build \
 && npm prune --omit=dev \
 && mkdir -p public /app \
 && cp -r package.json next.config.ts node_modules .next bin lib public /app/

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

# omp through Bun (it is a Bun package). Verified with `test -x`, never by
# running it: the server does not exit.
RUN bun install -g "@oh-my-pi/pi-coding-agent@${OMP_VERSION}" \
 && test -x "$(command -v omp)"

# Cody, prebuilt in the first stage. chown 99:100 = the omp user below, so the
# server (which runs as omp, unlike Cody's own root image) owns its app dir.
COPY --from=cody-build --chown=99:100 /app /opt/cody
RUN ln -s /opt/cody/bin/cody.js /usr/local/bin/cody \
 && chmod 0755 /opt/cody/bin/cody.js \
 && test -x "$(command -v cody)" && test -d /opt/cody/.next

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
# Cody reads CODY_* first with OMP_WEB_* as legacy fallbacks, so an old
# template that still passes OMP_WEB_PASSWORD keeps working. HOME under /data
# is what makes Cody read the same ~/.omp/agent state ompweb read; do NOT set
# PI_CODING_AGENT_DIR (Cody's own image points it at /data/agent, which would
# silently boot an empty agent here).
ENV HOME=/data/home \
    XDG_CONFIG_HOME=/data/config \
    CODY_HOSTNAME=0.0.0.0 \
    CODY_NO_OPEN=1 \
    CODY_OMP_BIN=/usr/local/bin/omp \
    CODY_HARNESS=omp \
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
