# PI and OMP

Two self-hosted coding-agent containers for Unraid, built and version-tracked
here. **PI** is pi + PI WEB (this document). **OMP** is the oh-my-pi fork with
subagents and model roles, plus the ompweb browser UI, and lives in
[](./omp) with its own image, template and README. They are siblings:
separate images, addresses, state and quotas.

## PI

[pi coding agent](https://pi.dev/) (earendil-works/pi) merged with the
[PI WEB](https://pi-web.dev/) browser client (jmfederico/pi-web) into one
container image for Unraid: `ghcr.io/nphil/pi`.

Chat with the agent, review file diffs, manage git worktrees, and open real
interactive terminals from any browser. A session daemon keeps agent runs
alive after the tab closes.

## How updates work

The image tracks upstream automatically; applying it stays a deliberate
click in the Unraid Docker tab, like any other container:

1. `.github/workflows/watch-upstream.yml` polls npm every six hours for new
   releases of `@earendil-works/pi-coding-agent` and `@jmfederico/pi-web`.
   On a change it bumps `versions.json` and pushes.
2. That triggers `build.yml`, which builds the image with both versions
   pinned as build args and pushes `:latest` plus an immutable
   `:pi<ver>-web<ver>` tag to GHCR.
3. Unraid's Check for Updates sees the moved `:latest` digest and shows the
   update badge on the PI app; Apply Update recreates from the template.

The template is the single canonical container definition. To pin or roll
back: edit `versions.json` by hand (the watcher will not downgrade it until
upstream moves past), or point the template at an immutable tag.

## Layout inside the container

Everything persists under the single `/data` volume, following pi-web's own
docker env contract:

| Path | What |
| --- | --- |
| `/data/pi-agent` | pi state: `models.json`, `settings.json`, sessions, auth |
| `/data/pi-web` | pi-web state and the sessiond socket |
| `/data/config` | XDG config (`pi-web/config.json`) |
| `/data/home` | HOME for the `pi` user (UID 99, GID 100 = Unraid nobody:users) |
| `/data/workspace` | where the agent works; clone repos here |

Seed configs for a llama-swap backed setup are in `config-seeds/`.

## What persists, and where installs go

The `/data` volume is the whole persistent world (on the Unraid host it is a
ZFS dataset with a 20G quota, so agents cannot fill the pool). The rules:

- **User-level installs persist automatically**: `npm -g` is prefixed to
  `/data/home/.npm-global`, `pip` / `uv tool` / `pipx` land in
  `/data/home/.local`, and both are on PATH for web terminals, SSH sessions,
  and agent bash alike. Python projects should use venvs (`uv venv`) in the
  workspace.
- **The pi user has passwordless sudo**, so agents can `sudo apt install`
  and do any root-level setup they need. The container is the wall: no
  docker socket, not privileged, one quota'd mount, internal network only.
- **System-level changes live in the overlay and reset on every image
  update.** The bridge is `/data/on-boot.sh`: it runs as root on every
  container start, so apt installs appended there re-apply themselves after
  updates. Tools that prove durable graduate to the Dockerfile's toolbox
  layer — CI builds the image and the update shows up in the Unraid Docker
  tab like any other.

The image ships a real toolbox out of the box: python3 + venv + pip + pipx +
uv, node (base image), make/g++/pkg-config for native builds, git and the
GitHub CLI, ripgrep, fd, jq, sqlite3, rsync, tree, htop, and friends.

## SSH straight into the TUI

The container runs its own sshd, so an SSH client (Termius, anything)
connects to the container directly — never to the host — and lands in the
pi TUI. Quitting pi drops to a bash shell for maintenance; `exit`
disconnects. The behavior lives in `/data/home/.bash_profile` (seeded on
first boot, then yours to edit).

- Auth is key-only by default: put your public key in
  `/data/home/.ssh/authorized_keys`. Setting the `PI_SSH_PASSWORD` template
  variable enables password login for the `pi` user.
- Host keys persist in `/data/ssh`, so clients never see a key change across
  image updates.
- sshd is the only process that runs as root; logins, the agent, and the web
  stack all run as the `pi` user (UID 99).

## Security model

- The container plus the non-root user is the sandbox: pi itself has none,
  so the blast radius is the `/data` mount and LAN network access.
- PI WEB has **no built-in auth** and upstream says do not expose it
  publicly. This deployment is internal only (LAN + tailnet); no WAN
  forward, no public proxy. If a hostname is ever wanted, put basic auth on
  it at the reverse proxy and forward WebSocket upgrades.

## Unraid

`unraid/my-PI.xml` is the dockerMan template (app name **PI**, port 8504,
one `/data` path mapping) and the only place the container's run arguments
live: dockerMan recreates from the XML on every Apply Update, so any change
that matters must land there.
