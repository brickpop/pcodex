#!/usr/bin/env bash
# Tests the pcodex launcher against a fake `podman` that records its argv, one argument
# per line, so nothing is built or run for real.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Stand-in for `podman`: `image exists` answers from $FAKE_NO_IMAGE, everything else is
# appended to $FAKE_LOG as one call per block, and exits with $FAKE_STATUS.
mkdir -p "$tmp/bin"
cat >"$tmp/bin/podman" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "image exists" ]; then [ -z "${FAKE_NO_IMAGE:-}" ]; exit; fi
{ printf '%s\n' "$@"; echo "--"; } >>"$FAKE_LOG"
exit "${FAKE_STATUS:-0}"
EOF
chmod +x "$tmp/bin/podman"
export PATH="$tmp/bin:$PATH" FAKE_LOG="$tmp/log" PCODEX_RELABEL=off
unset PCODEX_IMAGE PCODEX_HOME PCODEX_ARGS PCODEX_NO_YOLO PCODEX_ALLOW_HOME XDG_DATA_HOME \
      OPENAI_API_KEY OPENAI_BASE_URL CODEX_API_KEY CODEX_ACCESS_TOKEN GH_TOKEN TERM COLORTERM

run() { status=0; "$root/pcodex" "$@" >"$tmp/stdout" 2>"$tmp/stderr" || status=$?; }
eq() { [ "$1" = "$2" ] || { printf '  expected: %s\n  got:      %s\n' "$2" "$1"; exit 1; }; }
# Fails unless these arguments appear consecutively in the log, e.g. `seq_in_log --volume "$a:$b"`.
seq_in_log() {
  local want; want="$(printf '\037%s' "$@")"$'\037'
  { printf '\037'; tr '\n' '\037' <"$FAKE_LOG"; } | grep -qF -- "$want" || { echo "  log lacks: $*"; exit 1; }
}
not_forwarded() { ! grep -q "^$1=" "$FAKE_LOG" || { echo "  forwarded: $1"; exit 1; }; }
# Everything after the image name in the (last) run call.
cmd() { sed -n '/^localhost\/pcodex$/,/^--$/p' "$FAKE_LOG" | sed '1d;$d' | paste -sd' '; }
no_calls() { [ ! -e "$FAKE_LOG" ] || { echo "  podman was called"; exit 1; }; }

test_runs_codex_yolo_with_args_untouched() {
  run exec "two words" '$HOME' --model o3
  eq "$status" 0
  eq "$(cmd)" 'codex --dangerously-bypass-approvals-and-sandbox exec two words $HOME --model o3'
  seq_in_log codex --dangerously-bypass-approvals-and-sandbox exec "two words" '$HOME' --model o3
}
test_no_yolo_drops_bypass_flag() {
  PCODEX_NO_YOLO=1 run resume
  eq "$(cmd)" "codex resume"
}
test_shell_runs_bash_without_codex_flags() {
  run --pcodex-shell -c "ls"
  eq "$(cmd)" "bash -c ls"
}
test_launcher_option_after_codex_args_goes_to_codex() {
  run exec --pcodex-shell
  eq "$(cmd)" "codex --dangerously-bypass-approvals-and-sandbox exec --pcodex-shell"
}
test_project_mounted_at_its_own_path() {
  run
  seq_in_log --volume "$PWD:$PWD" --workdir "$PWD"
  seq_in_log --volume "$HOME/.codex:/home/node/.codex"
  [ -d "$HOME/.codex" ] || { echo "  ~/.codex not created"; exit 1; }
}
test_nothing_else_of_home_is_mounted() {
  run
  eq "$(grep -c -- '^--volume$' "$FAKE_LOG")" 2
}
test_gitconfig_mounted_read_only_when_present() {
  touch "$HOME/.gitconfig"; run
  seq_in_log --volume "$HOME/.gitconfig:/home/node/.gitconfig:ro"
}
test_relabel_suffixes() {
  touch "$HOME/.gitconfig"; PCODEX_RELABEL=Z run
  seq_in_log --volume "$PWD:$PWD:Z"
  seq_in_log --volume "$HOME/.codex:/home/node/.codex:Z"
  seq_in_log --volume "$HOME/.gitconfig:/home/node/.gitconfig:ro,Z"
}
test_bad_relabel_is_refused() {
  PCODEX_RELABEL=yes run
  eq "$status" 1; grep -q "PCODEX_RELABEL must be" "$tmp/stderr" || exit 1; no_calls
}
test_only_set_env_is_forwarded() {
  OPENAI_API_KEY="sk with space" GH_TOKEN="" run
  seq_in_log --env "OPENAI_API_KEY=sk with space"
  not_forwarded GH_TOKEN; not_forwarded OPENAI_BASE_URL
}
test_extra_podman_args_come_before_image() {
  PCODEX_ARGS="-e FOO=bar  -v /a:/b" run x
  seq_in_log -e FOO=bar -v /a:/b localhost/pcodex codex
}
test_refuses_home() {
  cd "$HOME" && run
  eq "$status" 1; grep -q "refusing to mount all of" "$tmp/stderr" || exit 1; no_calls
}
test_home_allowed_on_request() {
  cd "$HOME" && PCODEX_ALLOW_HOME=1 run
  eq "$status" 0; seq_in_log --volume "$HOME:$HOME"
}
test_refuses_root() {
  cd / && run
  eq "$status" 1; no_calls
}
test_exit_status_propagates() {
  FAKE_STATUS=7 run
  eq "$status" 7
}
test_missing_image_is_built_first() {
  FAKE_NO_IMAGE=1 run
  eq "$status" 0
  seq_in_log build -t localhost/pcodex "$HOME/.local/share/pcodex" -- run
}
test_missing_dockerfile_fails_clearly() {
  rm "$HOME/.local/share/pcodex/Dockerfile"; FAKE_NO_IMAGE=1 run
  eq "$status" 1; grep -q "no Dockerfile in" "$tmp/stderr" || exit 1; no_calls
}
test_build_passes_extra_args() {
  run --pcodex-build --build-arg CODEX_VERSION=1.2.3
  eq "$status" 0
  eq "$(paste -sd' ' "$FAKE_LOG")" "build -t localhost/pcodex --build-arg CODEX_VERSION=1.2.3 $HOME/.local/share/pcodex --"
}
test_update_rebuilds_from_scratch() {
  run --pcodex-update
  eq "$(paste -sd' ' "$FAKE_LOG")" "build -t localhost/pcodex --pull --no-cache $HOME/.local/share/pcodex --"
}
test_custom_image_and_home() {
  mkdir -p "$tmp/share" && touch "$tmp/share/Dockerfile"
  PCODEX_IMAGE=localhost/other PCODEX_HOME="$tmp/share" run --pcodex-build
  eq "$(paste -sd' ' "$FAKE_LOG")" "build -t localhost/other $tmp/share --"
}
test_help_prints_usage_only() {
  run --pcodex-help
  eq "$status" 0; grep -q "^Usage: pcodex" "$tmp/stdout" || exit 1; no_calls
}

failed=0
for t in $(declare -F | awk '/ test_/ {print $3}'); do
  export HOME="$tmp/home"
  rm -rf "$HOME" "$FAKE_LOG" "$tmp/project"
  mkdir -p "$HOME/.local/share/pcodex" "$tmp/project"
  touch "$HOME/.local/share/pcodex/Dockerfile"
  ( set -e; cd "$tmp/project"; "$t" )
  if [ $? = 0 ]; then echo "ok   ${t#test_}"; else echo "FAIL ${t#test_}"; failed=1; fi
done
exit "$failed"
