{
  description = "open-builder — collaborative Discord bot powered by OpenClaw + ppq.ai";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    openclaw.url = "github:Scout-DJ/openclaw-nix";
    deploy-rs.url = "github:serokell/deploy-rs";
  };

  outputs = { self, nixpkgs, openclaw, deploy-rs }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.open-builder = nixpkgs.lib.nixosSystem {
        modules = [
          openclaw.nixosModules.default
          {
            nixpkgs.overlays = [ openclaw.overlays.default ];
            nixpkgs.hostPlatform = system;
          }
          ./configuration.nix
          ./modules/open-builder.nix
        ];
      };

      deploy = {
        nodes.open-builder = {
          hostname = "open-builder.example.com"; # TODO: replace with actual VPS IP/hostname
          sshUser = "root";
          autoRollback = true;
          magicRollback = true;

          profiles.system = {
            user = "root";
            path = deploy-rs.lib.${system}.activate.nixos
              self.nixosConfigurations.open-builder;
          };
        };
      };

      checks = builtins.mapAttrs
        (system: deployLib: deployLib.deployChecks self.deploy)
        deploy-rs.lib;
    };
}
