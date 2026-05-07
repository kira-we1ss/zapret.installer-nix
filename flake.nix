{
  description = "Automatic installation and management of bol-van/zapret";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Tracks HEAD of bol-van/zapret.  Run `nix flake update zapret-src` to
    # pull the latest commit.
    zapret-src = {
      url   = "github:bol-van/zapret";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, zapret-src }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];

      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);

      pkgsFor = system: import nixpkgs { inherit system; };
    in {
      packages = forAllSystems (system:
        let pkgs = pkgsFor system; in {
          zapret  = pkgs.callPackage ./nix/package.nix { inherit zapret-src; };
          default = pkgs.callPackage ./nix/package.nix { inherit zapret-src; };
        }
      );

      nixosModules.default = { config, pkgs, lib, ... }:
        let
          autoPackage = pkgs.callPackage ./nix/package.nix { inherit zapret-src; };
        in {
          imports = [ ./nix/module.nix ];
          config = lib.mkIf config.services.zapret.enable {
            services.zapret.package = lib.mkDefault autoPackage;
          };
        };

      nixosModules.zapret = self.nixosModules.default;

      checks = forAllSystems (system:
        let pkgs = pkgsFor system; in {
          package = self.packages.${system}.zapret;
        }
      );
    };
}
