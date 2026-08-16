# OMP

[oh-my-pi](https://omp.sh/) (`omp`) — the subagent-and-model-roles fork of pi
by Can Bölük — with the [ompweb](https://github.com/kahme247/ompweb) browser
UI, in one container image: `ghcr.io/nphil/omp`.

**This is a sibling of the PI container, not a replacement.** PI (pi + PI WEB)
keeps running untouched. The two agents share nothing but the llama-swap
endpoint, and each has its own address, state directory and quota.

## Why not just swap pi for omp in the PI container

PI WEB embeds pi **in-process**, importing `createAgentSessionFromServices`,
`createAgentSessionRuntime` and `createAgentSessionServices` from
`@earendil-works/pi-coding-agent`. omp is a hard fork on a disjoint version
line (17.x vs 0.84.x) that publishes under `@oh-my-pi/*`, exports none of
those three symbols, ships raw TypeScript for Bun rather than compiled JS for
Node, and installs a binary named `omp` rather than `pi`. Any in-place swap
kills the browser IDE at startup, not at first use.

ompweb has none of that coupling: it **spawns the `omp` binary as a
subprocess** (`execFile`, `--mode rpc`, resolved through `OMP_WEB_OMP_BIN`),
so the agent and the UI version independently.

## Two runtimes, on purpose

| Component | Runtime | Why |
| --- | --- | --- |
| `omp` | Bun ≥1.3.14 | `engines.bun`; the package's library entry is raw `.ts` |
| `ompweb` | Node ≥22.19 | a Next.js app |

## Model roles: what actually routes

omp dispatches by **role**, and you decide what each role means
(`/data/home/.omp/agent/config.yml`). Roles: `default`, `smol`, `slow`,
`vision`, `plan`, `designer`, `commit`, `tiny`, `task`, `advisor`
(`advisor` inherits `slow`, `tiny` inherits `smol`). Background work —
session titles, memory, thinking-difficulty classification — automatically
uses `tiny`/`smol` without being asked. The `task` tool fans subagents out
into isolated worktrees and returns schema-validated results.

This deployment ships **cloud-first with locals as workers**: the thinking
roles are meant for Claude or ChatGPT once you log in, while `smol`, `tiny`,
`task`, `commit` and `vision` stay on llama-swap. The reason is context
budget — omp's system prompt plus tool prompts are roughly 26KB (~6k tokens)
before a file is read, which is a third of a 16k local window.

### Logging in to Claude and ChatGPT (the OAuth callback trap)

`/login` starts a callback server on **loopback inside the container** and the
provider redirects your browser to `http://localhost:<port>/callback`. Your
browser is on a different machine, where `localhost` is *your laptop* — so the
callback lands nowhere and the login appears to hang or error. Ports are fixed
per provider (`src/registry/oauth/*.ts`):

| Provider | Callback port |
| --- | --- |
| Claude Pro/Max (anthropic) | 54545 |
| ChatGPT Plus/Pro (openai-codex) | 1455 |
| Google Gemini CLI | 8085 |
| Google Antigravity | 51121 |

Two ways through, both supported:

**1. Forward the port over SSH (cleanest).** Connect with the callback port
tunnelled, then run `/login` in that session:

```bash
ssh -L 54545:127.0.0.1:54545 -L 1455:127.0.0.1:1455 omp@192.168.1.75
```

Your browser's `localhost:54545` now reaches the container and the callback
completes normally. In Termius, add these under the host's Port Forwarding as
local rules. `AllowTcpForwarding` is on in the image's sshd config, and the
redirect host cannot be changed instead — providers validate the registered
`http://localhost:<port>/callback` exactly.

**2. Paste the redirect URL (no setup).** Run `/login` normally, complete the
sign-in in the browser, and let the final redirect fail. Copy that dead URL
out of the address bar — it carries `?code=...&state=...` — and paste it at
omp's prompt. The flow offers this explicitly: *"If the browser cannot reach
this machine, paste the final redirect URL or authorization code when
prompted."*

**Note:** third-party harness usage of a Claude Pro/Max subscription is billed
per token as *extra usage*, not against plan limits.

## Updates

`omp-watch-upstream.yml` polls npm every six hours for `@oh-my-pi/pi-coding-agent`
and `@kahme247/ompweb`, bumps `omp/versions.json`, and dispatches
`omp-build.yml`, which pushes `:latest` plus an immutable
`:omp<ver>-web<ver>` tag. Unraid then shows an ordinary update badge; Apply
Update recreates from the template. omp releases 2-3 times a day, so to pin
or roll back, set a known-good pair in `versions.json` or point the template
at an immutable tag.

## Layout

Everything persists under `/data` (a ZFS dataset with a quota on the host):

| Path | What |
| --- | --- |
| `/data/home/.omp/agent` | omp state: `models.yml`, `config.yml`, `auth.json`, sessions |
| `/data/home` | HOME for the `omp` user (UID 99), SSH `authorized_keys` |
| `/data/ssh` | persistent SSH host keys |
| `/data/workspace` | where the agent works; clone repos here |
| `/data/on-boot.sh` | root-level provisioning re-applied at every start |

## Security

Container plus non-root user is the sandbox: no docker socket, not
privileged, one quota-capped mount, internal network only. The `omp` user has
passwordless sudo so agents can install what they need.

**`OMP_WEB_PASSWORD` is effectively required here, not optional.** ompweb
refuses to bind a non-loopback address without it, and says so plainly:
`Refusing to listen on 0.0.0.0 without OMP_WEB_PASSWORD.` Since this
container serves on its own LAN address, an empty password means a
restart loop rather than an open UI — a better default than PI WEB's, which
has no auth at all. The username is always `omp`. Basic Auth does not
encrypt, so keep this on the LAN or tailnet, never public.
