import pytest
import time
from main import ConstraintModel, solve_constraint_core


@pytest.mark.asyncio
async def test_timeout_param_smoke():
    problem = ConstraintModel(
        model="var 1..10: x; solve satisfy;",
        solver="gecode",
        timeout=1,
    )
    res = await solve_constraint_core(problem)
    assert res.status != "ERROR"
    assert res.num_solutions >= 1


@pytest.mark.asyncio
async def test_timeout_actually_times_out():
    """Test that timeout parameter actually interrupts long-running computation"""
    # Create a problem that would take a very long time to solve completely
    # Finding all solutions to 14-queens would take a VERY long time (minutes/hours)
    problem = ConstraintModel(
        model="""
        include "alldifferent.mzn";
        int: n = 14;
        array[1..n] of var 1..n: queens;
        constraint alldifferent(queens);
        constraint alldifferent([queens[i] + i | i in 1..n]);
        constraint alldifferent([queens[i] - i | i in 1..n]);
        solve satisfy;
        """,
        solver="gecode",
        all_solutions=True,  # This would take HOURS for n=14
        timeout=2,  # But we'll timeout after 2 seconds
    )

    start_time = time.time()
    res = await solve_constraint_core(problem)
    elapsed_time = time.time() - start_time

    print(f"Result status: {res.status}")
    print(f"Number of solutions: {res.num_solutions}")
    print(f"Elapsed time: {elapsed_time:.2f}s")
    print(f"Error (if any): {res.error}")
    print(f"Solve time from result: {res.solve_time}")

    # The solver should stop around the timeout duration
    # Allow some overhead (up to 5 seconds for 2 second timeout)
    assert elapsed_time < 5, f"Solver ran for {elapsed_time}s, should have timed out around 2s"

    # The elapsed time should be at least close to the timeout
    # (accounting for some overhead, should be at least 1.5 seconds)
    assert elapsed_time >= 1.5, f"Solver finished too quickly ({elapsed_time}s), timeout may not be working"

    # Should have some solutions but not all (14-queens has 365,596 solutions)
    assert res.num_solutions > 0, "Should have found at least some solutions before timeout"
    assert res.num_solutions < 100000, f"Found {res.num_solutions} solutions - solver may not have timed out properly"

    print(f"Timeout test passed: solver stopped after {elapsed_time:.2f}s (timeout was 2s)")


@pytest.mark.asyncio
async def test_no_timeout_completes():
    """Test that without timeout, a simple problem completes successfully"""
    problem = ConstraintModel(
        model="var 1..10: x; solve satisfy;",
        solver="gecode",
        timeout=None,  # No timeout
    )

    res = await solve_constraint_core(problem)
    assert res.status != "ERROR"
    assert res.num_solutions >= 1
