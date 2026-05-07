{ lib
, stdenv
, zapret-src
, libnetfilter_queue
, libnfnetlink
, libmnl
, libcap
, zlib
, openssl
, iptables
, iproute2
, pkg-config
, bash
}:

stdenv.mkDerivation {
  pname   = "zapret";
  version = zapret-src.rev or "git";

  src = zapret-src;

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [
    libnetfilter_queue
    libnfnetlink
    libmnl
    libcap
    zlib
    openssl
    iptables
  ];

  buildPhase = ''
    runHook preBuild
    make -C nfq    PREFIX="$out"
    make -C tpws   PREFIX="$out"
    make -C ip2net PREFIX="$out"
    make -C mdig   PREFIX="$out"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/share/zapret/ipset"
    install -Dm755 nfq/nfqws    "$out/bin/nfqws"
    install -Dm755 tpws/tpws    "$out/bin/tpws"
    install -Dm755 ip2net/ip2net "$out/bin/ip2net"
    install -Dm755 mdig/mdig    "$out/bin/mdig"
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
