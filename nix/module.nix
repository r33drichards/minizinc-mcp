# NixOS module for the minizinc-mcp server.
#
# Usage (in your NixOS configuration):
#
#   {
#     inputs.minizinc-mcp.url = "github:r33drichards/minizinc-mcp";
#
#     outputs = { nixpkgs, minizinc-mcp, ... }: {
#       nixosConfigurations.my-machine = nixpkgs.lib.nixosSystem {
#         modules = [
#           minizinc-mcp.nixosModules.default
#           {
#             services.minizinc-mcp = {
#               enable   = true;
#               host     = "0.0.0.0";
#               port     = 8000;
#             };
#           }
#         ];
#       };
#     };
#   }

self: { config, lib, pkgs, ... }:

let
  cfg = config.services.minizinc-mcp;

  # Resolve the package: prefer the flake's own package but allow the user to
  # supply a custom derivation (e.g. an overlay build).
  defaultPackage =
    self.packages.${pkgs.stdenv.hostPlatform.system}.default or (
      throw "minizinc-mcp: no package for system ${pkgs.stdenv.hostPlatform.system}"
    );
in
{
  options.services.minizinc-mcp = {
    enable = lib.mkEnableOption "MiniZinc MCP server";

    package = lib.mkPackageOption pkgs "minizinc-mcp" {
      default = [ ]; # resolved below via `defaultPackage`
    } // {
      # Override the option default so it resolves from the flake output.
      default = defaultPackage;
    };

    host = lib.mkOption {
      type        = lib.types.str;
      default     = "127.0.0.1";
      description = "Address the HTTP/SSE server will bind to.";
    };

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 8000;
      description = "TCP port the HTTP/SSE server will listen on.";
    };

    user = lib.mkOption {
      type        = lib.types.str;
      default     = "minizinc-mcp";
      description = "Unix user account that runs the service.";
    };

    group = lib.mkOption {
      type        = lib.types.str;
      default     = "minizinc-mcp";
      description = "Unix group for the service user.";
    };

    openFirewall = lib.mkOption {
      type        = lib.types.bool;
      default     = false;
      description = "Open the firewall for the configured port.";
    };

    extraEnvironment = lib.mkOption {
      type        = lib.types.attrsOf lib.types.str;
      default     = { };
      example     = { LOG_LEVEL = "debug"; };
      description = "Additional environment variables passed to the service.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group        = cfg.group;
      description  = "minizinc-mcp service user";
    };

    users.groups.${cfg.group} = { };

    networking.firewall.allowedTCPPorts =
      lib.mkIf cfg.openFirewall [ cfg.port ];

    systemd.services.minizinc-mcp = {
      description   = "MiniZinc MCP Server";
      wantedBy      = [ "multi-user.target" ];
      after         = [ "network.target" ];

      environment = {
        HOST = cfg.host;
        PORT = toString cfg.port;
      } // cfg.extraEnvironment;

      serviceConfig = {
        ExecStart     = "${cfg.package}/bin/minizinc-mcp";
        User          = cfg.user;
        Group         = cfg.group;
        Restart       = "on-failure";
        RestartSec    = "5s";

        # Hardening
        NoNewPrivileges       = true;
        PrivateTmp            = true;
        ProtectSystem         = "strict";
        ProtectHome           = true;
        ReadWritePaths        = [ "/tmp" ];
        CapabilityBoundingSet = "";
        LockPersonality       = true;
        RestrictNamespaces    = true;
        RestrictRealtime      = true;
        SystemCallFilter      = "@system-service";
      };
    };
  };
}
