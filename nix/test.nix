# NixOS integration test for minizinc-mcp.
#
# Run with:
#   nix build .#checks.x86_64-linux.integration --print-build-logs
# or:
#   nix flake check --print-build-logs

self: pkgs:

pkgs.testers.runNixOSTest {
  name = "minizinc-mcp";

  nodes.server = { config, pkgs, lib, ... }: {
    imports = [ (import ./module.nix self) ];

    services.minizinc-mcp = {
      enable = true;
      host   = "127.0.0.1";
      port   = 8000;
    };

    # Allow the test script to reach the service over loopback.
    networking.firewall.enable = false;
  };

  testScript = ''
    import json

    start_all()

    server.wait_for_unit("minizinc-mcp.service")
    server.wait_for_open_port(8000)

    # ------------------------------------------------------------------
    # 1. Basic liveness: the SSE endpoint must return HTTP 200.
    # ------------------------------------------------------------------
    server.succeed(
        "curl -fsSL --max-time 10 http://127.0.0.1:8000/sse -o /dev/null"
    )

    # ------------------------------------------------------------------
    # 2. Smoke-test the JSON-RPC / MCP initialise handshake.
    #    The MCP SSE transport expects a POST to /messages with a JSON
    #    body.  We POST an "initialize" request and expect a 200 back.
    # ------------------------------------------------------------------
    init_payload = json.dumps({
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "nixos-test", "version": "0.0.1"},
        },
    })

    server.succeed(
        f"curl -fsSL --max-time 10 "
        f"-X POST http://127.0.0.1:8000/messages "
        f"-H 'Content-Type: application/json' "
        f"-d '{init_payload}' "
        f"-o /dev/null"
    )

    # ------------------------------------------------------------------
    # 3. End-to-end constraint solve via the MCP tool call.
    #    We call solve_constraint with a trivial model (x in 1..3,
    #    x > 1, solve satisfy) and verify we get a solution back.
    # ------------------------------------------------------------------
    tool_payload = json.dumps({
        "jsonrpc": "2.0",
        "id": 2,
        "method": "tools/call",
        "params": {
            "name": "solve_constraint",
            "arguments": {
                "problem": {
                    "model": "var 1..3: x; constraint x > 1; solve satisfy;",
                    "solver": "gecode",
                },
            },
        },
    })

    raw = server.succeed(
        f"curl -fsSL --max-time 30 "
        f"-X POST http://127.0.0.1:8000/messages "
        f"-H 'Content-Type: application/json' "
        f"-d '{tool_payload}'"
    )

    result = json.loads(raw)

    # The response must not contain a top-level "error" key.
    assert "error" not in result, f"MCP returned an error: {result}"

    # The solve result is in result["result"]["content"][0]["text"] —
    # parse it and check we got at least one solution with x > 1.
    content_text = result["result"]["content"][0]["text"]
    solve_result  = json.loads(content_text)

    assert solve_result["status"] in ("SATISFIED", "ALL_SOLUTIONS", "OPTIMAL_SOLUTION"), \
        f"Unexpected solve status: {solve_result['status']}"

    assert solve_result["num_solutions"] >= 1, \
        f"Expected at least one solution, got: {solve_result}"

    x_val = solve_result["solutions"][0]["variables"]["x"]
    assert x_val > 1, f"Expected x > 1, got x = {x_val}"

    print(f"solve_constraint returned x = {x_val}  ✓")

    # ------------------------------------------------------------------
    # 4. Verify the service user was created and the process runs as it.
    # ------------------------------------------------------------------
    server.succeed("id minizinc-mcp")
    proc_user = server.succeed(
        "ps -o user= -p $(systemctl show -p MainPID --value minizinc-mcp)"
    ).strip()
    assert proc_user == "minizinc-mcp", \
        f"Expected service to run as 'minizinc-mcp', got '{proc_user}'"

    # ------------------------------------------------------------------
    # 5. Verify systemd hardening flags are active.
    # ------------------------------------------------------------------
    server.succeed("systemctl show minizinc-mcp | grep -q 'NoNewPrivileges=yes'")
    server.succeed("systemctl show minizinc-mcp | grep -q 'PrivateTmp=yes'")
  '';
}
