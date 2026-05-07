import asyncio
import json
import os
import socket
import subprocess
import sys
import time
import threading
import urllib.request

import pytest

SERVER_URL = os.environ.get("MCP_SSE_URL", "http://127.0.0.1:8000/sse")
SERVER_PORT = int(os.environ.get("PORT", "8000"))
SERVER_HOST = os.environ.get("HOST", "127.0.0.1")


def _start_server():
    """Start main.py in a subprocess, merging stderr into stdout."""
    env = os.environ.copy()
    proc = subprocess.Popen(
        [sys.executable, "main.py"],
        cwd=os.path.dirname(__file__) + "/..",
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env=env,
    )
    return proc


def _drain_output(proc, lines):
    """Background thread: drain proc.stdout into `lines` list."""
    for line in proc.stdout:
        lines.append(line)


def _wait_ready(proc, captured_lines, timeout=30):
    """Poll the TCP port until the server accepts connections."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        # Check the process hasn't crashed.
        if proc.poll() is not None:
            return False
        try:
            with socket.create_connection((SERVER_HOST, SERVER_PORT), timeout=1):
                return True
        except OSError:
            time.sleep(0.25)
    return False


@pytest.mark.timeout(60)
def test_e2e_solve_constraint():
    proc = _start_server()
    captured_lines = []
    drain_thread = threading.Thread(
        target=_drain_output, args=(proc, captured_lines), daemon=True
    )
    drain_thread.start()

    try:
        ready = _wait_ready(proc, captured_lines)
        if not ready:
            output = "".join(captured_lines)
            pytest.fail(
                f"Server did not become ready in time.\nServer output:\n{output}"
            )

        # Run a short-lived Python snippet that calls the core solver directly.
        # This exercises the full import chain (mcp, minizinc bindings, gecode)
        # without needing a full MCP client.
        code = r"""
import asyncio
from main import ConstraintModel, solve_constraint_core

async def run():
    problem = ConstraintModel(
        model='var 1..3: x; constraint x > 1; solve satisfy;',
        solver='gecode',
    )
    res = await solve_constraint_core(problem)
    assert res.num_solutions >= 1, f"Expected >=1 solution, got {res}"
    assert res.solutions[0].variables['x'] > 1, \
        f"Expected x > 1, got {res.solutions[0].variables}"

asyncio.run(run())
"""
        result = subprocess.run(
            [sys.executable, "-c", code],
            cwd=os.path.dirname(__file__) + "/..",
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            pytest.fail(
                f"Solver subprocess failed (exit {result.returncode}):\n"
                f"stdout: {result.stdout}\nstderr: {result.stderr}"
            )

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
