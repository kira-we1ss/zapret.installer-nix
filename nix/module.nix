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
  fwtype = cfg.firewallType;

  zapretCmd = pkgs.writeShellScriptBin "zapret" ''
    exec bash "${cfg.installerSrc}/zapret-control.sh" "$@"
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

    installerSrc = lib.mkOption {
      type        = lib.types.str;
      default     = "/var/lib/zapret.installer";
      description = "Path to the zapret installer repo. Set automatically by the flake to the Nix store path.";
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

      path = [
        pkgs.ipset pkgs.iptables pkgs.iproute2 pkgs.bash
        pkgs.nftables pkgs.coreutils pkgs.gnused pkgs.gawk
      ];

      serviceConfig = {
        Type           = "simple";
        StateDirectory = "zapret";
        ExecStartPre = pkgs.writeShellScript "zapret-fw-start" ''
          CONFIG=${stateDir}/config
          [ -f "$CONFIG" ] || exit 0

          TMPCONF=$(mktemp)
          sed \
            -e 's|/opt/zapret/files/fake/|${cfg.package}/share/zapret/fake/|g' \
            -e 's|/opt/zapret/ipset/|${stateDir}/ipset/|g' \
            -e 's|/opt/zapret/|${stateDir}/|g' \
            "$CONFIG" > "$TMPCONF"

          ZAPRET_BASE=${cfg.package}/share/zapret
          . "$TMPCONF"
          . "$ZAPRET_BASE/common/base.sh"
          . "$ZAPRET_BASE/common/fwtype.sh"
          . "$ZAPRET_BASE/common/ipt.sh"
          . "$ZAPRET_BASE/common/nft.sh"
          . "$ZAPRET_BASE/common/linux_iphelper.sh"
          . "$ZAPRET_BASE/common/linux_fw.sh"

          IPSET_DIR=${stateDir}/ipset
          ZAPRET_IP_IFACE_INCLUDE=""
          create_ipset() { return 0; }

          zapret_do_firewall 1
          rm -f "$TMPCONF"
        '';
        ExecStart = pkgs.writeShellScript "zapret-start" ''
          CONFIG=${stateDir}/config
          if [ ! -f "$CONFIG" ]; then
            echo "zapret: no config file found at $CONFIG" >&2
            exit 1
          fi

          TMPCONF=$(mktemp)
          sed \
            -e 's|/opt/zapret/files/fake/|${cfg.package}/share/zapret/fake/|g' \
            -e 's|/opt/zapret/ipset/|${stateDir}/ipset/|g' \
            -e 's|/opt/zapret/|${stateDir}/|g' \
            "$CONFIG" > "$TMPCONF"
          . "$TMPCONF"
          rm -f "$TMPCONF"

          LISTS_DIR=${stateDir}/ipset
          BINDIR=${cfg.package}/bin

          for f in "$LISTS_DIR"/ipset-*.txt; do
            [ -f "$f" ] || continue
            setname=$(basename "$f" .txt)
            ${pkgs.ipset}/bin/ipset create "$setname" hash:net family inet hashsize 4096 maxelem 1048576 2>/dev/null || true
            ${pkgs.ipset}/bin/ipset flush "$setname"
            while IFS= read -r line || [ -n "$line" ]; do
              line=$(echo "$line" | sed 's/#.*//' | xargs)
              [ -z "$line" ] && continue
              ${pkgs.ipset}/bin/ipset add "$setname" "$line" 2>/dev/null || true
            done < "$f"
          done

          case "''${MODE:-nfqws}" in
            nfqws)
              exec "$BINDIR/nfqws" --qnum="''${QNUM:-200}" $NFQWS_OPT
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
        ExecStopPost = pkgs.writeShellScript "zapret-fw-stop" ''
          CONFIG=${stateDir}/config
          [ -f "$CONFIG" ] || exit 0

          TMPCONF=$(mktemp)
          sed \
            -e 's|/opt/zapret/files/fake/|${cfg.package}/share/zapret/fake/|g' \
            -e 's|/opt/zapret/ipset/|${stateDir}/ipset/|g' \
            -e 's|/opt/zapret/|${stateDir}/|g' \
            "$CONFIG" > "$TMPCONF"

          ZAPRET_BASE=${cfg.package}/share/zapret
          . "$TMPCONF"
          . "$ZAPRET_BASE/common/base.sh"
          . "$ZAPRET_BASE/common/fwtype.sh"
          . "$ZAPRET_BASE/common/ipt.sh"
          . "$ZAPRET_BASE/common/nft.sh"
          . "$ZAPRET_BASE/common/linux_iphelper.sh"
          . "$ZAPRET_BASE/common/linux_fw.sh"

          zapret_do_firewall 0
          rm -f "$TMPCONF"
        '';
        Restart    = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
