{ config, pkgs, lib, ... }:

let
  # Project source, filtered to exclude .git, editor backups, etc.
  # Only documents/, skills/, and scripts/ are actually copied to the VPS.
  projectSrc = lib.cleanSource ../.;
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

    # --- Wire documents into the OpenClaw workspace ---
    # OpenClaw reads AGENTS.md, SOUL.md, TOOLS.md from its workspace directory
    # (~/.openclaw/workspace/). By default this contains generic templates.
    # Overwrite them with our custom documents so the agent gets the Tinker
    # personality and phase logic.
    WORKSPACE="/var/lib/openclaw/.openclaw/workspace"
    if [ -d "$WORKSPACE" ]; then
      for doc in AGENTS.md SOUL.md TOOLS.md; do
        if [ -f "$DEST/documents/$doc" ]; then
          cp "$DEST/documents/$doc" "$WORKSPACE/$doc"
          chmod 600 "$WORKSPACE/$doc"
        fi
      done
      # Remove BOOTSTRAP.md if present — it triggers the onboarding flow
      # instead of using our custom agent behavior.
      rm -f "$WORKSPACE/BOOTSTRAP.md"
      chown -R openclaw:openclaw "$WORKSPACE"
    fi
  '';
}
