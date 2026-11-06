# pcodex

Run [Codex CLI](https://github.com/openai/codex) inside a Podman container, sandboxed to
the directory you launch it from.

Codex runs with `--dangerously-bypass-approvals-and-sandbox`, so it never stops to ask —
but it can only see the current project, your `~/.codex` config and nothing else of your
machine.

```sh
cd ~/dev/some-project
pcodex
```

## Install

**1. Install Podman**

```sh
sudo dnf install podman          # Fedora / RHEL / CentOS
sudo apt install podman          # Debian / Ubuntu
sudo pacman -S podman            # Arch
brew install podman && podman machine init && podman machine start   # macOS
```

**2. Install pcodex**

```sh
git clone https://github.com/brickpop/pcodex.git
cd pcodex
./install.sh
```

This copies `pcodex` to `~/.local/bin`, the Dockerfile to `~/.local/share/pcodex`,
and builds the image (a few minutes).

If `~/.local/bin` is not on your `PATH`:

```sh
fish_add_path ~/.local/bin                                    # fish
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc      # bash/zsh
```

**3. Log in** once, on the host, with plain `codex login`. Codex stores the login in
`~/.codex/auth.json`, which is mounted into the container, so that single login covers
`pcodex` too and survives image rebuilds. Token refreshes inside the container are
written back to the same file, so host `codex` stays logged in as well.

This relies on Codex's default `cli_auth_credentials_store = "file"`. If your
`~/.codex/config.toml` sets it to `keyring` or `auto`, the login lives in the OS keyring,
which the container cannot reach, and `pcodex` will ask you to log in.

No host `codex`? Log in from inside the container instead with
`pcodex login --device-auth`. The plain browser flow does not work there: its callback
listens on `localhost:1455` inside the container, which your browser cannot reach.

If you authenticate with `OPENAI_API_KEY` or `CODEX_API_KEY` instead, no login is needed
at all — those are forwarded from the environment.

## Usage

Arguments are passed through to `codex` untouched:

```sh
pcodex                              # interactive session
pcodex exec "explain this repo"     # non-interactive
pcodex --model o3 resume --last     # any codex flag
pcodex mcp list                     # any codex subcommand
```

The launcher's own options are namespaced so they can never clash with a Codex flag:

| Option | |
|---|---|
| `--pcodex-build` | Build the image |
| `--pcodex-update` | Rebuild it from scratch, pulling the latest base and Codex |
| `--pcodex-shell` | Open a shell in the container instead of Codex |
| `--pcodex-help` | Usage |

### Running something other than Codex

The image sets `codex` as its `CMD` and clears the entrypoint, so Codex is only the
default — any command in the image can replace it, with no `--entrypoint` needed:

```sh
podman run --rm -it -v $PWD:$PWD:z -w $PWD localhost/pcodex        # codex
podman run --rm -it -v $PWD:$PWD:z -w $PWD localhost/pcodex bash   # a shell
podman run --rm -v $PWD:$PWD:z -w $PWD localhost/pcodex forge test # anything else
```

`pcodex --pcodex-shell` is just the shorthand for the second one, with all the usual
mounts applied.

## What gets mounted

| Host | Container | |
|---|---|---|
| `$PWD` | `$PWD` (same path) | read-write — the only project code Codex can reach |
| `~/.codex` | `/home/node/.codex` | login, `config.toml`, sessions, history |
| `~/.gitconfig` | `/home/node/.gitconfig` | read-only, if present |

`OPENAI_API_KEY`, `OPENAI_BASE_URL`, `CODEX_API_KEY`, `CODEX_ACCESS_TOKEN`, `GH_TOKEN`,
`TERM` and `COLORTERM` are forwarded when set. Nothing else from your machine is visible.
Running in `$HOME` itself is refused (it would defeat the point); set
`PCODEX_ALLOW_HOME=1` if you really mean it.

The project keeps its host path inside the container, and `HOME` stays `/home/node`.
Codex records each session's working directory and `codex resume` lists only the
sessions of the current one, so `pcodex resume --last` picks up where `codex` left off in
that same repo.

`~/.codex/config.toml` is shared with the host, so anything in it that points at host
paths or host-only programs (MCP server commands, `notify` scripts...) will not work
inside the container.

Codex's own sandbox (bubblewrap) is always off — the container is the sandbox, and it
couldn't create its namespaces in there anyway. `PCODEX_NO_YOLO=1` only brings back the
approval prompts (`--sandbox danger-full-access` keeps the inner sandbox off). The container runs with no capabilities
(`--cap-drop all`) and `no-new-privileges`, so nothing inside can escalate via setuid.

Note that the container has **unrestricted network access** — the sandbox is about your
filesystem, not about what Codex can reach online.

### SELinux

On Fedora/RHEL, bind mounts are relabelled with `:z` (shared) so that repeated and
concurrent sessions work. The stricter `:Z` gives each container a private MCS category,
which means a second `pcodex` session would relabel `~/.codex` out from under the first
and break it — use `PCODEX_RELABEL=Z` only if you run one session at a time. On
non-SELinux hosts no suffix is added at all.

To undo the relabelling of a directory later: `restorecon -R <dir>`.

## Configuration

| Variable | Default | |
|---|---|---|
| `PCODEX_IMAGE` | `localhost/pcodex` | image to run |
| `PCODEX_HOME` | `~/.local/share/pcodex` | where the Dockerfile lives |
| `PCODEX_ARGS` | — | extra `podman run` args |
| `PCODEX_NO_YOLO` | — | `1` makes Codex ask for approval when it sees fit (`--ask-for-approval on-request`) |
| `PCODEX_RELABEL` | `auto` | `z`, `Z` or `off` |
| `PCODEX_ALLOW_HOME` | — | `1` allows running in `$HOME` |

Mount something extra:

```sh
PCODEX_ARGS="-v $HOME/dev/shared-lib:/shared:z" pcodex
```

Forward your SSH agent, so Codex can push:

```sh
PCODEX_ARGS="-v $SSH_AUTH_SOCK:/ssh-agent:z -e SSH_AUTH_SOCK=/ssh-agent" pcodex
```

## What's in the image

One image, `localhost/pcodex`, built from `node:26-slim`. Everything is on `PATH`, so
Codex can reach for any of it:

| | |
|---|---|
| **Node** | node, npm — from the base image |
| **Bun** | bun |
| **Deno** | deno |
| **Foundry** | forge, cast, anvil, chisel |
| **Go** | go, with `GOPATH=/home/node/go` |
| **Codex** | codex (ships its own `rg`) |
| **Shell tools** | git, openssh, curl, jq, make, unzip, fzf, vim, less, ps, just, wiki |

The first build takes a few minutes; after that it is cached.

Pin a version at build time:

```sh
pcodex --pcodex-build --build-arg CODEX_VERSION=0.167.0
pcodex --pcodex-build --build-arg GO_VERSION=1.24.5
```

Any update Codex installs inside a running container is lost when it exits. Run
`pcodex --pcodex-update` now and then to bake in the current release. Codex installs
last in the `Dockerfile`, so bumping it reuses the toolchain layers.

## Development

```sh
just test
```

`test.sh` runs the launcher against a fake `podman` that records its arguments, so
nothing is built or started. It runs on Linux and macOS.

## Uninstall

```sh
rm ~/.local/bin/pcodex
rm -rf ~/.local/share/pcodex
podman rmi -f $(podman images localhost/pcodex -q)
```
