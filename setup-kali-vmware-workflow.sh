#!/usr/bin/env bash
set -Eeuo pipefail

#############################################
# Kali VMware Pentest Workflow Setup
# Interactive + curl|bash friendly
#############################################

USER_NAME="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"

HGFS_ROOT="${HGFS_ROOT:-/mnt/hgfs}"
SHARE_NAME="${SHARE_NAME:-KaliShare}"
BASE_SUBDIR="${BASE_SUBDIR:-pentest-data}"
ENABLE_SSH="${ENABLE_SSH:-false}"
SET_ZSH_DEFAULT="${SET_ZSH_DEFAULT:-false}"
INSTALL_EXTRA_GO_TOOLS="${INSTALL_EXTRA_GO_TOOLS:-true}"
INSTALL_PIPX_TOOLS="${INSTALL_PIPX_TOOLS:-true}"
DISABLE_SCREEN_TIMEOUT="${DISABLE_SCREEN_TIMEOUT:-true}"

TMUX_DIR="$HOME_DIR/.tmux"
TPM_DIR="$TMUX_DIR/plugins/tpm"
TMUX_CONF="$HOME_DIR/.tmux.conf"

APT_PACKAGES=(
  tmux
  git
  curl
  wget
  jq
  tree
  unzip
  p7zip-full
  python3
  python3-pip
  python3-venv
  pipx
  golang
  xclip
  zsh
  open-vm-tools
  open-vm-tools-desktop
  seclists
  feroxbuster
  ffuf
  gobuster
  dirsearch
  sqlmap
  nmap
  whatweb
  nikto
  wfuzz
  nuclei
  httpx-toolkit
  subfinder
  amass
  assetfinder
  smbclient
  rlwrap
  netexec
  evil-winrm
  xfconf-query
  hashcat
  john
  openvpn
)

PIPX_TOOLS=(
  "impacket"
)

GO_TOOLS=(
  "github.com/tomnomnom/waybackurls@latest"
  "github.com/lc/gau/v2/cmd/gau@latest"
  "github.com/projectdiscovery/katana/cmd/katana@latest"
  "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
  "github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
)

GIT_REPOS=()

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

run_as_user() {
    sudo -H -u "$USER_NAME" bash -lc "$*"
}

require_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "Run this script with sudo."
        exit 1
    fi
}

is_true() {
    case "${1,,}" in
        true|yes|y|1) return 0 ;;
        false|no|n|0) return 1 ;;
        *) return 1 ;;
    esac
}

prompt_with_default() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="$3"
    local reply=""

    if [[ -r /dev/tty ]]; then
        read -r -p "$prompt_text [$default_value]: " reply < /dev/tty || true
        reply="${reply:-$default_value}"
    else
        reply="$default_value"
    fi

    printf -v "$var_name" '%s' "$reply"
}

prompt_bool() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="$3"
    local reply=""

    if [[ -r /dev/tty ]]; then
        read -r -p "$prompt_text [$default_value]: " reply < /dev/tty || true
        reply="${reply:-$default_value}"
    else
        reply="$default_value"
    fi

    case "${reply,,}" in
        y|yes|true|1) reply="true" ;;
        n|no|false|0) reply="false" ;;
        *) reply="$default_value" ;;
    esac

    printf -v "$var_name" '%s' "$reply"
}

configure_interactive() {
    echo
    echo "Kali VMware Pentest Workflow Setup"
    echo "Press Enter to accept defaults."
    echo

    prompt_with_default HGFS_ROOT "VMware shared folders root" "$HGFS_ROOT"
    prompt_with_default SHARE_NAME "VMware shared folder name" "$SHARE_NAME"
    prompt_with_default BASE_SUBDIR "Workspace subdirectory" "$BASE_SUBDIR"

    prompt_bool ENABLE_SSH "Enable SSH server" "$ENABLE_SSH"
    prompt_bool SET_ZSH_DEFAULT "Set Zsh as default shell" "$SET_ZSH_DEFAULT"
    prompt_bool INSTALL_EXTRA_GO_TOOLS "Install extra Go tools" "$INSTALL_EXTRA_GO_TOOLS"
    prompt_bool INSTALL_PIPX_TOOLS "Install pipx tools" "$INSTALL_PIPX_TOOLS"
    prompt_bool DISABLE_SCREEN_TIMEOUT "Disable screen standby and lock" "$DISABLE_SCREEN_TIMEOUT"

    echo
}

normalize_bool() {
    case "${1,,}" in
        true|yes|y|1) echo "true" ;;
        false|no|n|0) echo "false" ;;
        *) echo "$2" ;;
    esac
}

resolve_paths() {
    local fallback_base="$HOME_DIR/$BASE_SUBDIR"

    if [[ -d "$HGFS_ROOT/$SHARE_NAME" ]]; then
        BASE_DIR="$HGFS_ROOT/$SHARE_NAME/$BASE_SUBDIR"
        USING_SHARED="true"
    elif [[ -d "$HGFS_ROOT" ]] && mountpoint -q "$HGFS_ROOT"; then
        local first_share
        first_share="$(find "$HGFS_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1 || true)"
        if [[ -n "${first_share:-}" ]]; then
            BASE_DIR="$first_share/$BASE_SUBDIR"
            USING_SHARED="true"
        else
            BASE_DIR="$fallback_base"
            USING_SHARED="false"
        fi
    else
        BASE_DIR="$fallback_base"
        USING_SHARED="false"
    fi

    TOOLS_DIR="$BASE_DIR/tools"
    WORDLIST_DIR="$BASE_DIR/wordlists"
    ASSESSMENTS_DIR="$BASE_DIR/assessments"
    LOGS_DIR="$BASE_DIR/tmux-logs"
    NOTES_DIR="$BASE_DIR/notes"
    VPN_DIR="$BASE_DIR/vpn"
    LOOT_DIR="$BASE_DIR/loot"
    SCREENSHOTS_DIR="$BASE_DIR/screenshots"

    GIT_REPOS=(
      "https://github.com/peass-ng/PEASS-ng.git|$TOOLS_DIR/PEASS-ng"
      "https://github.com/projectdiscovery/nuclei-templates.git|$TOOLS_DIR/nuclei-templates"
      "https://github.com/danielmiessler/SecLists.git|$TOOLS_DIR/SecLists-git"
    )
}

show_configuration() {
    echo "Configuration:"
    echo "  User:                    $USER_NAME"
    echo "  Home:                    $HOME_DIR"
    echo "  VMware shared root:      $HGFS_ROOT"
    echo "  VMware share name:       $SHARE_NAME"
    echo "  Base subdirectory:       $BASE_SUBDIR"
    echo "  Using shared folder:     $USING_SHARED"
    echo "  Base directory:          $BASE_DIR"
    echo "  Enable SSH:              $ENABLE_SSH"
    echo "  Set Zsh default shell:   $SET_ZSH_DEFAULT"
    echo "  Install extra Go tools:  $INSTALL_EXTRA_GO_TOOLS"
    echo "  Install pipx tools:      $INSTALL_PIPX_TOOLS"
    echo "  Disable standby/lock:    $DISABLE_SCREEN_TIMEOUT"
    echo
}

ensure_packages() {
    log "Updating package lists and installing packages"
    apt update
    apt install -y "${APT_PACKAGES[@]}"
}

ensure_vmware_tools() {
    log "Ensuring VMware tools are enabled"
    systemctl enable open-vm-tools || true
    systemctl restart open-vm-tools || true
}

ensure_dirs() {
    log "Creating directory structure"
    mkdir -p \
      "$BASE_DIR" \
      "$TOOLS_DIR" \
      "$WORDLIST_DIR" \
      "$ASSESSMENTS_DIR" \
      "$LOGS_DIR" \
      "$NOTES_DIR" \
      "$VPN_DIR" \
      "$LOOT_DIR" \
      "$SCREENSHOTS_DIR" \
      "$TMUX_DIR/plugins"

    chown -R "$USER_NAME:$USER_NAME" "$BASE_DIR"
    chown -R "$USER_NAME:$USER_NAME" "$TMUX_DIR"
}

install_tpm() {
    if [[ -d "$TPM_DIR/.git" ]]; then
        log "Updating tmux plugin manager"
        run_as_user "git -C '$TPM_DIR' pull --ff-only || true"
    else
        log "Installing tmux plugin manager"
        run_as_user "git clone https://github.com/tmux-plugins/tpm '$TPM_DIR'"
    fi
}

backup_tmux_conf() {
    if [[ -f "$TMUX_CONF" ]]; then
        log "Backing up existing tmux configuration"
        cp "$TMUX_CONF" "${TMUX_CONF}.bak-$DATE_TAG"
        chown "$USER_NAME:$USER_NAME" "${TMUX_CONF}.bak-$DATE_TAG"
    fi
}

write_tmux_conf() {
    log "Writing tmux configuration"
    cat > "$TMUX_CONF" <<EOF
# Prefix
set -g prefix C-b
unbind C-b
bind C-b send-prefix

# General usability
set -g mouse on
setw -g mode-keys vi
set -g base-index 1
setw -g pane-base-index 1
set -g history-limit 50000
set -g renumber-windows on

# Better splitting
bind | split-window -h
bind - split-window -v

# Reload config
bind r source-file ~/.tmux.conf \; display-message "tmux.conf reloaded"

# Plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-logging'
set -g @plugin 'tmux-plugins/tmux-sessionist'
set -g @plugin 'tmux-plugins/tmux-resurrect'

# Logging config
set -g @logging-path '$LOGS_DIR'
set -g @screen-capture-path '$LOGS_DIR'
set -g @save-complete-history 'on'

# Resurrect
set -g @resurrect-dir '$HOME_DIR/.tmux/resurrect'

# TPM init
run '~/.tmux/plugins/tpm/tpm'
EOF

    chown "$USER_NAME:$USER_NAME" "$TMUX_CONF"
}

setup_wordlists() {
    log "Linking system wordlists into the workspace"
    if [[ -d /usr/share/seclists ]]; then
        run_as_user "ln -sfn /usr/share/seclists '$WORDLIST_DIR/seclists'"
    fi
}

install_pipx_tools() {
    if ! is_true "$INSTALL_PIPX_TOOLS"; then
        return
    fi

    log "Installing pipx tools"
    run_as_user "python3 -m pip install --user -U pip pipx"
    run_as_user "python3 -m pipx ensurepath"

    for tool in "${PIPX_TOOLS[@]}"; do
        run_as_user "pipx install --force '$tool' || true"
    done
}

install_go_tools() {
    if ! is_true "$INSTALL_EXTRA_GO_TOOLS"; then
        return
    fi

    log "Installing Go tools"
    for tool in "${GO_TOOLS[@]}"; do
        run_as_user "GOPATH='$HOME_DIR/go' PATH='$HOME_DIR/go/bin:\$PATH' go install '$tool'"
    done
}

clone_git_repos() {
    log "Cloning or updating repositories"
    for entry in "${GIT_REPOS[@]}"; do
        local repo dest
        repo="${entry%%|*}"
        dest="${entry##*|}"

        if [[ -d "$dest/.git" ]]; then
            run_as_user "git -C '$dest' pull --ff-only || true"
        else
            run_as_user "git clone '$repo' '$dest'"
        fi
    done
}

write_assessment_helper() {
    log "Creating assessment helper"
    cat > /usr/local/bin/start-assessment <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail

CLIENT_NAME="\${1:-client}"
DATE_TAG="\$(date +%F)"
SAFE_NAME="\${CLIENT_NAME// /_}"
SESSION_NAME="\${SAFE_NAME}-\${DATE_TAG}"
BASE_DIR="$ASSESSMENTS_DIR/\$CLIENT_NAME/\$DATE_TAG"

mkdir -p "\$BASE_DIR"/{notes,loot,scans,screenshots,logs,recon,web,infra,evidence,reporting}

LOGBOOK="\$BASE_DIR/notes/logbook.md"
SCOPEFILE="\$BASE_DIR/notes/scope.md"

[[ -f "\$LOGBOOK" ]] || cat > "\$LOGBOOK" <<'LOGEOF'
# Logbook

## Objective
-

## Activities performed
-

## Exploitation attempts
-

## Notes
-
LOGEOF

[[ -f "\$SCOPEFILE" ]] || cat > "\$SCOPEFILE" <<'SCOPEEOF'
# Scope

## Client
-

## Objectives
-

## In scope
-

## Out of scope
-

## Notes
-
SCOPEEOF

if tmux has-session -t "\$SESSION_NAME" 2>/dev/null; then
    exec tmux attach -t "\$SESSION_NAME"
fi

tmux new-session -d -s "\$SESSION_NAME" -n main
tmux send-keys -t "\$SESSION_NAME:main" "cd '\$BASE_DIR'" C-m

tmux split-window -h -t "\$SESSION_NAME:main"
tmux send-keys -t "\$SESSION_NAME:main.2" "cd '\$BASE_DIR/scans'" C-m

tmux split-window -v -t "\$SESSION_NAME:main.1"
tmux send-keys -t "\$SESSION_NAME:main.3" "cd '\$BASE_DIR/notes'" C-m

tmux select-pane -t "\$SESSION_NAME:main.1"
tmux attach -t "\$SESSION_NAME"
EOF

    chmod +x /usr/local/bin/start-assessment
}

write_shell_aliases() {
    log "Adding shell aliases"
    local zshrc="$HOME_DIR/.zshrc"
    run_as_user "touch '$zshrc'"

    run_as_user "grep -q 'export PATH=\"\$HOME/go/bin:\$HOME/.local/bin:\$PATH\"' '$zshrc' || echo 'export PATH=\"\$HOME/go/bin:\$HOME/.local/bin:\$PATH\"' >> '$zshrc'"
    run_as_user "grep -q \"alias ta='tmux attach -t'\" '$zshrc' || echo \"alias ta='tmux attach -t'\" >> '$zshrc'"
    run_as_user "grep -q \"alias tls='tmux ls'\" '$zshrc' || echo \"alias tls='tmux ls'\" >> '$zshrc'"
    run_as_user "grep -q \"alias tnew='tmux new -s'\" '$zshrc' || echo \"alias tnew='tmux new -s'\" >> '$zshrc'"
    run_as_user "grep -q \"alias assess='start-assessment'\" '$zshrc' || echo \"alias assess='start-assessment'\" >> '$zshrc'"
    run_as_user "grep -q \"alias pentestbase='cd $BASE_DIR'\" '$zshrc' || echo \"alias pentestbase='cd $BASE_DIR'\" >> '$zshrc'"
}

write_workspace_readme() {
    log "Writing workspace setup notes"
    cat > "$BASE_DIR/README-SETUP.txt" <<EOF
Kali pentest workflow setup

Base directory:
$BASE_DIR

Tmux logs:
$LOGS_DIR

Assessment helper:
assess <client-name>

Tmux plugin installation:
1. Start tmux
2. Press Ctrl+b
3. Press Shift+i

Tmux logging:
- Start or stop logging: Ctrl+b then Shift+p
- Retroactive pane save: Ctrl+b then Alt+Shift+p
- Pane capture: Ctrl+b then Alt+p
EOF
    chown "$USER_NAME:$USER_NAME" "$BASE_DIR/README-SETUP.txt"
}

disable_screen_timeout() {
    if ! is_true "$DISABLE_SCREEN_TIMEOUT"; then
        return
    fi

    log "Disabling screen timeout and lock"

    run_as_user "gsettings set org.gnome.desktop.session idle-delay 0 || true"
    run_as_user "gsettings set org.gnome.desktop.screensaver lock-enabled false || true"
    run_as_user "gsettings set org.gnome.desktop.screensaver idle-activation-enabled false || true"

    run_as_user "xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/inactivity-on-ac -s 0 || true"
    run_as_user "xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/blank-on-ac -s 0 || true"
    run_as_user "xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/dpms-enabled -s false || true"
    run_as_user "xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/presentation-mode -s true || true"
}

setup_ssh() {
    if ! is_true "$ENABLE_SSH"; then
        return
    fi

    log "Enabling SSH server"
    apt install -y openssh-server
    systemctl enable ssh
    systemctl restart ssh
}

set_default_shell() {
    if ! is_true "$SET_ZSH_DEFAULT"; then
        return
    fi

    log "Setting Zsh as the default shell"
    chsh -s /usr/bin/zsh "$USER_NAME" || true
}

cleanup() {
    log "Cleaning up package cache"
    apt autoremove -y
    apt autoclean
}

print_summary() {
    cat <<EOF

Setup complete.

Shared folder in use: $USING_SHARED
Base directory:       $BASE_DIR
Assessments:          $ASSESSMENTS_DIR
Tmux logs:            $LOGS_DIR
Tools:                $TOOLS_DIR
Wordlists:            $WORDLIST_DIR

Next steps:
1. Open a new shell or run:
   source ~/.zshrc

2. Start tmux:
   tmux new -s setup

3. Install tmux plugins:
   Ctrl+b then Shift+i

4. Start an assessment:
   assess example-client

5. Optionally run PimpMyKali afterward for browser and desktop customizations.

EOF
}

main() {
    require_root
    configure_interactive
    resolve_paths
    show_configuration
    ensure_packages
    ensure_vmware_tools
    ensure_dirs
    install_tpm
    backup_tmux_conf
    write_tmux_conf
    setup_wordlists
    install_pipx_tools
    install_go_tools
    clone_git_repos
    write_assessment_helper
    write_shell_aliases
    write_workspace_readme
    disable_screen_timeout
    setup_ssh
    set_default_shell
    cleanup
    print_summary
}

main "$@"
