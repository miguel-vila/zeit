# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "anthropic>=0.40.0",
# ]
# ///
"""Generate docs/token-counts.md with a table of token counts per markdown file.

Shows token counts and % of context window for several Claude models.

Usage:
    uv run scripts/token-counts-report.py

Requires ANTHROPIC_API_KEY environment variable.
"""

import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import anthropic

CONTEXT_WINDOWS = [200_000, 1_000_000]

REPO_ROOT = Path(__file__).resolve().parent.parent


def get_markdown_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "*.md", "**/*.md"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Error: git ls-files failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    paths = [REPO_ROOT / line for line in result.stdout.splitlines() if line]
    # Group symlinks with their targets so they appear as a single row
    seen_real: dict[Path, list[str]] = {}
    for p in sorted(paths):
        real = p.resolve()
        rel = str(p.relative_to(REPO_ROOT))
        seen_real.setdefault(real, []).append(rel)
    # Return one representative path per real file, keeping all names for labeling
    unique: list[tuple[Path, str]] = []
    for real, names in sorted(seen_real.items(), key=lambda x: x[1][0]):
        label = " / ".join(names)
        unique.append((real, label))
    return unique


def count_tokens(client: anthropic.Anthropic, text: str) -> int:
    response = client.messages.count_tokens(
        model="claude-opus-4-6",
        messages=[{"role": "user", "content": text}],
    )
    return response.input_tokens


def pct(tokens: int, context: int) -> str:
    value = tokens / context * 100
    if value < 0.01:
        return "<0.01%"
    return f"{value:.2f}%"


def ctx_label(size: int) -> str:
    return f"{size // 1000}K"


def render_table(file_counts: list[tuple[str, int]], total: int) -> str:
    cols = ["File", "Tokens"] + [f"% of {ctx_label(ctx)}" for ctx in CONTEXT_WINDOWS]
    header = "| " + " | ".join(cols) + " |"
    sep = "| " + " | ".join(["---"] * len(cols)) + " |"

    rows = [header, sep]

    for filename, tokens in file_counts:
        pcts = [pct(tokens, ctx) for ctx in CONTEXT_WINDOWS]
        row = f"| `{filename}` | {tokens:,} | " + " | ".join(pcts) + " |"
        rows.append(row)

    pcts = [pct(total, ctx) for ctx in CONTEXT_WINDOWS]
    row = f"| **Total** | **{total:,}** | " + " | ".join(f"**{p}**" for p in pcts) + " |"
    rows.append(row)

    return "\n".join(rows)


def main() -> None:
    md_files = get_markdown_files()
    if not md_files:
        print("No git-tracked markdown files found.", file=sys.stderr)
        sys.exit(0)

    client = anthropic.Anthropic()
    file_counts: list[tuple[str, int]] = []
    total = 0

    for path, label in md_files:
        text = path.read_text()
        tokens = count_tokens(client, text)
        file_counts.append((label, tokens))
        total += tokens
        print(f"  {label}: {tokens:,}", file=sys.stderr)

    table = render_table(file_counts, total)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    content = f"""# Token Counts

How much of the context window do the project's markdown files consume?

Generated on {now}. All current Claude models share the same tokenizer.

{table}
"""

    out = REPO_ROOT / "docs" / "token-counts.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(content)
    print(f"\nWrote {out} ({total:,} total tokens)", file=sys.stderr)


if __name__ == "__main__":
    main()
