# PI

[pi coding agent](https://pi.dev/) (earendil-works/pi) merged with the
[PI WEB](https://pi-web.dev/) browser client (jmfederico/pi-web) into one
container image for Unraid: `ghcr.io/nphil/pi`.

Chat with the agent, review file diffs, manage git worktrees, and open real
interactive terminals from any browser. A session daemon keeps agent runs
alive after the tab closes.

## How updates work

Fully automatic, three stages:

1. `.github/workflows/watch-upstream.yml` polls npm every six hours for new
   releases of `@earendil-works/pi-coding-agent` and `@jmfederico/pi-web`.
   On a change it bumps `versions.json` and pushes.
2. That triggers `build.yml`, which builds the image with both versions
   pinned as build args and pushes `:latest` plus an immutable
   `:pi<ver>-web<ver>` tag to GHCR.
3. On the server, `unraid/update-pi.sh` (User Scripts, daily cron) pulls
   `:latest` and recreates the container when the digest moves.

To pin or roll back: edit `versions.json` by hand (the watcher will not
downgrade it until upstream moves past), or point the container at an
immutable tag.

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

## Security model

- The container plus the non-root user is the sandbox: pi itself has none,
  so the blast radius is the `/data` mount and LAN network access.
- PI WEB has **no built-in auth** and upstream says do not expose it
  publicly. This deployment is internal only (LAN + tailnet); no WAN
  forward, no public proxy. If a hostname is ever wanted, put basic auth on
  it at the reverse proxy and forward WebSocket upgrades.

## Unraid

`unraid/my-PI.xml` is the dockerMan template (app name **PI**, port 8504,
one `/data` path mapping). `unraid/update-pi.sh` is the auto-update user
script; it recreates with its own canonical args, so keep it and the
template in sync when changing either.
