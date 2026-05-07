# nix/flake.nix
#
# Exposes the zapret package and NixOS module.
#
# Usage as a flake input:
#
#   inputs.zapret = {
#     url = "github:kira-we1ss/zapret.installer-nix";
#     inputs.nixpkgs.follows = "nixpkgs";
#   };
#
#   # In your NixOS configuration:
#   imports = [ inputs.zapret.nixosModules.default ];
#   services.zapret.enable = true;
#
# The zapret source (bol-van/zapret) is tracked as a separate flake input so
# that `nix flake update zapret-src` updates only the zapret binaries without
# touching the rest of the lock file.

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
      # -----------------------------------------------------------------------
      # Package: build zapret binaries
      # -----------------------------------------------------------------------
      packages = forAllSystems (system:
        let pkgs = pkgsFor system; in {
          zapret = pkgs.callPackage ./package.nix { inherit zapret-src; };
          default = pkgs.callPackage ./package.nix { inherit zapret-src; };
        }
      );

      # -----------------------------------------------------------------------
      # NixOS module
      # -----------------------------------------------------------------------
      nixosModules.default = { config, pkgs, lib, ... }:
        let
          # Wire the pre-fetched zapret-src into the module so users do not
          # need to specify a hash themselves.
          autoPackage = pkgs.callPackage ./package.nix { inherit zapret-src; };
        in {
          imports = [ ./module.nix ];
          # Override the default package with the flake-pinned one.
          config = lib.mkIf config.services.zapret.enable {
            services.zapret.package = lib.mkDefault autoPackage;
          };
        };

      # Alias
      nixosModules.zapret = self.nixosModules.default;

      # -----------------------------------------------------------------------
      # Checks (basic evaluation smoke-test)
      # -----------------------------------------------------------------------
      checks = forAllSystems (system:
        let pkgs = pkgsFor system; in {
          package = self.packages.${system}.zapret;
        }
      );
    };
}
