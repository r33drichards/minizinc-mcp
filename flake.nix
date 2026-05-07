{
  description = "MiniZinc MCP Server — constraint solving via the Model Context Protocol";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # NixOS module is system-independent.
      nixosModule = import ./nix/module.nix self;
    in
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        python = pkgs.python3;

        # minizinc Python bindings (not yet in nixpkgs).
        minizinc-python = python.pkgs.buildPythonPackage rec {
          pname   = "minizinc";
          version = "0.10.0";
          format  = "pyproject";

          src = python.pkgs.fetchPypi {
            inherit pname version;
            sha256 = "sha256-zh01Ac5FBopc9BmnHlqlB+OmKjCIY4rpaiAOwyn5Cjo=";
          };

          nativeBuildInputs = [ python.pkgs.setuptools ];
          # No runtime deps beyond the minizinc binary (provided via PATH wrapper).
          doCheck = false;

          meta = with pkgs.lib; {
            description = "Python bindings for the MiniZinc constraint modelling language";
            homepage    = "https://github.com/MiniZinc/minizinc-python";
            license     = licenses.mpl20;
          };
        };

        # MCP SDK (Model Context Protocol).
        mcp-sdk = python.pkgs.buildPythonPackage rec {
          pname   = "mcp";
          version = "1.27.0";
          format  = "pyproject";

          src = python.pkgs.fetchPypi {
            inherit pname version;
            sha256 = "sha256-09w1p+7A1FjB2kl2pI+YIJfdqrh+J4xVEdWkpW6FK4M=";
          };

          nativeBuildInputs = with python.pkgs; [ hatchling ];

          propagatedBuildInputs = with python.pkgs; [
            anyio
            httpx
            pydantic
            pydantic-settings
            starlette
            uvicorn
            sse-starlette
            python-multipart
            jsonschema
            typing-extensions
            # httpx-sse / typing-inspection may not be in nixpkgs yet;
            # they are optional transitive deps that fastmcp doesn't require at
            # import time, so we skip them here.
          ];

          doCheck = false;

          meta = with pkgs.lib; {
            description = "Model Context Protocol SDK";
            homepage    = "https://github.com/modelcontextprotocol/python-sdk";
            license     = licenses.mit;
          };
        };

        pythonEnv = python.withPackages (ps: [
          ps.pydantic
          mcp-sdk
          minizinc-python
        ]);

        minizinc-mcp = pkgs.stdenv.mkDerivation {
          pname   = "minizinc-mcp";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = [ pkgs.makeWrapper ];
          buildInputs        = [ pythonEnv pkgs.minizinc ];

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
          packages = [ pythonEnv pkgs.minizinc ];
        };
      }
    ) // {
      nixosModules.default      = nixosModule;
      nixosModules.minizinc-mcp = nixosModule;
    };
}
