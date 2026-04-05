FROM ubuntu:24.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    jq \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (LTS)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code

# Create kamosu directories
RUN mkdir -p /opt/kamosu/scripts /opt/kamosu/templates /opt/kamosu/tools

# Copy VERSION
COPY VERSION /opt/kamosu/VERSION

# Set toolkit version from VERSION file (can be overridden with --build-arg)
ARG KB_TOOLKIT_VERSION
RUN if [ -z "${KB_TOOLKIT_VERSION}" ]; then KB_TOOLKIT_VERSION=$(cat /opt/kamosu/VERSION | tr -d '[:space:]'); fi && \
    echo "export KB_TOOLKIT_VERSION=${KB_TOOLKIT_VERSION}" >> /etc/profile.d/kamosu.sh
ENV KB_TOOLKIT_VERSION=${KB_TOOLKIT_VERSION:-0.1.0}

# Copy claude-base.md
COPY claude-base.md /opt/kamosu/claude-base.md

# Copy templates
COPY templates/ /opt/kamosu/templates/

# Copy scripts and make executable
COPY scripts/ /opt/kamosu/scripts/
RUN chmod +x /opt/kamosu/scripts/*

# Add scripts to PATH
ENV PATH="/opt/kamosu/scripts:${PATH}"

# Working directory for data repositories
WORKDIR /workspace

# Entrypoint handles credential setup, then passes through to command
ENTRYPOINT ["/opt/kamosu/scripts/entrypoint.sh"]
CMD ["bash"]
