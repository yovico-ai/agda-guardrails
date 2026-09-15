{
  description = "agda-guardrails — a total Agda spec as a compiled oracle for a Go property test";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        # Same shape as Yovico's own flake.nix: plain pkgs.agda with the
        # standard-library added, no extra pins beyond nixpkgs itself.
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
          # Python venv, whatever else lives in a dev machine's shell) can
          # shadow the nix-built glibc these binaries link against, and the
          # failure mode is an opaque "undefined symbol: __nptl_change_stack_perm"
          # rather than anything naming LD_LIBRARY_PATH. Stripping it for this
          # shell is cheaper than making every reader rediscover that.
          #
          # GOTOOLCHAIN=local pins Go to whatever's on PATH (this shell's
          # pkgs.go) instead of its default "auto", which will otherwise
          # reach past the nix sandbox for a different SDK matching go.mod's
          # `go` directive if one happens to be installed on the host (gvm,
          # asdf, a system package) — reproducible for a reader is the whole
          # point of the flake.
          #
          # GOROOT/GOPATH are unset for the same reason: a Go version
          # manager (gvm, asdf, ...) on the host commonly exports both
          # globally, and an inherited GOROOT pointing at a DIFFERENT Go
          # install than the `go` binary this shell puts on PATH produces
          # exactly this error, unhelpfully worded as a version mismatch:
          # `compile: version 1.x.y does not match go tool version 1.a.b`.
          shellHook = ''
            unset LD_LIBRARY_PATH
            unset GOROOT
            unset GOPATH
            export GOTOOLCHAIN=local
          '';
        };
      });
}
