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
  # Target: /home/openclaw/projects/open-builder/
  system.activationScripts.open-builder-content = lib.stringAfter [ "users" "groups" ] ''
    DEST="/home/openclaw/projects/open-builder"
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
}
