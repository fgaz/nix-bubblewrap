{
  description = "Nix - bubblewrap integration";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nixpkgs, flake-utils }: flake-utils.lib.eachDefaultSystem (system: rec {
    packages.nix-bubblewrap = import ./. { pkgs = nixpkgs.legacyPackages."${system}"; };
    defaultPackage = packages.nix-bubblewrap;
  });
}
