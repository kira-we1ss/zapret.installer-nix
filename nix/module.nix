# nix/module.nix
#
# NixOS module for zapret.
#
# Traditional (non-flake) usage in configuration.nix:
#
#   imports = [ /path/to/zapret.installer-nix/nix/module.nix ];
#   services.zapret.enable = true;
#
# When the module is imported without the flake the package is built via
# pkgs.callPackage using whatever zapret source the user pins themselves.
# With the flake the source is wired automatically (see flake.nix).
#
# The module exposes the following options:
#
#   services.zapret.enable          — bool
#   services.zapret.package         — derivation (defaults to auto-built from source)
#   services.zapret.firewallType    — "auto" | "iptables" | "nftables"
#   services.zapret.configFile      — path or null  (null = TUI-managed)
#   services.zapret.hostlistFile    — path or null  (null = TUI-managed)
#   services.zapret.gameMode        — bool
#
# Mutable runtime state lives in /var/lib/zapret/.
# When configFile / hostlistFile are set, nixos-rebuild switch copies them
# there (module always wins on rebuild).

{ config, pkgs, lib, ... }:

let
  cfg = config.services.zapret;

  # When the module is used without the flake there is no pre-built package
  # injected.  Fall back to building from a local fetchFromGitHub call so the
  # module stays self-contained.  Users can override via services.zapret.package.
  # When used via flake.nix the package is injected via services.zapret.package.
  # In non-flake usage you must set services.zapret.package yourself, e.g.:
  #   services.zapret.package = pkgs.callPackage ./nix/package.nix {
  #     zapret-src = pkgs.fetchFromGitHub { owner="bol-van"; repo="zapret"; rev="..."; hash="..."; };
  #   };
  defaultPackage = throw ''
    services.zapret.package is not set.
    When using the module without the flake, set it manually:

      services.zapret.package = pkgs.callPackage <path-to-zapret.installer-nix/nix/package.nix> {
        zapret-src = pkgs.fetchFromGitHub {
          owner = "bol-van"; repo = "zapret";
          rev = "<commit-or-tag>";
          hash = "<sri-hash>";
        };
      };

    Or use the flake (recommended):
      inputs.zapret.url = "github:kira-we1ss/zapret.installer-nix";
      # then add zapret.nixosModules.default to your modules list.
  '';

  stateDir = "/var/lib/zapret";

  # Resolve firewall type at activation time when set to "auto".
  # The service ExecStartPre script does the same detection at runtime, but
  # we also write it into the config file during activation so the TUI
  # management script reads the correct value.
  fwtype = cfg.firewallType;

in {
  options.services.zapret = {
    enable = lib.mkEnableOption "zapret DPI circumvention service";

    package = lib.mkOption {
      type        = lib.types.package;
      default     = defaultPackage;
      description = "The zapret package to use (nfqws/tpws binaries).";
    };

    firewallType = lib.mkOption {
      type    = lib.types.enum [ "auto" "iptables" "nftables" ];
      default = "auto";
      description = ''
        Firewall backend to use.  "auto" detects at activation time by
        inspecting iptables --version output (legacy → iptables, nf_tables →
        nftables).
      '';
    };

    configFile = lib.mkOption {
      type        = lib.types.nullOr lib.types.path;
      default     = null;
      description = ''
        Path to a zapret strategy config file (the contents of /var/lib/zapret/config).
        When set, nixos-rebuild switch always copies this file to the state dir,
        overwriting any changes made via the TUI management script.
        Set to null to manage the config exclusively via the TUI.
      '';
    };

    hostlistFile = lib.mkOption {
      type        = lib.types.nullOr lib.types.path;
      default     = null;
      description = ''
        Path to a host/IP list file (zapret-hosts-user.txt).
        Same overwrite semantics as configFile.
      '';
    };

    gameMode = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = ''
        When true, routes all traffic (0.0.0.0/0) through zapret (game mode).
        When false, writes a dummy placeholder IP to disable the game ipset.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # -----------------------------------------------------------------------
    # Ensure required tools are available system-wide
    # -----------------------------------------------------------------------
    environment.systemPackages = [
      cfg.package
      pkgs.ipset
      pkgs.iptables
    ];

    # -----------------------------------------------------------------------
    # Activation script: set up /var/lib/zapret, copy declared files
    # -----------------------------------------------------------------------
    system.activationScripts.zapret = lib.stringAfter [ "users" "groups" ] ''
      echo "zapret: setting up state directory..."
      mkdir -p ${stateDir}/ipset

      # Resolve firewall type
      _fwtype="${fwtype}"
      if [ "$_fwtype" = "auto" ]; then
        if command -v iptables >/dev/null 2>&1; then
          _ver=$(iptables --version 2>&1)
          if echo "$_ver" | grep -q "legacy"; then
            _fwtype="iptables"
          elif echo "$_ver" | grep -q "nf_tables"; then
            _fwtype="nftables"
          else
            _fwtype="iptables"
          fi
        else
          _fwtype="nftables"
        fi
      fi

      ${lib.optionalString (cfg.configFile != null) ''
        echo "zapret: installing configFile..."
        cp ${cfg.configFile} ${stateDir}/config
        # Patch FWTYPE in the copied config
        sed -i "s/^FWTYPE=.*$/FWTYPE=$_fwtype/" ${stateDir}/config
      ''}

      ${lib.optionalString (cfg.hostlistFile != null) ''
        echo "zapret: installing hostlistFile..."
        cp ${cfg.hostlistFile} ${stateDir}/ipset/zapret-hosts-user.txt
      ''}

      # Game mode ipset
      if [ "${lib.boolToString cfg.gameMode}" = "true" ]; then
        echo "0.0.0.0/0" > ${stateDir}/ipset/ipset-game.txt
      else
        # Write dummy placeholder so zapret does not complain about a missing file
        if [ ! -f ${stateDir}/ipset/ipset-game.txt ]; then
          echo "203.0.113.77" > ${stateDir}/ipset/ipset-game.txt
        fi
      fi

      # Ensure the exclude list exists
      touch ${stateDir}/ipset/zapret-hosts-user-exclude.txt
    '';

    # -----------------------------------------------------------------------
    # systemd service
    # -----------------------------------------------------------------------
    systemd.services.zapret = {
      description = "zapret DPI circumvention service";
      after    = [ "network.target" "network-online.target" ];
      wants    = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type           = "forking";
        StateDirectory = "zapret";
        # Read the config file and exec the appropriate binary.
        # The config file sourced here is the one in /var/lib/zapret/config
        # (written by the activation script or the TUI).
        ExecStartPre = pkgs.writeShellScript "zapret-prestart" ''
          set -e
          CONFIG=${stateDir}/config
          if [ ! -f "$CONFIG" ]; then
            echo "zapret: no config file found at $CONFIG — skipping start." >&2
            exit 0
          fi
        '';
        ExecStart = pkgs.writeShellScript "zapret-start" ''
          set -e
          CONFIG=${stateDir}/config
          [ -f "$CONFIG" ] || exit 0
          . "$CONFIG"

          LISTS_DIR=${stateDir}/ipset
          BINDIR=${cfg.package}/bin

          # Load ipset lists
          for f in "$LISTS_DIR"/ipset-*.txt; do
            [ -f "$f" ] || continue
            setname=$(basename "$f" .txt)
            ipset create "$setname" hash:net family inet hashsize 4096 maxelem 1048576 2>/dev/null || true
            ipset flush "$setname"
            while IFS= read -r line || [ -n "$line" ]; do
              line=$(echo "$line" | sed 's/#.*//' | xargs)
              [ -z "$line" ] && continue
              ipset add "$setname" "$line" 2>/dev/null || true
            done < "$f"
          done

          # Start nfqws or tpws based on MODE in config
          case "''${MODE:-nfqws}" in
            nfqws)
              exec "$BINDIR/nfqws" $NFQWS_OPT
              ;;
            tpws)
              exec "$BINDIR/tpws" $TPWS_OPT
              ;;
            *)
              echo "zapret: unknown MODE=''${MODE}" >&2
              exit 1
              ;;
          esac
        '';
        ExecStop = pkgs.writeShellScript "zapret-stop" ''
          pkill -f nfqws || true
          pkill -f tpws  || true
        '';
        RemainAfterExit = true;
        Restart         = "on-failure";
        RestartSec      = "5s";
      };
    };
  };
}
