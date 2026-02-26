{
  description = "tinker — collaborative Discord bot powered by OpenClaw + ppq.ai";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    openclaw.url = "github:Scout-DJ/openclaw-nix";
    deploy-rs.url = "github:serokell/deploy-rs";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, openclaw, deploy-rs, disko, nixos-anywhere }:
    let
      system = "x86_64-linux";
      devSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forDevSystems = nixpkgs.lib.genAttrs devSystems;
    in
    {
      nixosConfigurations.tinker = nixpkgs.lib.nixosSystem {
        modules = [
          openclaw.nixosModules.default
          disko.nixosModules.disko
          {
            nixpkgs.overlays = [ openclaw.overlays.default ];
            nixpkgs.hostPlatform = system;
          }
          ./disko-config.nix
          ./configuration.nix
          ./modules/tinker.nix
          ./modules/credit-bot.nix
        ];
      };

      deploy = {
        nodes.tinker = {
          hostname = "178.156.161.158";
          sshUser = "root";
          autoRollback = true;
          magicRollback = true;
          remoteBuild = true;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.${system}.activate.nixos
              self.nixosConfigurations.tinker;
          };
        };
      };

      checks = builtins.mapAttrs
        (system: deployLib: deployLib.deployChecks self.deploy)
        deploy-rs.lib;

      devShells = forDevSystems (devSystem:
        let pkgs = nixpkgs.legacyPackages.${devSystem};
        in {
          default = pkgs.mkShell {
            packages = with pkgs; [
              openssh
              rsync
              jq
              curl
              hcloud
            ];
            shellHook = ''
              export PATH="$PWD/scripts:$PATH"
              echo "tinker dev shell — run 'tinker-status' to check VPS"
            '';
          };
        }
      );
    };
}
