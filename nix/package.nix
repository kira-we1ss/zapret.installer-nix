# nix/package.nix
#
# Builds the zapret binaries (nfqws, tpws, ip2net, mdig) from source.
#
# Usage (traditional, without flakes):
#   pkgs.callPackage ./nix/package.nix {
#     zapret-src = pkgs.fetchFromGitHub {
#       owner = "bol-van"; repo = "zapret";
#       rev = "..."; hash = "sha256-...";
#     };
#   }
#
# When used via flake.nix the zapret-src argument is wired up automatically.

{ lib
, stdenv
, zapret-src
, libnetfilter_queue
, libcap
, zlib
, openssl
, iptables
, iproute2
, pkg-config
, bash
}:

stdenv.mkDerivation {
  pname = "zapret";
  # The upstream repo has no version file; use the git revision supplied by
  # the caller (flake) or fall back to "git".
  version = zapret-src.rev or "git";

  src = zapret-src;

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    libnetfilter_queue
    libcap
    zlib
    openssl
    iptables
  ];

  # zapret does not have a top-level Makefile that builds everything at once.
  # Each tool is in its own subdirectory with its own Makefile.
  buildPhase = ''
    runHook preBuild

    for tool in nfqws tpws ip2net mdig; do
      if [ -d "$tool" ]; then
        echo "Building $tool..."
        make -C "$tool" PREFIX="$out"
      fi
    done

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/zapret/ipset"

    for tool in nfqws tpws ip2net mdig; do
      if [ -f "$tool/$tool" ]; then
        install -Dm755 "$tool/$tool" "$out/bin/$tool"
      fi
    done

    # Install the ipset helper scripts used by the service
    if [ -d ipset ]; then
      for f in ipset/get_*.sh ipset/create_*.sh; do
        [ -f "$f" ] && install -Dm755 "$f" "$out/share/zapret/ipset/$(basename "$f")"
      done
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "DPI circumvention tool (nfqws/tpws) by bol-van";
    homepage    = "https://github.com/bol-van/zapret";
    license     = licenses.mit;
    platforms   = platforms.linux;
    maintainers = [];
  };
}
