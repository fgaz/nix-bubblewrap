{ pkgs ? import <nixpkgs> {}
, nix-bubblewrap ? import ./. { inherit pkgs; } }:

{
  wrapProgram =
    { name # name of the program
    , options ? [] # nix-bwrap cli options
    , program # path to the binary to wrap
    }:

    # runCommand isn't enough because we need makeBinaryWrapper, which is a hook
    pkgs.stdenvNoCC.mkDerivation {
      name = "${name}-bwrapped";
      dontUnpack = true;
      dontPatch = true;
      dontConfigure = true;
      dontBuild = true;
      nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        makeBinaryWrapper \
          ${nix-bubblewrap}/bin/nix-bwrap \
          $out/bin/$(basename ${program}) \
          --add-flags "${toString options}" \
          --add-flags ${program}
        runHook postInstall
      '';
    };

  wrapPackage =
    { options ? [] # nix-bwrap cli options
    , package # package to wrap
    , name ? package.name
    }:

    pkgs.stdenvNoCC.mkDerivation {
      name = "${name}-bwrapped";
      dontUnpack = true;
      dontPatch = true;
      dontConfigure = true;
      dontBuild = true;
      nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin
        for bin in ${package}/bin/*; do
          makeBinaryWrapper \
            ${nix-bubblewrap}/bin/nix-bwrap \
            $out/bin/$(basename "$bin") \
            --add-flags "${toString options}" \
            --add-flags "$bin"
        done
        runHook postInstall
      '';
    };
}
