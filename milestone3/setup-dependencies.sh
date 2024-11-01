#!/bin/bash

# Install GitHub CLI and authenticate
sudo snap install gh
gh auth login --with-token < /home/ubuntu/ghtoken

# Install Go
wget https://go.dev/dl/go1.23.2.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.23.2.linux-amd64.tar.gz
echo 'export PATH=\$PATH:/usr/local/go/bin' >> ~/.bashrc

# Install Docker stack
sudo snap install docker

# Install build tools
curl -sL https://raw.githubusercontent.com/creationix/nvm/v0.33.8/install.sh -o install_nvm.sh
bash install_nvm.sh
source ~/.bashrc
nvm install --lts
nvm use --lts
