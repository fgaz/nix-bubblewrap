{ pkgs ? import <nixpkgs> {} }:

pkgs.tcl.mkTclDerivation rec {
  pname = "nix-bubblewrap";
  version = "unstable";

  dontUnpack = true;

  buildInputs = with pkgs; [
    tcllib
    bubblewrap
    coreutils
    which
  ];

  nativeBuildInputs = [
    pkgs.makeWrapper
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 ${./nix-bwrap.tcl} $out/bin/nix-bwrap
    wrapProgram $out/bin/nix-bwrap \
      --prefix PATH : "${pkgs.lib.makeBinPath buildInputs}"
    runHook postInstall
  '';

  passthru.exePath = "/bin/nix-bwrap";

  meta.mainProgram = "nix-bwrap";
}
