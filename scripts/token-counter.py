# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "anthropic>=0.40.0",
# ]
# ///
"""Count Claude tokens for all markdown files in a directory.

Outputs a JSON object mapping each .md file (relative path) to its token count,
plus a "_total" key with the sum. Only considers git-tracked files.

Usage:
    uv run scripts/token-counter.py [directory] [--model MODEL] [--output FILE]

Requires ANTHROPIC_API_KEY environment variable.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

import anthropic


def get_markdown_files(directory: Path) -> list[Path]:
    """Get all git-tracked markdown files in the directory."""
    result = subprocess.run(
        ["git", "ls-files", "*.md", "**/*.md"],
        cwd=directory,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Error: git ls-files failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return [directory / line for line in result.stdout.splitlines() if line]


def count_tokens(client: anthropic.Anthropic, text: str, model: str) -> int:
    response = client.messages.count_tokens(
        model=model,
        messages=[{"role": "user", "content": text}],
    )
    return response.input_tokens


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Count Claude tokens for all markdown files in a directory."
    )
    parser.add_argument(
        "directory",
        nargs="?",
        type=Path,
        default=Path("."),
        help="Directory to scan (default: current directory)",
    )
    parser.add_argument(
        "--model",
        default="claude-opus-4-6",
        help="Claude model for tokenization (default: claude-opus-4-6)",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=Path,
        help="Write JSON to this file instead of stdout",
    )
    args = parser.parse_args()

    directory = args.directory.resolve()
    if not directory.is_dir():
        print(f"Error: {directory} is not a directory", file=sys.stderr)
        sys.exit(1)

    md_files = get_markdown_files(directory)
    if not md_files:
        print("No git-tracked markdown files found.", file=sys.stderr)
        sys.exit(0)

    client = anthropic.Anthropic()
    counts: dict[str, int] = {}
    total = 0

    for path in sorted(md_files):
        rel = str(path.relative_to(directory))
        text = path.read_text()
        tokens = count_tokens(client, text, args.model)
        counts[rel] = tokens
        total += tokens
        print(f"  {rel}: {tokens:,}", file=sys.stderr)

    counts["_total"] = total
    output = json.dumps(counts, indent=2)

    if args.output:
        args.output.write_text(output + "\n")
        print(f"\nWrote {args.output} ({total:,} total tokens)", file=sys.stderr)
    else:
        print(output)


if __name__ == "__main__":
    main()
