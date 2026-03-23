{
  description = "tinker — collaborative AI building platform";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko }:
    let
      system = "x86_64-linux";
      devSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forDevSystems = nixpkgs.lib.genAttrs devSystems;
    in
    {
      nixosConfigurations.tinker = nixpkgs.lib.nixosSystem {
        modules = [
          disko.nixosModules.disko
          {
            nixpkgs.hostPlatform = system;
          }
          ./disko-config.nix
          ./configuration.nix
          ./modules/agent.nix
          ./modules/caddy.nix
        ];
      };

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
