# The assistant's sandbox: a small Debian with the tools a model reaches for
# (Python, Node, git, curl, jq, ripgrep, a C compiler) and a headless Chromium
# for pages that need JavaScript (shop prices). It runs as you (your uid) with
# no capabilities, a read-only root, capped memory / CPU / processes, and only
# ~/.local/share/rice/sandbox mounted (at /work). Your home is not visible.
#   docker build -t rice-sandbox sandbox/      (bin/rice-ollama sandbox build)
FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl wget git jq ripgrep fd-find file less unzip xz-utils zip bc procps tree \
        python3 python3-pip python3-venv \
        nodejs npm \
        gcc libc6-dev make \
        chromium-headless-shell fonts-dejavu-core \
    && ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man

# HOME lives in the mounted folder, so `pip install --user` and npm packages persist.
ENV HOME=/work/.home \
    PIP_USER=1 PIP_BREAK_SYSTEM_PACKAGES=1 PIP_DISABLE_PIP_VERSION_CHECK=1 \
    NPM_CONFIG_PREFIX=/work/.home/.npm-global \
    PATH=/work/.home/.local/bin:/work/.home/.npm-global/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PYTHONDONTWRITEBYTECODE=1 LANG=C.UTF-8
WORKDIR /work
CMD ["sleep", "infinity"]
