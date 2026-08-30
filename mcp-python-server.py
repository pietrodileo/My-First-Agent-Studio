"""Small deterministic stdio MCP server used by the tutorial agent."""

import logging
import statistics
import sys

from mcp.server.fastmcp import FastMCP

logging.basicConfig(stream=sys.stderr, level=logging.INFO)
mcp = FastMCP("healthcare-statistics", log_level="ERROR")


@mcp.tool()
async def add_numbers(first: float, second: float) -> dict:
    """Add two numbers and return the operands and deterministic result.

    Args:
        first: First number to add.
        second: Second number to add.
    """
    return {
        "first": float(first),
        "second": float(second),
        "result": float(first) + float(second),
    }


@mcp.tool()
async def summarize_measurements(
    values: list[float],
    label: str = "values",
) -> dict:
    """Return bounded descriptive statistics for synthetic numeric values.

    Args:
        values: One to 100 synthetic numeric measurements.
        label: Short label identifying the measurements.
    """
    if not values:
        raise ValueError("values must contain at least one number")
    if len(values) > 100:
        raise ValueError("values cannot contain more than 100 numbers")

    normalized = [float(value) for value in values]
    return {
        "label": label,
        "count": len(normalized),
        "minimum": min(normalized),
        "maximum": max(normalized),
        "mean": round(statistics.fmean(normalized), 2),
        "median": round(statistics.median(normalized), 2),
        "syntheticOnly": True,
    }


@mcp.tool()
async def count_categories(
    values: list[str],
    label: str = "categories",
) -> dict:
    """Count up to 100 synthetic categorical values without clinical inference.

    Args:
        values: One to 100 synthetic category values.
        label: Short label identifying the categories.
    """
    if not values:
        raise ValueError("values must contain at least one category")
    if len(values) > 100:
        raise ValueError("values cannot contain more than 100 categories")

    counts: dict[str, int] = {}
    for value in values:
        category = str(value).strip() or "Unknown"
        counts[category] = counts.get(category, 0) + 1

    return {
        "label": label,
        "count": len(values),
        "categories": counts,
        "syntheticOnly": True,
    }

@mcp.tool()
async def get_mcp_info() -> dict:
    """Return the private identity marker of this MCP server.
    This tool is used to verify that the agent is calling the correct MCP server.
    """
    return {
        "name": "healthcare-statistics",
        "version": "0.1.0",
        "marker": "FIRST_AGENT_MCP_7F3A",
        "tools": [
            "add_numbers",
            "count_categories",
            "get_mcp_info",
            "summarize_measurements",
        ],
    }

if __name__ == "__main__":
    mcp.run(transport="stdio")
