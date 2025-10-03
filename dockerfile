FROM ubuntu:22.04

# Install necessary dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /usr/local/bin
RUN mkdir -p /root/.local/share/opencode
RUN mkdir -p /workdir

# Copy the opencode binary
COPY packages/opencode/dist/opencode-linux-x64/bin/opencode /usr/local/bin/opencode

# Make the binary executable and add to PATH
RUN chmod +x /usr/local/bin/opencode
ENV PATH="/usr/local/bin:${PATH}"

# Set working directory
WORKDIR /workdir

# Expose port
EXPOSE 4096

# Default command
CMD ["opencode", "serve", "--hostname", "0.0.0.0", "--port", "4096"]