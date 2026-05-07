{ config, pkgs, lib, ... }:

let
  cfg = config.services.zapret;

  defaultPackage = throw ''
    services.zapret.package is not set.

    Flake users: add zapret.nixosModules.default to your modules list —
    the package is set automatically.

    Channel users: set services.zapret.package explicitly, e.g.:
      services.zapret.package = pkgs.callPackage ./zapret-package.nix {
        zapret-src = pkgs.fetchFromGitHub {
          owner = "bol-van";
          repo  = "zapret";
          rev   = "<pinned-commit-sha>";
          hash  = "sha256-...";
        };
      };
    See README.md for full channel installation instructions.
  '';

  stateDir = "/var/lib/zapret";
  fwtype = cfg.firewallType;

  zapretCmd = pkgs.writeShellScriptBin "zapret" ''
    exec bash "${cfg.installerSrc}/zapret-control.sh" "$@"
  '';

  patchConf = pkgs.writeShellScript "zapret-patch-conf" ''
    sed \
      -e 's|/opt/zapret/files/fake/|${cfg.package}/share/zapret/fake/|g' \
      -e 's|/opt/zapret/ipset/|${stateDir}/ipset/|g' \
      -e 's|/opt/zapret/|${stateDir}/|g' \
      "$1"
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
      pkgs.nftables
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
        pkgs.procps pkgs.kmod
      ];

      serviceConfig = {
        Type           = "simple";
        StateDirectory = "zapret";

        ExecStartPre = pkgs.writeShellScript "zapret-fw-start" ''
          CONFIG=${stateDir}/config
          [ -f "$CONFIG" ] || exit 0
          TMPCONF=$(mktemp)
          ${patchConf} "$CONFIG" > "$TMPCONF"
          . "$TMPCONF"
          rm -f "$TMPCONF"
          QNUM="''${QNUM:-200}"

          if [ "''${FWTYPE:-nftables}" = "nftables" ]; then
            nft add table inet zapret 2>/dev/null || true
            nft add chain inet zapret postrouting '{ type filter hook postrouting priority mangle; }' 2>/dev/null || true
            nft add chain inet zapret prerouting  '{ type filter hook prerouting  priority mangle; }' 2>/dev/null || true
            if [ -n "''${NFQWS_PORTS_TCP:-}" ]; then
              nft add rule inet zapret postrouting tcp dport "{ ''${NFQWS_PORTS_TCP} }" ct original packets 1-"''${NFQWS_TCP_PKT_OUT:-6}" queue num "$QNUM" bypass 2>/dev/null || true
            fi
            if [ -n "''${NFQWS_PORTS_UDP:-}" ]; then
              nft add rule inet zapret postrouting udp dport "{ ''${NFQWS_PORTS_UDP} }" ct original packets 1-"''${NFQWS_UDP_PKT_OUT:-6}" queue num "$QNUM" bypass 2>/dev/null || true
            fi
          else
            iptables  -t mangle -N ZAPRET 2>/dev/null || iptables  -t mangle -F ZAPRET
            ip6tables -t mangle -N ZAPRET 2>/dev/null || ip6tables -t mangle -F ZAPRET
            if [ -n "''${NFQWS_PORTS_TCP:-}" ]; then
              iptables  -t mangle -A ZAPRET -p tcp -m multiport --dports "''${NFQWS_PORTS_TCP}" -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:"''${NFQWS_TCP_PKT_OUT:-6}" -j NFQUEUE --queue-num "$QNUM" --queue-bypass
              ip6tables -t mangle -A ZAPRET -p tcp -m multiport --dports "''${NFQWS_PORTS_TCP}" -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:"''${NFQWS_TCP_PKT_OUT:-6}" -j NFQUEUE --queue-num "$QNUM" --queue-bypass
            fi
            if [ -n "''${NFQWS_PORTS_UDP:-}" ]; then
              iptables  -t mangle -A ZAPRET -p udp -m multiport --dports "''${NFQWS_PORTS_UDP}" -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:"''${NFQWS_UDP_PKT_OUT:-6}" -j NFQUEUE --queue-num "$QNUM" --queue-bypass
              ip6tables -t mangle -A ZAPRET -p udp -m multiport --dports "''${NFQWS_PORTS_UDP}" -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:"''${NFQWS_UDP_PKT_OUT:-6}" -j NFQUEUE --queue-num "$QNUM" --queue-bypass
            fi
            iptables  -t mangle -A POSTROUTING -j ZAPRET
            ip6tables -t mangle -A POSTROUTING -j ZAPRET
          fi
        '';

        ExecStart = pkgs.writeShellScript "zapret-start" ''
          CONFIG=${stateDir}/config
          if [ ! -f "$CONFIG" ]; then
            echo "zapret: no config file found at $CONFIG" >&2
            exit 1
          fi
          TMPCONF=$(mktemp)
          ${patchConf} "$CONFIG" > "$TMPCONF"
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
          ${patchConf} "$CONFIG" > "$TMPCONF"
          . "$TMPCONF"
          rm -f "$TMPCONF"

          if [ "''${FWTYPE:-nftables}" = "nftables" ]; then
            nft delete table inet zapret 2>/dev/null || true
          else
            iptables  -t mangle -D POSTROUTING -j ZAPRET 2>/dev/null || true
            ip6tables -t mangle -D POSTROUTING -j ZAPRET 2>/dev/null || true
            iptables  -t mangle -F ZAPRET 2>/dev/null || true
            ip6tables -t mangle -F ZAPRET 2>/dev/null || true
            iptables  -t mangle -X ZAPRET 2>/dev/null || true
            ip6tables -t mangle -X ZAPRET 2>/dev/null || true
          fi
        '';

        Restart    = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
