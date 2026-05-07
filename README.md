# MiniZinc Constraint Solver MCP Server

A [Model Context Protocol (MCP)](https://modelcontextprotocol.io) server that provides constraint solving capabilities using [MiniZinc](https://www.minizinc.org/). Expose a single powerful tool — `solve_constraint` — that accepts any MiniZinc model and returns solutions directly inside your AI assistant.

## Features

- **solve_constraint** — General-purpose constraint solver accepting any MiniZinc model with optional data parameters, solver selection, and timeout configuration
- Supports satisfaction, optimisation, and all-solutions modes
- Works with any MiniZinc-compatible solver (default: Gecode)

---

## Quick Start

### Option 1: Hosted Version (no setup)

Use the free hosted instance:

```
https://minizinc-mcp.up.railway.app/sse
```

### Option 2: Nix / NixOS (recommended for reproducible deployments)

#### Run directly with `nix run`

```bash
nix run github:r33drichards/minizinc-mcp
```

#### Development shell

```bash
nix develop github:r33drichards/minizinc-mcp
python main.py
```

#### NixOS module

Add to your flake inputs and enable the systemd service:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url        = "github:NixOS/nixpkgs/nixos-unstable";
    minizinc-mcp.url   = "github:r33drichards/minizinc-mcp";
  };

  outputs = { nixpkgs, minizinc-mcp, ... }: {
    nixosConfigurations.my-machine = nixpkgs.lib.nixosSystem {
      system  = "x86_64-linux";
      modules = [
        minizinc-mcp.nixosModules.default
        {
          services.minizinc-mcp = {
            enable       = true;
            host         = "127.0.0.1";   # or "0.0.0.0" to expose publicly
            port         = 8000;
            openFirewall = false;          # set true to open the port
          };
        }
      ];
    };
  };
}
```

| Option | Default | Description |
|---|---|---|
| `enable` | `false` | Enable the systemd service |
| `host` | `127.0.0.1` | Bind address |
| `port` | `8000` | Listen port |
| `user` / `group` | `minizinc-mcp` | Service account (auto-created) |
| `openFirewall` | `false` | Open the port in the firewall |
| `extraEnvironment` | `{}` | Extra environment variables |

The service runs with systemd hardening (`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`, etc.).

### Option 3: Docker

```bash
git clone https://github.com/r33drichards/minizinc-mcp
cd minizinc-mcp
docker build -t minizinc-mcp .
docker run -p 8000:8000 minizinc-mcp
```

### Option 4: Local Python

**Prerequisites:** Python 3.11+, [MiniZinc 2.8+](https://www.minizinc.org/software.html)

```bash
git clone https://github.com/r33drichards/minizinc-mcp
cd minizinc-mcp
pip install -r requirements.txt
python main.py
```

The server listens on `0.0.0.0:8000` by default. Override with environment variables:

```bash
HOST=127.0.0.1 PORT=9000 python main.py
```

---

## Connecting to Claude

### Claude.ai (web)

1. Go to [claude.ai/settings/connectors](https://claude.ai/settings/connectors)
2. Click **Add Custom Connector**
3. Name: `minizinc mcp`
4. URL: `https://minizinc-mcp.up.railway.app/sse` (or your self-hosted URL)

### Claude Code (CLI)

```bash
claude mcp add minizinc -t sse https://minizinc-mcp.up.railway.app/sse
```

Then test it:

```bash
claude
```

Prompt:

> Solve the 4-Queens problem where 4 queens must be placed on a 4x4 chessboard so that no two queens attack each other

![4-Queens solution example](image.png)

---

## Example Prompts

Once connected, ask your AI assistant to solve constraint problems:

- *"Solve the 4-Queens problem where 4 queens must be placed on a 4x4 chessboard so that no two queens attack each other"*
- *"Find the optimal solution to a knapsack problem with items having weights [2,3,4,5] and values [3,4,5,6] and capacity 7"*
- *"Solve this custom constraint: I need two variables x and y between 1 and 10 where x + y = 15 and x < y"*
- *"Find all solutions to a graph colouring problem with 4 nodes and 3 colours"*

---

## Response Format

`solve_constraint` returns a `SolveResult`:

```json
{
  "solutions": [
    {
      "variables": { "x": 3, "y": 7 },
      "objective": null,
      "is_optimal": false
    }
  ],
  "status": "SATISFIED",
  "solve_time": 0.012,
  "num_solutions": 1,
  "error": null
}
```

| Field | Description |
|---|---|
| `solutions` | List of solutions found |
| `status` | `SATISFIED`, `OPTIMAL_SOLUTION`, `ALL_SOLUTIONS`, `UNSATISFIABLE`, `ERROR` |
| `solve_time` | Wall-clock solve time in seconds |
| `num_solutions` | Number of solutions returned |
| `error` | Error message, if any |

Each solution:

| Field | Description |
|---|---|
| `variables` | Map of variable name → value |
| `objective` | Objective value (optimisation problems) |
| `is_optimal` | `true` if proven optimal |

---

## Running the Tests

```bash
# Unit + integration tests (requires MiniZinc on PATH)
pytest

# NixOS VM integration test (requires Linux + KVM)
nix build .#checks.x86_64-linux.integration --print-build-logs

# Full flake check
nix flake check --print-build-logs
```

---

## License

MIT — see [LICENSE](LICENSE) for details.
