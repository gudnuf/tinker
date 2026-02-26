{ config, pkgs, lib, ... }:

let
  # Project source, filtered to exclude .git, editor backups, etc.
  # Only documents/, skills/, and scripts/ are actually copied to the VPS.
  projectSrc = lib.cleanSource ../.;

  # Script to sync Tinker documents into the OpenClaw workspace.
  # Called via ExecStartPost — must run AFTER openclaw creates/regenerates
  # workspace defaults on startup (activation scripts run too early).
  workspaceSyncScript = pkgs.writeShellScript "tinker-workspace-sync" ''
    WORKSPACE="/var/lib/openclaw/.openclaw/workspace"
    DEST="/home/openclaw/projects/tinker"

    # Wait for openclaw to finish initializing and create workspace files
    for i in $(seq 1 30); do
      if [ -f "$WORKSPACE/AGENTS.md" ]; then
        break
      fi
      sleep 1
    done
    # Extra delay to ensure openclaw has finished writing defaults
    sleep 5

    for doc in AGENTS.md SOUL.md TOOLS.md; do
      if [ -f "$DEST/documents/$doc" ]; then
        cp "$DEST/documents/$doc" "$WORKSPACE/$doc"
        chmod 600 "$WORKSPACE/$doc"
      fi
    done
    # Remove BOOTSTRAP.md — it triggers the onboarding flow instead of
    # using our custom agent behavior.
    rm -f "$WORKSPACE/BOOTSTRAP.md"
    chown -R openclaw:openclaw "$WORKSPACE"
  '';
in
{
  # Copy project content (agent docs, skills, scripts) to the openclaw
  # working directory on every deploy. This runs as an activation script
  # after the openclaw user/group have been created.
  #
  # Source files come from the Nix store (built into the system closure).
  # Target: /home/openclaw/projects/tinker/
  system.activationScripts.tinker-content = lib.stringAfter [ "users" "groups" ] ''
    DEST="/home/openclaw/projects/tinker"
    mkdir -p "$DEST"

    for dir in documents skills scripts; do
      SRC="${projectSrc}/$dir"
      if [ -d "$SRC" ]; then
        rm -rf "$DEST/$dir"
        cp -r "$SRC" "$DEST/$dir"
      fi
    done

    # Make all shell scripts executable
    if [ -d "$DEST/scripts" ]; then
      chmod +x "$DEST/scripts/"*.sh 2>/dev/null || true
    fi

    # Ensure openclaw owns everything
    chown -R openclaw:openclaw "$DEST"
  '';

  # Wire custom documents into the workspace AFTER openclaw starts.
  # openclaw regenerates workspace defaults on every service start,
  # so activation scripts (which run before service restart) get overwritten.
  # ExecStartPost runs after the gateway forks — we wait for initialization
  # then overwrite the defaults with our custom phase logic and personality.
  systemd.services.openclaw-gateway.serviceConfig.ExecStartPost =
    lib.mkAfter [ workspaceSyncScript ];
}
