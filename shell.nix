{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    (pkgs.yarn.override { nodejs = pkgs.nodejs_latest; })
    pkgs.nodejs_latest
  ];

  shellHook = ''
    DIRECTORY_NAME="/tmp/$(basename "$PWD")"
    mkdir -p $DIRECTORY_NAME/npm
    export NODE_PATH=$DIRECTORY_NAME/npm
    export NPM_CONFIG_PREFIX=$NODE_PATH
    export PATH=$NODE_PATH/bin:$PATH
  '';
}
