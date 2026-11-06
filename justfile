# List the available recipes
help:
    @just --list

# Run the launcher tests (against a fake podman)
[group('dev')]
test:
    ./test.sh
