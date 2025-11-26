#!/bin/bash
# Auto-generated package installation script for Parrot OS / Debian-based Linux
# Review before executing!

set -e

echo 'Installing common development tools...'

# Update package list
sudo apt update

# Common CLI tools
PACKAGES=(
    bash
    curl
    git
    htop
    jq
    nodejs
    python3 python3-pip
    ruby-full
    tmux
    tree
    vim
    wget
)

# Install packages
for pkg in "${PACKAGES[@]}"; do
    echo "Installing $pkg..."
    sudo apt install -y $pkg
done

echo 'Package installation complete!'

# NPM global packages
if command -v npm &> /dev/null; then
    echo 'Installing NPM global packages...'
    npm install -g 
fi

# Python packages
if command -v pip3 &> /dev/null; then
    echo 'Installing Python packages...'
    pip3 install -r ../packages/pip3-packages.txt
fi
