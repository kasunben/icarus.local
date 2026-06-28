FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    git \
    jq \
    ripgrep \
    python3 \
    python3-pip \
    python3-venv \
    ca-certificates \
    gnupg \
    pinentry-tty \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22 LTS via NodeSource
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code + Open Code
RUN npm install -g @anthropic-ai/claude-code opencode-ai

# Python tools
RUN pip3 install --break-system-packages uv ruff black

# Non-root dev user (UID 1001)
RUN useradd -m -u 1001 -s /bin/bash dev

# Ensure .claude dir exists and is writable by dev before volume mount
RUN mkdir -p /home/dev/.claude && chown -R dev:dev /home/dev/.claude

WORKDIR /workspace
USER dev
