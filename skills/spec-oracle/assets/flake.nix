{
  description = "A total Agda spec, compiled, as the conformance oracle for a property test";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        agdaWithStdlib = pkgs.agda.withPackages (p: [
          p.standard-library
        ]);
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            agdaWithStdlib
            pkgs.ghc
            pkgs.go
            pkgs.gnumake
          ];

          # An ambient LD_LIBRARY_PATH from unrelated host tooling (CUDA, a
          # Python venv, a Go version manager) can shadow the nix-built glibc
          # these binaries link against; the failure mode is an opaque
          # "undefined symbol: __nptl_change_stack_perm" that names nothing
          # useful. Stripping it here is cheaper than rediscovering that.
          #
          # GOTOOLCHAIN=local pins Go to this shell's binary instead of its
          # default "auto", which will otherwise reach past the nix sandbox
          # for a different SDK if one happens to be installed on the host.
          #
          # GOROOT/GOPATH are unset for the same reason: an inherited GOROOT
          # pointing at a different Go install than the `go` on PATH fails
          # as `compile: version 1.x.y does not match go tool version 1.a.b`.
          shellHook = ''
            unset LD_LIBRARY_PATH
            unset GOROOT
            unset GOPATH
            export GOTOOLCHAIN=local
          '';
        };
      });
}
