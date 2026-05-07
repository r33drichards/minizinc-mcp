{
  description = "MiniZinc MCP Server — constraint solving via the Model Context Protocol";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # NixOS module is system-independent, so we expose it separately.
      nixosModule = import ./nix/module.nix self;
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        python = pkgs.python3;

        # The `minizinc` Python package may not be in nixpkgs yet; build from
        # PyPI so the flake is self-contained.
        minizinc-python = python.pkgs.buildPythonPackage rec {
          pname = "minizinc";
          version = "0.9.0";
          format = "pyproject";

          src = python.pkgs.fetchPypi {
            inherit pname version;
            sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
          };

          nativeBuildInputs = [ python.pkgs.setuptools ];
          propagatedBuildInputs = [ python.pkgs.pydantic ];

          # MiniZinc binary must be on PATH at runtime; we wire it in via the
          # wrapper below, so skip the import check here.
          doCheck = false;

          meta = {
            description = "Python bindings for the MiniZinc constraint modelling language";
            homepage    = "https://github.com/MiniZinc/minizinc-python";
            license     = pkgs.lib.licenses.mpl20;
          };
        };

        pythonEnv = python.withPackages (ps: [
          ps.pydantic
          # `mcp` (Model Context Protocol SDK) — use the nixpkgs package when
          # available, otherwise fall back to a PyPI build.
          (ps.mcp or (ps.buildPythonPackage rec {
            pname = "mcp";
            version = "1.8.0";
            format = "pyproject";

            src = ps.fetchPypi {
              inherit pname version;
              sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
            };

            nativeBuildInputs = [ ps.hatchling ];
            propagatedBuildInputs = with ps; [ anyio httpx pydantic starlette uvicorn ];

            doCheck = false;

            meta = {
              description = "Model Context Protocol SDK";
              homepage    = "https://github.com/modelcontextprotocol/python-sdk";
              license     = pkgs.lib.licenses.mit;
            };
          }))
          minizinc-python
        ]);

        minizinc-mcp = pkgs.stdenv.mkDerivation {
          pname   = "minizinc-mcp";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs = [ pythonEnv pkgs.minizinc ];

          dontBuild = true;

          installPhase = ''
            mkdir -p $out/share/minizinc-mcp $out/bin
            cp main.py $out/share/minizinc-mcp/main.py

            makeWrapper ${pythonEnv}/bin/python $out/bin/minizinc-mcp \
              --add-flags "$out/share/minizinc-mcp/main.py" \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.minizinc ]}
          '';

          meta = with pkgs.lib; {
            description = "MCP server exposing MiniZinc constraint solving";
            homepage    = "https://github.com/r33drichards/minizinc-mcp";
            license     = licenses.mit;
            maintainers = [ ];
            platforms   = platforms.linux ++ platforms.darwin;
          };
        };
      in
      {
        packages = {
          inherit minizinc-mcp;
          default = minizinc-mcp;
        };

        apps.default = flake-utils.lib.mkApp {
          drv  = minizinc-mcp;
          name = "minizinc-mcp";
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pythonEnv
            pkgs.minizinc
          ];
        };
      }
    ) // {
      nixosModules.default = nixosModule;
      nixosModules.minizinc-mcp = nixosModule;
    };
}
