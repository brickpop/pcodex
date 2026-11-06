# Tasks

## In progress

- [ ] Build the image and run a real session once (no Podman where the port was done):
      `codex --version` in the build, a host `codex login` being picked up, a token
      refresh inside the container landing in `~/.codex/auth.json`, and
      `pcodex resume --last` finding host sessions of the same repo.

## Open decisions

- [ ] `--tty` is always passed. With a non-terminal stdin (`pcodex exec ... | tee`, CI,
      piping a prompt in) Podman may refuse or mangle output. Pass `--tty` only when
      `[ -t 0 ]`?
- [ ] `PCODEX_NO_YOLO=1` re-enables Codex's own bubblewrap/landlock sandbox, which likely
      cannot create namespaces inside a rootless container. Keep it as "approvals + own
      sandbox", or make it pass `--sandbox danger-full-access` and only restore approvals?
- [ ] No up-front login check: with neither `~/.codex/auth.json` nor an API key, Codex
      itself asks to log in inside the container, where only `--device-auth` works. Fail
      early with a hint instead?

## Known limitations

- `PCODEX_ARGS` is split on whitespace only; quotes are not honoured, so a path with
  spaces cannot be mounted through it.
- Only `$PWD = $HOME` is refused. Running in a parent of `$HOME` (e.g. `/home`, `/Users`)
  still mounts every home directory below it.
- A `keyring`/`auto` `cli_auth_credentials_store` keeps the login out of reach of the
  container (documented in the README).
- Host-specific entries in the shared `~/.codex/config.toml` (MCP commands, `notify`)
  break inside the container.
- Two concurrent sessions may refresh the token at the same time; the loser holds a
  revoked refresh token and has to log in again.

## Done

- Ported from pclaude (Claude Code) to Codex CLI. The macOS Keychain sync is gone: Codex
  stores its login in `~/.codex/auth.json` by default, which is simply mounted.
- Launcher tests against a fake `podman` (`just test`), covering arg passthrough, yolo
  flag, mounts, relabelling, env forwarding, `$HOME`/`/` guards, builds and exit status.
