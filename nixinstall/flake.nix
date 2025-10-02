{
  description = "PKI tools flake exporting portable statically linked binaries as a .tar.gz";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    workingDir.url = "path:/home/cloudsdk/nix-devops";

    masterbuilder.url = "path:${workingDir}/nixenvs/masterbuilder";
  };

  outputs = { self, nixpkgs, flake-utils, masterbuilder, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = masterbuilder.packageSet.${system};

        tools = [
          pkgs.sops
          pkgs.age
          pkgs.mkcert
          pkgs.terraform
          pkgs.butane
        ];

        tarball = pkgs.runCommandLocal "pki-tools.tar.gz" {
          nativeBuildInputs = [ pkgs.gnutar pkgs.coreutils ];
        } ''
          mkdir -p work/bin

          # Copy each tool's binaries into work/bin
          for tool in ${toString tools}; do
            for bin in "$tool/bin/"*; do
              install -Dm755 "$bin" "work/bin/$(basename "$bin")"
            done
          done

          tar -czf pki-tools.tar.gz -C work .

          install -m644 pki-tools.tar.gz $out
        '';
      in {
        packages.default = tarball;
      }
    );
}
