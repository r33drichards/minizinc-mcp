from mcp.server.fastmcp import FastMCP
from pydantic import BaseModel
from typing import Optional, List, Dict, Any
import minizinc
import datetime


class ConstraintModel(BaseModel):
    """Model for constraint problem definition"""
    model: str  # MiniZinc model as string
    data: Optional[Dict[str, Any]] = None  # Data parameters
    solver: str = "gecode"  # Default solver
    all_solutions: bool = False
    timeout: Optional[int] = None  # Timeout in seconds

class Solution(BaseModel):
    """Model for a single solution"""
    variables: Dict[str, Any]
    objective: Optional[float] = None
    is_optimal: bool = False

class SolveResult(BaseModel):
    """Model for solving results"""
    solutions: List[Solution]
    status: str  # SATISFIED, OPTIMAL, UNSATISFIABLE, etc.
    solve_time: float
    num_solutions: int
    error: Optional[str] = None

class SolverInfo(BaseModel):
    """Model for solver information"""
    id: str
    name: str
    version: str
    tags: List[str]


async def solve_constraint_core(problem: ConstraintModel) -> "SolveResult":
    """Reusable async solver used by both the MCP tool and tests."""
    try:
        # Look up the solver
        solver = minizinc.Solver.lookup(problem.solver)

        # Create a model from the string
        model = minizinc.Model()
        model.add_string(problem.model)

        # Create an instance
        instance = minizinc.Instance(solver, model)

        # Add data parameters if provided
        if problem.data:
            for key, value in problem.data.items():
                instance[key] = value

        # Solve the problem
        if problem.timeout:
            result = await instance.solve_async(
                all_solutions=problem.all_solutions,
                time_limit=datetime.timedelta(seconds=problem.timeout)
            )
        else:
            result = await instance.solve_async(all_solutions=problem.all_solutions)

        # Process the results
        solutions: List[Solution] = []

        if result.status == minizinc.Status.SATISFIED or result.status == minizinc.Status.ALL_SOLUTIONS:
            if problem.all_solutions and result:
                # When all_solutions is True, result is iterable
                for sol in result:
                    sol_dict: Dict[str, Any] = {}
                    for key in sol.__dict__:
                        if not key.startswith('_'):
                            sol_dict[key] = sol.__dict__[key]
                    solutions.append(Solution(
                        variables=sol_dict,
                        objective=sol.objective if hasattr(sol, 'objective') else None,
                        is_optimal=False
                    ))
            elif result.solution:
                # Single solution case
                sol_dict: Dict[str, Any] = {}
                for key in result.solution.__dict__:
                    if not key.startswith('_'):
                        sol_dict[key] = result.solution.__dict__[key]
                solutions.append(Solution(
                    variables=sol_dict,
                    objective=result.objective if hasattr(result, 'objective') else None,
                    is_optimal=result.status == minizinc.Status.OPTIMAL_SOLUTION
                ))
        elif result.status == minizinc.Status.OPTIMAL_SOLUTION:
            sol_dict: Dict[str, Any] = {}
            for key in result.solution.__dict__:
                if not key.startswith('_'):
                    sol_dict[key] = result.solution.__dict__[key]
            solutions.append(Solution(
                variables=sol_dict,
                objective=result.objective if hasattr(result, 'objective') else None,
                is_optimal=True
            ))

        # Convert solve_time from timedelta to float (seconds)
        solve_time_value = 0.0
        if hasattr(result, 'statistics') and 'solveTime' in result.statistics:
            solve_time = result.statistics['solveTime']
            if hasattr(solve_time, 'total_seconds'):
                solve_time_value = solve_time.total_seconds()
            else:
                solve_time_value = float(solve_time)

        return SolveResult(
            solutions=solutions,
            status=str(result.status),
            solve_time=solve_time_value,
            num_solutions=len(solutions),
            error=None
        )

    except Exception as e:
        return SolveResult(
            solutions=[],
            status="ERROR",
            solve_time=0,
            num_solutions=0,
            error=str(e)
        )


def create_server():
    mcp = FastMCP(
        host="0.0.0.0",
        name="MiniZinc Constraint Solver MCP",
        instructions="Solve constraint satisfaction and optimization problems using MiniZinc"
    )

    @mcp.tool()
    async def solve_constraint(problem: ConstraintModel) -> SolveResult:
        """
        Solve a constraint satisfaction or optimization problem.

        Provide a MiniZinc model as a string, optional data parameters,
        and solver preferences. Returns solutions found.

        Example model:
        ```
        int: n = 4;
        array[1..n] of var 1..n: queens;
        constraint alldifferent(queens);
        constraint alldifferent(i in 1..n)(queens[i] + i);
        constraint alldifferent(i in 1..n)(queens[i] - i);
        solve satisfy;
        ```
        """
        return await solve_constraint_core(problem)

    # Expose the core solver on the app instance for programmatic tests
    setattr(mcp, "solve_constraint", solve_constraint_core)

    return mcp

app = create_server()

if __name__ == "__main__":
    app.run(transport="sse")   #, host="