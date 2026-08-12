#!/bin/bash

# Detect the platform so the same script works on macOS and Linux
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Darwin) PLATFORM="macos" ;;
  Linux)  PLATFORM="linux" ;;
  *) echo "Unsupported operating system: $OS"; exit 1 ;;
esac

echo "Detected platform: ${PLATFORM} (${ARCH})"

# Define and sort all required packages (Debian/Ubuntu names)
required_packages_linux=(
  build-essential
  ca-certificates
  curl
  fzf
  gnome-control-center
  jq
  libbz2-dev
  libffi-dev
  liblzma-dev
  libncursesw5-dev
  libreadline-dev
  libsqlite3-dev
  libssl-dev
  libxmlsec1-dev
  libxml2-dev
  ninja-build
  openjdk-11-jdk
  openvpn
  python3-dev
  tk-dev
  tmux
  tree
  unzip
  wget
  xclip
  xz-utils
  zlib1g-dev
  zsh
)

# Homebrew equivalents. Deliberately omitted:
#   build-essential, python3-dev -> Xcode Command Line Tools
#   ca-certificates, unzip       -> shipped with macOS
#   gnome-control-center         -> Linux desktop only
#   xclip                        -> macOS has pbcopy/pbpaste
#   zsh                          -> macOS already ships zsh as the default shell
required_packages_macos=(
  bzip2
  coreutils
  curl
  fzf
  jq
  libffi
  libxml2
  libxmlsec1
  ninja
  openjdk@11
  openssl@3
  openvpn
  readline
  sqlite
  tcl-tk
  tmux
  tree
  xz
  zlib
)

# Download a URL to a local path using whichever fetcher is available
download() {
  url="$1"
  dest="$2"
  if command -v curl &> /dev/null; then
    curl -fsSL "$url" -o "$dest"
  elif command -v wget &> /dev/null; then
    wget -q "$url" -O "$dest"
  else
    echo "Neither curl nor wget is available; cannot download $url"
    return 1
  fi
}

install_packages_linux() {
  if ! command -v apt &> /dev/null; then
    echo "The Linux path of this script expects apt (Debian/Ubuntu)."
    echo "Install the equivalents of these packages with your package manager, then rerun:"
    printf '  %s\n' "${required_packages_linux[@]}"
    return 1
  fi

  echo "Updating package list and ensuring all utilities are installed or at their latest version..."
  sudo apt update

  # Install or update all required packages
  sudo apt install -y "${required_packages_linux[@]}"
}

install_packages_macos() {
  # The compiler toolchain and system headers come from the Command Line Tools
  if ! xcode-select -p &> /dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "Finish the Command Line Tools installer, then rerun this script."
    exit 0
  fi

  if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
      echo "Homebrew installation failed. See https://brew.sh for manual instructions."
      return 1
    }
  fi

  # Homebrew lives in /opt/homebrew on Apple Silicon and /usr/local on Intel
  if ! command -v brew &> /dev/null; then
    for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      if [ -x "$brew_bin" ]; then
        eval "$("$brew_bin" shellenv)"
        break
      fi
    done
  fi

  if ! command -v brew &> /dev/null; then
    echo "Homebrew is not on PATH; cannot install packages."
    return 1
  fi

  echo "Updating Homebrew and ensuring all utilities are installed or at their latest version..."
  brew update
  brew install "${required_packages_macos[@]}" ||
    echo "⚠️ Some formulae could not be installed. Continuing."
  brew upgrade "${required_packages_macos[@]}" ||
    echo "⚠️ Some formulae could not be upgraded. Continuing."
}

if [ "$PLATFORM" = "macos" ]; then
  install_packages_macos
else
  install_packages_linux
fi

# Special handling for GitHub CLI (gh)
if ! command -v gh &> /dev/null; then
    if [ "$PLATFORM" = "macos" ]; then
        echo "Installing GitHub CLI (gh) with Homebrew..."
        brew install gh
    else
        echo "Installing GitHub CLI (gh) from official repository..."
        sudo mkdir -p -m 755 /etc/apt/keyrings
        out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg
        cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
        sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update
        sudo apt install gh -y
    fi
else
    echo "GitHub CLI (gh) is already installed: $(gh --version | head -n 1)"
fi

# Install Just if not already installed
if ! command -v just &> /dev/null; then
  echo "Installing Just..."

  if [ "$PLATFORM" = "macos" ] && command -v brew &> /dev/null; then
    brew install just
  fi

  # Fall back to the prebuilt binary for the current OS/architecture
  if ! command -v just &> /dev/null; then
    JUST_VERSION="1.19.0"

    case "$ARCH" in
      x86_64|amd64) just_arch="x86_64" ;;
      aarch64|arm64) just_arch="aarch64" ;;
      *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
    esac

    if [ "$PLATFORM" = "macos" ]; then
      just_target="${just_arch}-apple-darwin"
    else
      just_target="${just_arch}-unknown-linux-musl"
    fi

    JUST_DOWNLOAD_URL="https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-${just_target}.tar.gz"

    just_tmp=$(mktemp -d)
    if download "$JUST_DOWNLOAD_URL" "${just_tmp}/just.tar.gz" &&
       tar -xzf "${just_tmp}/just.tar.gz" -C "$just_tmp" just; then
      sudo mkdir -p /usr/local/bin
      sudo mv "${just_tmp}/just" /usr/local/bin/
      export PATH="/usr/local/bin:$PATH"
      echo "Just installed successfully."
    else
      echo "Failed to install Just from ${JUST_DOWNLOAD_URL}"
      echo "Install it manually: https://just.systems/man/en/packages.html"
      rm -rf "$just_tmp"
      exit 1
    fi
    rm -rf "$just_tmp"
  else
    echo "Just installed successfully."
  fi
fi

# Check if user.name and user.email are already set
user_name=$(git config --get user.name)
user_email=$(git config --get user.email)

if [ -z "$user_name" ]; then
    read -r -p "Enter your GitHub full name: " user_name
    git config --global user.name "$user_name"
fi

if [ -z "$user_email" ]; then
    read -r -p "Enter your email address: " user_email
    git config --global user.email "$user_email"
fi

# Check if the default shell is Zsh
zsh_path="$(command -v zsh)"
if [ "$SHELL" = "$zsh_path" ]; then
  echo "Default shell is already Zsh."
elif [ -z "$zsh_path" ]; then
  echo "Zsh is not installed; skipping the default shell change."
else
  echo "Default shell is not Zsh. Attempting to change shell to Zsh..."
  # chsh only accepts shells listed in /etc/shells (enforced on both macOS and Linux)
  if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
    echo "$zsh_path" | sudo tee -a /etc/shells > /dev/null
  fi
  if sudo chsh -s "$zsh_path" "$USER"; then
    touch ${HOME}/.zshrc
    echo "Shell changed to Zsh. Please re-login and rerun this script."
    echo "Or run"
    echo "cd ${HOME}/dotfiles && just"
    echo "Exiting..."
    sleep 3
    exit 0
  else
    echo "Failed to change the shell. Please have someone with root access run 'chsh -s $zsh_path $USER'."
  fi
fi

# Run just to execute the default recipe
just
