{ config, pkgs, lib, ... }:

let
  cfg = config.services.zapret;

  defaultPackage = throw ''
    services.zapret.package is not set.
    Use the flake:
      inputs.zapret.url = "github:kira-we1ss/zapret.installer-nix";
    then add zapret.nixosModules.default to your modules list.
  '';

  stateDir = "/var/lib/zapret";
  installerDir = "/var/lib/zapret.installer";
  fwtype = cfg.firewallType;

  zapretCmd = pkgs.writeShellScriptBin "zapret" ''
    exec bash "${installerDir}/zapret-control.sh" "$@"
  '';

in {
  disabledModules = [ "services/networking/zapret.nix" ];

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
      description = "Firewall backend. auto detects via iptables --version.";
    };

    configFile = lib.mkOption {
      type        = lib.types.nullOr lib.types.path;
      default     = null;
      description = "Path to a zapret strategy config file. When set, copied to /var/lib/zapret/config on rebuild, overwriting TUI changes. null = TUI-managed.";
    };

    hostlistFile = lib.mkOption {
      type        = lib.types.nullOr lib.types.path;
      default     = null;
      description = "Path to a host/IP list file. Same overwrite semantics as configFile.";
    };

    gameMode = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = "Route all traffic through zapret (0.0.0.0/0 game mode).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      pkgs.ipset
      pkgs.iptables
      zapretCmd
    ];

    system.activationScripts.zapret = lib.stringAfter [ "users" "groups" ] ''
      mkdir -p ${stateDir}/ipset

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
        cp ${cfg.configFile} ${stateDir}/config
        sed -i "s/^FWTYPE=.*$/FWTYPE=$_fwtype/" ${stateDir}/config
      ''}

      ${lib.optionalString (cfg.hostlistFile != null) ''
        cp ${cfg.hostlistFile} ${stateDir}/ipset/zapret-hosts-user.txt
      ''}

      if [ "${lib.boolToString cfg.gameMode}" = "true" ]; then
        echo "0.0.0.0/0" > ${stateDir}/ipset/ipset-game.txt
      else
        if [ ! -f ${stateDir}/ipset/ipset-game.txt ]; then
          echo "203.0.113.77" > ${stateDir}/ipset/ipset-game.txt
        fi
      fi

      touch ${stateDir}/ipset/zapret-hosts-user-exclude.txt
    '';

    systemd.services.zapret = {
      description = "zapret DPI circumvention service";
      after    = [ "network.target" "network-online.target" ];
      wants    = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type           = "forking";
        StateDirectory = "zapret";
        ExecStartPre = pkgs.writeShellScript "zapret-prestart" ''
          CONFIG=${stateDir}/config
          if [ ! -f "$CONFIG" ]; then
            echo "zapret: no config file found at $CONFIG" >&2
            exit 0
          fi
        '';
        ExecStart = pkgs.writeShellScript "zapret-start" ''
          CONFIG=${stateDir}/config
          [ -f "$CONFIG" ] || exit 0
          . "$CONFIG"

          LISTS_DIR=${stateDir}/ipset
          BINDIR=${cfg.package}/bin

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
