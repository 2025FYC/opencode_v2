#!/usr/bin/env bash
set -euo pipefail

# OpenCode Local Build Script
# This script builds OpenCode from the current local directory
# Requirements: Git, curl, sudo access

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install system dependencies
install_system_deps() {
    log_step "Installing system dependencies..."

    if command_exists apt-get; then
        sudo apt-get update
        sudo apt-get install -y unzip curl wget build-essential
    elif command_exists yum; then
        sudo yum install -y unzip curl wget gcc gcc-c++ make
    elif command_exists brew; then
        brew install unzip curl wget
    else
        log_error "Package manager not supported. Please install unzip, curl, and wget manually."
        exit 1
    fi
}

# Install Bun
install_bun() {
    log_step "Installing Bun JavaScript runtime..."

    if command_exists bun; then
        log_info "Bun already installed: $(bun --version)"
        return
    fi

    curl -fsSL https://bun.sh/install | bash

    # Add Bun to PATH for this session
    export PATH="$HOME/.bun/bin:$PATH"

    if command_exists bun; then
        log_info "Bun installed successfully: $(bun --version)"
    else
        log_error "Failed to install Bun"
        exit 1
    fi
}

# Install Go
install_go() {
    log_step "Installing Go 1.24..."

    if command_exists go; then
        GO_VERSION=$(go version | awk '{print $3}')
        if [[ "$GO_VERSION" == "go1.24"* ]]; then
            log_info "Go 1.24 already installed: $GO_VERSION"
            return
        else
            log_warn "Go version $GO_VERSION found, but we need Go 1.24"
        fi
    fi

    # Determine architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "aarch64" ]]; then
        ARCH="arm64"
    elif [[ "$ARCH" == "x86_64" ]]; then
        ARCH="amd64"
    else
        log_error "Unsupported architecture: $ARCH"
        exit 1
    fi

    # Download and install Go
    GO_VERSION="1.24rc1"
    GO_TARBALL="go${GO_VERSION}.linux-${ARCH}.tar.gz"

    log_info "Downloading Go ${GO_VERSION} for ${ARCH}..."
    wget "https://go.dev/dl/${GO_TARBALL}" -O "/tmp/${GO_TARBALL}"

    # Remove existing Go installation and install new one
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"

    # Add Go to PATH for this session
    export PATH="/usr/local/go/bin:$PATH"

    # Clean up
    rm "/tmp/${GO_TARBALL}"

    if command_exists go; then
        log_info "Go installed successfully: $(go version)"
    else
        log_error "Failed to install Go"
        exit 1
    fi
}

# Setup environment variables
setup_environment() {
    log_step "Setting up environment..."

    # Ensure PATH includes Bun and Go
    export PATH="/usr/local/go/bin:$HOME/.bun/bin:$PATH"

    # Verify installations
    if ! command_exists bun; then
        log_error "Bun not found in PATH"
        exit 1
    fi

    if ! command_exists go; then
        log_error "Go not found in PATH"
        exit 1
    fi

    log_info "Environment setup complete"
    log_info "Bun version: $(bun --version)"
    log_info "Go version: $(go version | awk '{print $3}')"
}

# Verify we're in the right directory
verify_directory() {
    log_step "Verifying current directory..."

    if [[ ! -f "package.json" ]]; then
        log_error "package.json not found. Are you in the opencode root directory?"
        exit 1
    fi

    if [[ ! -d "packages/opencode" ]]; then
        log_error "packages/opencode directory not found. Are you in the opencode root directory?"
        exit 1
    fi

    if ! grep -q '"name": "opencode"' package.json; then
        log_error "This doesn't appear to be the opencode project directory"
        exit 1
    fi

    log_info "Directory verification passed"
}

# Clean previous builds
clean_build() {
    log_step "Cleaning previous builds..."

    if [[ -d "packages/opencode/dist" ]]; then
        rm -rf packages/opencode/dist
        log_info "Removed previous build artifacts"
    fi

    if [[ -d "node_modules" ]]; then
        rm -rf node_modules
        log_info "Removed node_modules"
    fi
}

# Install dependencies
install_dependencies() {
    log_step "Installing project dependencies..."

    bun install
    log_info "Dependencies installed successfully"
}

# Build OpenCode
build_opencode() {
    log_step "Building OpenCode..."

    # First build the plugin dependency
    log_info "Building plugin dependency..."
    cd packages/plugin
    bun run build

    # Then build opencode
    log_info "Building main opencode package..."
    cd ../opencode
    bun run build
    cd ../..

    log_info "Build completed successfully"
}

# Test the built binary
test_binary() {
    log_step "Testing built binary..."

    if [[ -f "packages/opencode/dist/opencode-linux-x64/bin/opencode" ]]; then
        log_info "Testing Linux x64 binary..."
        packages/opencode/dist/opencode-linux-x64/bin/opencode --version
        log_info "Binary test successful"
    else
        log_error "Built binary not found"
        exit 1
    fi
}

# Install binary to system
install_binary() {
    log_step "Installing OpenCode binary..."

    INSTALL_DIR="$HOME/.local/bin"
    mkdir -p "$INSTALL_DIR"

    # Copy the appropriate binary for current architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        BINARY_PATH="packages/opencode/dist/opencode-linux-x64/bin/opencode"
    elif [[ "$ARCH" == "aarch64" ]]; then
        BINARY_PATH="packages/opencode/dist/opencode-linux-arm64/bin/opencode"
    else
        log_error "Unsupported architecture for installation: $ARCH"
        exit 1
    fi

    if [[ -f "$BINARY_PATH" ]]; then
        cp "$BINARY_PATH" "$INSTALL_DIR/opencode"
        chmod +x "$INSTALL_DIR/opencode"
        log_info "OpenCode installed to $INSTALL_DIR/opencode"

        # Add to PATH if not already there
        if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
            echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$HOME/.bashrc"
            log_info "Added $INSTALL_DIR to PATH in ~/.bashrc"
            log_warn "Please run 'source ~/.bashrc' or restart your shell"
        fi
    else
        log_error "Binary not found: $BINARY_PATH"
        exit 1
    fi
}

# Update PATH in shell config files
update_shell_config() {
    log_step "Updating shell configuration..."

    # Add Bun and Go to various shell config files
    local configs=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile")
    local go_path_line="export PATH=\"/usr/local/go/bin:\$PATH\""
    local bun_path_line="export PATH=\"\$HOME/.bun/bin:\$PATH\""

    for config in "${configs[@]}"; do
        if [[ -f "$config" ]]; then
            # Add Go to PATH if not already there
            if ! grep -q "/usr/local/go/bin" "$config"; then
                echo "" >> "$config"
                echo "# Go" >> "$config"
                echo "$go_path_line" >> "$config"
                log_info "Added Go to PATH in $config"
            fi

            # Bun should already be added by its installer
            if ! grep -q ".bun/bin" "$config" && [[ "$config" != "$HOME/.bashrc" ]]; then
                echo "" >> "$config"
                echo "# Bun" >> "$config"
                echo "$bun_path_line" >> "$config"
                log_info "Added Bun to PATH in $config"
            fi
        fi
    done
}

# Show current directory and git status
show_status() {
    log_step "Current project status..."

    log_info "Working directory: $(pwd)"

    if [[ -d ".git" ]]; then
        log_info "Git status:"
        git status --short 2>/dev/null | head -5 || true
        log_info "Current branch: $(git branch --show-current 2>/dev/null || echo 'unknown')"
        log_info "Latest commit: $(git log --oneline -1 2>/dev/null || echo 'unknown')"
    else
        log_info "Not a git repository"
    fi
}

# Main build process
main() {
    log_info "Starting OpenCode local build..."
    log_info "Building from current directory: $(pwd)"

    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        log_error "Don't run this script as root"
        exit 1
    fi

    # Ask for sudo access upfront
    sudo -v || {
        log_error "This script requires sudo access"
        exit 1
    }

    # Build steps
    show_status
    verify_directory
    install_system_deps
    install_bun
    install_go
    setup_environment
    clean_build
    install_dependencies
    build_opencode
    test_binary

    # Ask if user wants to install the binary
    read -p "Do you want to install OpenCode to ~/.local/bin? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        install_binary
        update_shell_config
    else
        log_info "Skipping installation. Binary is available at:"
        log_info "  $(pwd)/packages/opencode/dist/opencode-linux-x64/bin/opencode"
    fi

    log_info "Local build completed successfully!"
    log_info "Available binaries:"
    ls -la packages/opencode/dist/*/bin/opencode 2>/dev/null || true

    echo
    log_info "To use OpenCode:"
    log_info "  1. Add the binary to your PATH, or"
    log_info "  2. Run directly: ./packages/opencode/dist/opencode-linux-x64/bin/opencode"
    log_info "  3. Or if installed: opencode --help"

    echo
    log_info "Your local modifications will be included in the build!"
}

# Run main function
main "$@"