{
  description = "FCOS config generator with directory scanning (files + units + dropins + ssh keys)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Directories
        filesDir          = ./storage/files;
        unitsDir          = ./systemd/units;
        dropinsDir        = ./systemd/dropins;
        sshKeysDir        = ./ssh_authorized_keys;

        # Global exclusion list
        exclude = [ "ignore-this.conf" "old-service.service" ];

        # Global manual includes
        includesFiles = [ ./extra/proxy.sh ];
        includesUnits = [ ./extra/manual-unit.service ];

        # Helpers
        baseName = p: baseNameOf (toString p);

        # Collect files from a directory filtered by global exclude
        getFiles = dir:
          builtins.filter
            (f: !(builtins.elem (baseName f) exclude))
            (builtins.attrValues (pkgs.lib.fileset.toSource {
              root = dir;
              fileset = pkgs.lib.fileset.fileFilter pkgs.lib.fileset.isFile dir;
            }).files);

        storageFiles = (getFiles filesDir) ++ includesFiles;
        systemdUnits = (getFiles unitsDir) ++ includesUnits;

        # Build dropins map { unitName = [ {name, contents}... ]; ... }
        dropins =
          let
            dirs = builtins.readDir dropinsDir;
          in
            builtins.mapAttrs
              (unitName: _:
                let
                  unitPath = dropinsDir + "/${unitName}";
                  files = builtins.attrNames (builtins.readDir unitPath);
                in
                  map (f: {
                    name = f;
                    contents = builtins.readFile (unitPath + "/${f}");
                  }) files
              )
              dirs;

        # Read all SSH public keys and inline them
        sshKeys =
          if pkgs.lib.pathExists sshKeysDir then
            let keyFiles = builtins.attrNames (builtins.readDir sshKeysDir);
            in map (f: builtins.readFile (sshKeysDir + "/" + f)) keyFiles
          else [];

        # Butane storage entries
        mkFileEntry = path: {
          path = "/etc/${baseName path}";
          mode = if pkgs.lib.hasSuffix ".sh" (baseName path) then "0755" else "0644";
          contents.inline = builtins.readFile path;
        };

        # Butane unit entries, add dropins if exist
        mkUnitEntry = path:
          let
            name = baseName path;
            dIns = builtins.getAttrFromPath [ name ] dropins or [];
          in {
            inherit name;
            enabled = true;
            contents = builtins.readFile path;
            dropins = dIns;
          };

        butaneYaml = {
          variant = "fcos";
          version = "1.6.0";

          passwd.users = [
            {
              name = "core";
              groups = [ "wheel" ];
              shell = "/bin/bash";
              ssh_authorized_keys = sshKeys;
            }
          ];

          storage.files = map mkFileEntry storageFiles;

          systemd.units = map mkUnitEntry systemdUnits;
        };

      in {
        packages.default = pkgs.writeText "butane.yaml" (builtins.toJSON butaneYaml);
      });
}
