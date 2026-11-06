#!/usr/bin/env bash
# Installs the pcodex launcher into ~/.local/bin and builds the image.
set -euo pipefail

src="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="${HOME}/.local/bin"
share="${PCODEX_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/pcodex}"

command -v podman >/dev/null || { echo "podman is not installed — see the README" >&2; exit 1; }

mkdir -p "$bin" "$share"
install -m 0644 "$src/Dockerfile" "$share/Dockerfile"
install -m 0755 "$src/pcodex" "$bin/pcodex"
echo "installed: $bin/pcodex"
echo "installed: $share/Dockerfile"

"$bin/pcodex" --pcodex-build "$@"

case ":$PATH:" in
  *":$bin:"*) ;;
  *)
    echo
    echo "NOTE: $bin is not on your PATH. Add it:"
    echo "  bash/zsh:  echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
    echo "  fish:      fish_add_path ~/.local/bin"
    ;;
esac

echo
echo "Done. Run 'pcodex' inside any project directory."
