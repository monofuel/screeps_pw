{
  description = "Screeps PW browser toolchain";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: let
    pkgs = import nixpkgs { system = "x86_64-linux"; };
  in {
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [ nim emscripten stdenv.cc pkg-config openssl curl ];
      LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath [ pkgs.curl pkgs.openssl ];
    };
  };
}
