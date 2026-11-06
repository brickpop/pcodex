FROM docker.io/library/node:26-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      openssh-client \
      less \
      jq \
      make \
      unzip \
      fzf \
      vim \
      just \
      procps \
  && rm -rf /var/lib/apt/lists/*

# Go, pinned via build arg or resolved at build time with "latest".
ARG GO_VERSION=latest
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    ver="$GO_VERSION"; \
    if [ "$ver" = "latest" ]; then ver="$(curl -fsSL https://go.dev/VERSION?m=text | head -n1)"; fi; \
    case "$ver" in go*) ;; *) ver="go$ver" ;; esac; \
    curl -fsSL "https://go.dev/dl/${ver}.linux-${arch}.tar.gz" -o /tmp/go.tgz; \
    tar -C /usr/local -xzf /tmp/go.tgz; \
    rm /tmp/go.tgz /usr/local/go/test /usr/local/go/api -rf; \
    /usr/local/go/bin/go version

ARG WIKI_VERSION=v0.10.0
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    mkdir -p /tmp/wiki && cd /tmp/wiki && \
    curl -fsSL -O "https://github.com/agentic-wiki/wiki/releases/download/${WIKI_VERSION}/wiki_linux_${arch}.tar.gz" && \
    tar xfz "wiki_linux_${arch}.tar.gz" && \
    mv ./wiki /usr/local/bin && \
    cd .. && \
    rm -Rf /tmp/wiki

ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global \
    GOPATH=/home/node/go \
    DENO_INSTALL=/home/node/.deno \
    BUN_INSTALL=/home/node/.bun \
    PATH=/usr/local/share/npm-global/bin:/usr/local/go/bin:/home/node/go/bin:/home/node/.foundry/bin:/home/node/.deno/bin:/home/node/.bun/bin:$PATH \
    DEVCONTAINER=true

RUN mkdir -p /usr/local/share/npm-global /home/node/.codex \
  && chown -R node:node /usr/local/share/npm-global /home/node/.codex

USER node

RUN curl -fsSL https://bun.sh/install | bash
RUN curl -fsSL https://deno.land/install.sh | sh -s -- -y

ARG FOUNDRY_VERSION=1.7.1
# Foundry (forge, cast, anvil, chisel). foundryup keeps a second copy of every
# binary under versions/; hardlinking them together saves ~220 MB.
RUN curl -fsSL https://foundry.paradigm.xyz | bash \
  && /home/node/.foundry/bin/foundryup --install ${FOUNDRY_VERSION} \
  && for f in /home/node/.foundry/versions/*/*; do \
       if [ -f "$f" ]; then ln -f "$f" "/home/node/.foundry/bin/$(basename "$f")"; fi; \
     done

# Last, because it moves fastest: a version bump reuses every layer above.
ARG CODEX_VERSION=latest
RUN npm install -g @openai/codex@${CODEX_VERSION} \
  && npm cache clean --force

RUN forge --version && deno --version && bun --version && go version && codex --version && wiki --version

# The command is exactly what you pass, and defaults to Codex.
# pcodex bind-mounts each project at its host path and passes a matching --workdir.
ENTRYPOINT []
CMD ["codex"]
