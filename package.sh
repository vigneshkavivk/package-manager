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
        args: [--py39-plus, --add-import, 'from _future_ import annotations']

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
    rev: 3.2.372  # Use the latest version
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
-   id: shellcheck
    name: shellcheck
    description: Test shell scripts with shellcheck
    entry: shellcheck
    language: python
    types: [shell]
    require_serial: true # shellcheck can detect sourcing this way
-   id: custom-python-linter
    name: Custom Python Linter
    description: Lints Python files for line length, trailing whitespace, and missing docstrings.
    entry: custom_linter.py
    language: system
    types: [python]
-   id: golang-linter
    name: go linter
    description: Checks Go files for formatting and linting issues.
    entry: go run golang_linter.go
    language: system
    types: [go]
-   id: shfmt
    name: Check shell style with shfmt
    language: script
    entry: pre_commit_hooks/shfmt
    types: [shell]
-   id: google-style-java
    name: google style java
    language: system
    entry: google_java_format.sh
    types: [file]
    files: \.java$
-   id: check-html
    name: Check HTML files
    description: Run HTMLHint on staged HTML files
    entry: htmlhint
    language: system
    types: [text]
    files: \.html$

-   id: check-yaml
    name: check yaml
    description: checks yaml files for parseable syntax.
    entry: check-yaml
    language: python
    types: [yaml]
-   id: checkov
    name: Checkov
    description: This hook runs checkov.
    entry: checkov -d .
    language: python
    pass_filenames: false
    always_run: false
    files: \.tf$
    exclude: \.+.terraform\/.*$
    require_serial: true
-   id: check-executables-have-shebangs
    name: check that executables have shebangs
    description: ensures that (non-binary) executables have a shebang.
    entry: check-executables-have-shebangs
    language: python
    types: [text, executable]
    stages: [pre-commit, pre-push, manual]
    minimum_pre_commit_version: 3.2.0
-   id: check-illegal-windows-names
    name: check illegal windows names
    entry: Illegal Windows filenames detected
    language: fail
    files: '(?i)((^|/)(CON|PRN|AUX|NUL|COM[\d¹²³]|LPT[\d¹²³])(\.|/|$)|[<>:\"\\|?\x00-\x1F]|/[^/][\.\s]/|[^/]*[\.\s]$)'
-   id: check-json
    name: check json
    description: checks json files for parseable syntax.
    entry: check-json
    language: python
    types: [json]
-   id: check-shebang-scripts-are-executable
    name: check that scripts with shebangs are executable
    description: ensures that (non-binary) files with a shebang are executable.
    entry: check-shebang-scripts-are-executable
    language: python
    types: [text]
    stages: [pre-commit, pre-push, manual]
    minimum_pre_commit_version: 3.2.0
-   id: pretty-format-json
    name: pretty format json
    description: sets a standard for formatting json files.
    entry: pretty-format-json
    language: python
    types: [json]
-   id: check-merge-conflict
    name: check for merge conflicts
    description: checks for files that contain merge conflict strings.
    entry: check-merge-conflict
    language: python
    types: [text]
-   id: check-symlinks
    name: check for broken symlinks
    description: checks for symlinks which do not point to anything.
    entry: check-symlinks
    language: python
    types: [symlink]
-   id: check-vcs-permalinks
    name: check vcs permalinks
    description: ensures that links to vcs websites are permalinks.
    entry: check-vcs-permalinks
    language: python
    types: [text]
-   id: check-xml
    name: check xml
    description: checks xml files for parseable syntax.
    entry: check-xml
    language: python
    types: [xml]
-   id: check-yaml
    name: check yaml
    description: checks yaml files for parseable syntax.
    entry: check-yaml
    language: python
    types: [yaml]
-   id: debug-statements
    name: debug statements (python)
    description: checks for debugger imports and py37+ breakpoint() calls in python source.
    entry: debug-statement-hook
    language: python
    types: [python]
-   id: destroyed-symlinks
    name: detect destroyed symlinks
    description: detects symlinks which are changed to regular files with a content of a path which that symlink was pointing to.
    entry: destroyed-symlinks
    language: python
    types: [file]
    stages: [pre-commit, pre-push, manual]
-   id: detect-aws-credentials
    name: detect aws credentials
    description: detects your aws credentials from the aws cli credentials file.
    entry: detect-aws-credentials
    language: python
    types: [text]
-   id: end-of-file-fixer
    name: fix end of files
    description: ensures that a file is either empty, or ends with one newline.
    entry: end-of-file-fixer
    language: python
    types: [text]
    stages: [pre-commit, pre-push, manual]
    minimum_pre_commit_version: 3.2.0
-   id: file-contents-sorter
    name: file contents sorter
    description: sorts the lines in specified files (defaults to alphabetical). you must provide list of target files as input in your .pre-commit-config.yaml file.
    entry: file-contents-sorter
    language: python
    files: '^$'
-   id: fix-byte-order-marker
    name: fix utf-8 byte order marker
    description: removes utf-8 byte order marker.
    entry: fix-byte-order-marker
    language: python
    types: [text]
-   id: mixed-line-ending
    name: mixed line ending
    description: replaces or checks mixed line ending.
    entry: mixed-line-ending
    language: python
    types: [text]
-   id: name-tests-test
    name: python tests naming
    description: verifies that test files are named correctly.
    entry: name-tests-test
    language: python
    files: (^|/)tests/.+\.py$
-   id: no-commit-to-branch
    name: "don't commit to branch"
    entry: no-commit-to-branch
    language: python
    pass_filenames: false
    always_run: true
-   id: requirements-txt-fixer
    name: fix requirements.txt
    description: sorts entries in requirements.txt.
    entry: requirements-txt-fixer
    language: python
    files: (requirements|constraints).*\.txt$
-   id: sort-simple-yaml
    name: sort simple yaml files
    description: sorts simple yaml files which consist only of top-level keys, preserving comments and blocks.
    language: python
    entry: sort-simple-yaml
    files: '^$'
-   id: trailing-whitespace
    name: trim trailing whitespace
    description: trims trailing whitespace.
    entry: trailing-whitespace-fixer
    language: python
    types: [text]
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
