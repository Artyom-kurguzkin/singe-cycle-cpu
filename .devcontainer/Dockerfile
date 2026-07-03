FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    curl \
    git \
    sudo \
    make \
    ghdl \
    && rm -rf /var/lib/apt/lists/*

# Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Non-root user (devcontainer convention)
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

USER $USERNAME

# Claude Code CLI installed as vscode user so auto-update can write to the prefix
RUN mkdir -p /home/$USERNAME/.npm-global \
    && npm config set prefix /home/$USERNAME/.npm-global \
    && npm install -g @anthropic-ai/claude-code

ENV PATH="/home/${USERNAME}/.npm-global/bin:${PATH}"
WORKDIR /workspace
