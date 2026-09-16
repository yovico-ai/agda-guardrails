{
  description = "agda-guardrails — a total Agda spec as a compiled oracle for a Go property test";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    # Not eachDefaultSystem: nixpkgs unstable dropped x86_64-darwin in 26.11
    # and importing it for that system now throws, which would take the
    # whole flake down with it.
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        lib = nixpkgs.lib;

        # Same shape as Yovico's own flake.nix: plain pkgs.agda with the
        # standard-library added, no extra pins beyond nixpkgs itself.
        agdaWithStdlib = pkgs.agda.withPackages (p: [
          p.standard-library
        ]);

        toolchain = [ agdaWithStdlib pkgs.ghc pkgs.go pkgs.gnumake ];
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = toolchain;

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
      }
      # Gated on the system string, not on pkgs: flake-utils assembles this
      # attrset eagerly for every system, and forcing pkgs here would import
      # nixpkgs for each of them just to decide whether to add an attribute.
      // lib.optionalAttrs (lib.hasSuffix "-linux" system) {
        # The no-Nix door: the same four packages on a Debian base, for
        # `docker run`, a GitHub Actions `container:`, and .devcontainer/.
        # Built FROM this flake so it cannot carry a different Agda or
        # stdlib than `nix develop` does. The base is the devcontainers
        # image rather than bare Debian because Codespaces / VS Code Server
        # need libstdc++ and a non-root user, and an Actions `container:`
        # needs the standard glibc loader path — a pure-nix image has none
        # of those. Nothing here writes into /bin: the tools are reached
        # through PATH, which leaves Debian's merged-usr /bin symlink alone.
        packages.image = pkgs.dockerTools.buildLayeredImage {
          name = "ghcr.io/yovico-ai/agda-guardrails";
          tag = "latest";
          fromImage = pkgs.dockerTools.pullImage {
            imageName = "mcr.microsoft.com/devcontainers/base";
            imageDigest = "sha256:3aacff4130e6cf04709f9cab1d7a6d3e1cc4bff6202bc61611831a18d3755673";
            hash = "sha256-pNS9JD/Hv1FHNzfCswrufn+x7gxLWLnIypYrKhDVMdM=";
            finalImageName = "mcr.microsoft.com/devcontainers/base";
            finalImageTag = "bookworm";
          };
          config = {
            Env = [
              "PATH=${lib.makeBinPath toolchain}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
              # GHC-compiled programs (agda, the oracle) refuse to print
              # non-ASCII under a non-UTF-8 locale; C.UTF-8 is built into glibc.
              "LANG=C.UTF-8"
              "LC_ALL=C.UTF-8"
              # Same pin as the devShell, same reason.
              "GOTOOLCHAIN=local"
              # Caches under /tmp so `docker run` works as any uid, including
              # against a bind-mounted checkout owned by someone else.
              "GOCACHE=/tmp/go-build"
              "GOMODCACHE=/tmp/go-mod"
              "GOPATH=/tmp/go"
              # That bind-mounted checkout is usually owned by a different uid
              # than the container's. Without these, git refuses to look at it
              # ("dubious ownership") and Go's VCS stamping fails the build.
              "GOFLAGS=-buildvcs=false"
              "GIT_CONFIG_COUNT=1"
              "GIT_CONFIG_KEY_0=safe.directory"
              "GIT_CONFIG_VALUE_0=*"
            ];
            WorkingDir = "/work";
            Cmd = [ "/bin/bash" ];
          };
          extraCommands = "mkdir -p -m 1777 work";
        };
      });
}
