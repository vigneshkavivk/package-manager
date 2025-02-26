#!/bin/bash

# Define package names
PACKAGES=("terraform" "awscli" "git" "terragrunt" "opa" "python3" "helm" "kubectl" "rsync")

LOG_FILE="install_log.txt"
exec > >(tee -a "$LOG_FILE") 2>&1

PRECOMMIT_VENV="$HOME/precommit_venv"

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        OS_TYPE="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="macos"
    elif [[ "$OS" =~ ^Windows || "$OS" =~ ^MINGW || "$OS" =~ ^CYGWIN ]]; then
        OS_TYPE="windows"
    else
        OS_TYPE="unknown"
    fi
}

# Install Packages
install_package() {
    if command -v "$1" &>/dev/null; then
        echo "$1 is already installed. Skipping..."
        return
    fi

    case "$OS_TYPE" in
        linux)
            sudo apt-get update -y
            case "$1" in
                terraform)
                    echo "Installing Terraform..."
                    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
                    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
                    sudo apt-get install -y terraform
                    ;;
                awscli)
                    echo "Installing AWS CLI..."
                    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
                    unzip -o awscliv2.zip
                    sudo ./aws/install
                    rm -rf awscliv2.zip aws/
                    ;;
                git)
                    echo "Installing Git..."
                    sudo apt install -y git
                    ;;
                terragrunt)
                    echo "Installing Terragrunt..."
                    curl -LO https://github.com/gruntwork-io/terragrunt/releases/latest/download/terragrunt_linux_amd64
                    sudo install -m 755 terragrunt_linux_amd64 /usr/local/bin/terragrunt
                    ;;
                opa)
                    echo "Installing OPA..."
                    curl -L -o opa https://openpolicyagent.org/downloads/latest/opa_linux_amd64
                    sudo install -m 755 opa /usr/local/bin/opa
                    ;;
                python3)
                    echo "Installing Python..."
                    sudo apt install -y python3 python3-pip python3-venv
                    ;;
                helm)
                    echo "Installing Helm..."
                    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
                    ;;
                kubectl)
                    echo "Installing kubectl..."
                    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
                    sudo install -m 755 kubectl /usr/local/bin/kubectl
                    ;;
                rsync)
                    echo "Installing rsync..."
                    sudo apt install -y rsync
                    ;;
                *)
                    echo "Unknown package: $1"
                    ;;
            esac
            ;;
        macos)
            echo "Installing $1 on macOS..."
            brew install "$1"
            ;;
        windows)
            if ! command -v choco &> /dev/null; then
                echo "Chocolatey not found. Installing..."
                powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
                export PATH="$PATH:/c/ProgramData/chocolatey/bin"
            fi
            echo "Installing $1 on Windows..."
            choco install "$1" -y --no-progress
            ;;
        *)
            echo "Unsupported OS: $OS_TYPE"
            ;;
    esac
}

# Install Pre-commit and Checkov in Separate Virtual Environment
install_precommit_checkov() {
    echo "Setting up separate virtual environment for pre-commit and checkov..."
    if [ ! -d "$PRECOMMIT_VENV" ]; then
        python3 -m venv "$PRECOMMIT_VENV"
    fi
    source "$PRECOMMIT_VENV/bin/activate"
    pip install --upgrade pip
    pip install pre-commit checkov pyyaml
    echo "Pre-commit version: $(pre-commit --version 2>/dev/null || echo 'Unknown')"
    echo "Checkov version: $(checkov --version 2>/dev/null || echo 'Unknown')"
    deactivate
    echo "Pre-commit and Checkov installed in virtual environment at $PRECOMMIT_VENV"
    
    # Create pre-commit config files
    cat > "$HOME/.pre-commit-config.yaml" <<EOL
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: debug-statements
      - id: double-quote-string-fixer
      - id: name-tests-test
      - id: requirements-txt-fixer
      - id: check-docstring-first
      - id: check-added-large-files
        args: ['--maxkb=5000']
      - id: check-docstring-first
      - id: check-json
      - id: detect-private-key
      - id: sort-simple-yaml

  - repo: https://github.com/asottile/setup-cfg-fmt
    rev: v2.7.0
    hooks:
      - id: setup-cfg-fmt

  - repo: https://github.com/asottile/reorder-python-imports
    rev: v3.14.0
    hooks:
      - id: reorder-python-imports
        args: [--py39-plus, --add-import, 'from __future__ import annotations']

  - repo: https://github.com/asottile/add-trailing-comma
    rev: v3.1.0
    hooks:
      - id: add-trailing-comma

  - repo: https://github.com/asottile/pyupgrade
    rev: v3.19.1
    hooks:
      - id: pyupgrade
        args: [--py39-plus]

  - repo: https://github.com/hhatto/autopep8
    rev: v2.3.2
    hooks:
      - id: autopep8

  - repo: https://github.com/PyCQA/flake8
    rev: 7.1.2
    hooks:
      - id: flake8

  - repo: https://github.com/psf/black
    rev: 25.1.0
    hooks:
      - id: black

  - repo: https://github.com/golangci/golangci-lint
    rev: v1.64.5
    hooks:
      - id: golangci-lint
        name: Go linter
        files: \.go$
        types: [file]

  - repo: https://github.com/bridgecrewio/checkov
    rev: 3.2.373  # Use the latest version
    hooks:
    - id: checkov
      name: Checkov Security Scanner
      entry: checkov -d .
      language: python
      pass_filenames: false

  - repo: local  # Use "local" for local hooks
    hooks:
      - id: custom-python-linter
        name: Custom Python Linter
        entry: python3 custom_linter.py
        language: system
        types: [python]
        stages: [pre-commit]
        description: Runs a custom Python linter to enforce coding standards.

      - id: check-large-files
        name: Check for Large Files
        entry: check_large_files.sh
        language: script
        types: [file]
        stages: [pre-commit]
        description: Prevents committing files larger than 1MB.

  - repo: local
    hooks:
      - id: golang-setup
        name: Go Environment Setup
        language: system
        entry: go version
        files: \.go$

  - repo: local
    hooks:
      - id: htmlhint
        name: HTMLHint
        entry: htmlhint
        language: system
        types: [text]
        files: \.html$

  - repo: local
    hooks:
      - id: checkstyle
        name: Checkstyle Java Linter
        entry: checkstyle -c checkstyle.xml
        language: system
        files: \.java$

  - repo: https://github.com/bridgecrewio/checkov
    rev: "3.2.372"  # Use a stable version for production
    hooks:
      - id: checkov
        name: "Checkov Terraform Scan"
        entry: python3 -c "import os; os.system('checkov -d .') or os.system('checkov -f .')"
        language: python
        language: system
        types: [file]
        files: ".*\\.tf$"
        args: ["-v"]
        pass_filenames: false

      - id: checkov
        name: "Checkov YAML Scan"
        entry: python3 -c "import os; os.system('checkov -d .') or os.system('checkov -f .')"
        language: python
        language: system
        types: [file]
        files: ".*\\.ya?ml$"
        args: ["-v"]  # Added verbose flag
        pass_filenames: false

      - id: checkov
        name: "Checkov Helm Chart Scan"
        entry: python3 -c "import os; os.system('checkov -d .') or os.system('checkov -f .')"
        language: python
        language: system
        types: [file]
        files: ".*\\.ya?ml$"  # Ensures it checks YAML inside charts/templates
        args: ["-v"]  # Added verbose flag
        pass_filenames: false
EOL

    cat > "$HOME/.pre-commit-hooks.yaml" <<EOL
       -   id: validate_manifest
    name: validate pre-commit manifest
    description: This validator validates a pre-commit hooks manifest file
    entry: pre-commit validate-manifest
    language: python
    files: ^\.pre-commit-hooks\.yaml$
    stages: [pre-commit, pre-push, manual]
    minimum_pre_commit_version: 3.2.0
EOL
    echo "Pre-commit configuration files created."
}

# Uninstall all packages and clean up
uninstall_packages() {
    echo "Removing all installed packages..."
    for package in "${PACKAGES[@]}"; do
        sudo apt-get remove --purge -y "$package" 2>/dev/null || echo "$package not found"
    done
    sudo rm -rf "$PRECOMMIT_VENV"
    sudo apt-get autoremove -y
    sudo apt-get clean
    echo "All installed packages and dependencies have been removed."
}

# Detect OS
detect_os

# Menu
echo "Select an option:"
echo "1) Install Packages"
echo "2) Remove Installed Packages"
read -p "Enter your choice: " choice

case "$choice" in
    1)
        for package in "${PACKAGES[@]}"; do
            install_package "$package"
        done
        install_precommit_checkov
        show_installed_versions
        ;;
    2)
        uninstall_packages
        ;;
    *)
        echo "Invalid option. Exiting..."
        ;;
esac
