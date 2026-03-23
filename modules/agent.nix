{ config, pkgs, lib, ... }:

{
  # --- Tinker User ---
  users.users.tinker = {
    isNormalUser = true;
    home = "/srv/tinker";
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      (builtins.readFile ../keys/deploy.pub)
    ];
  };

  programs.zsh.enable = true;

  # Claude Code has an unfree license
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
  ];

  # --- System Packages ---
  environment.systemPackages = with pkgs; [
    claude-code
    tmux
    zsh
    git
    jq
    curl
    ripgrep
    fd
    chromium
    nodejs_22
    bun
  ];

  # --- Directory Structure & Git Init ---
  system.activationScripts.tinkerDirs = lib.stringAfter [ "users" ] ''
    install -d -o tinker -g users /srv/tinker/projects
    install -d -o tinker -g users /srv/tinker/docs
    install -d -o tinker -g users /srv/tinker/modules/apps
    install -d -o tinker -g users /srv/tinker/state
    install -d -o tinker -g users /srv/tinker/prompts

    # Initialize git repo if not exists
    if [ ! -d /srv/tinker/.git ]; then
      cd /srv/tinker
      ${pkgs.git}/bin/git init
      ${pkgs.git}/bin/git config user.name "tinker"
      ${pkgs.git}/bin/git config user.email "tinker@tinker.builders"
      chown -R tinker:users /srv/tinker/.git
    fi

    # Write Claude Code settings (only if file doesn't exist)
    install -d -o tinker -g users /srv/tinker/.claude
    if [ ! -f /srv/tinker/.claude/settings.json ]; then
      cat > /srv/tinker/.claude/settings.json << 'EOF'
{"enabledPlugins":{"discord@claude-plugins-official":true}}
EOF
      chown tinker:users /srv/tinker/.claude/settings.json
    fi
  '';

  # --- Tmux Auto-Attach on SSH Login ---
  system.activationScripts.tinkerZshrc = lib.stringAfter [ "users" "tinkerDirs" ] ''
    # Install tmux auto-attach zshrc for tinker user
    ZSHRC="/srv/tinker/.zshrc"
    cat > "$ZSHRC" << 'ZEOF'
export PATH="/srv/tinker/scripts:$PATH"

# Source secrets if available
if [ -f /run/secrets/tinker.env ]; then
  set -a; source /run/secrets/tinker.env; set +a
fi

# Auto-attach to tmux session on SSH login
if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then
  tmux new-session -A -s tinker
fi
ZEOF
    chown tinker:users "$ZSHRC"
    chmod 644 "$ZSHRC"
  '';

  # --- Sudoers: Passwordless nixos-rebuild + git in /etc/nixos ---
  security.sudo.extraRules = [{
    users = [ "tinker" ];
    commands = [
      { command = "/run/current-system/sw/bin/nixos-rebuild"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/git"; options = [ "NOPASSWD" ]; }
    ];
  }];
}
