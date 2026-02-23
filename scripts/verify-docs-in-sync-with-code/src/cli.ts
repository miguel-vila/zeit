import { parseArgs } from "node:util";

export interface CliArgs {
  repoDir: string;
  verifyOnly: boolean;
  verbose: boolean;
  model: string;
  include: string[];
}

const HELP = `Usage: verify-docs-in-sync-with-code [options] [repo_dir]

Options:
  --verify-only      Only verify docs, skip fix & PR phase
  --include <file>   Additional files to verify (can be repeated)
  -v, --verbose      Log turn numbers, tool calls, and token usage to stderr
  -m, --model <id>   Anthropic model to use (default: claude-haiku-4-5-20251001)
  -h, --help         Show this help message

Arguments:
  repo_dir           Repository root (defaults to cwd)

Environment:
  ANTHROPIC_API_KEY  Required. API key for the Anthropic SDK.`;

export function parseCli(): CliArgs {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      "verify-only": { type: "boolean", default: false },
      include: { type: "string", multiple: true, default: [] },
      verbose: { type: "boolean", short: "v", default: false },
      model: { type: "string", short: "m", default: "claude-haiku-4-5-20251001" },
      help: { type: "boolean", short: "h", default: false },
    },
  });

  if (values.help) {
    console.log(HELP);
    process.exit(0);
  }

  return {
    repoDir: positionals[0] ?? process.cwd(),
    verifyOnly: values["verify-only"] ?? false,
    verbose: values.verbose ?? false,
    model: values.model ?? "claude-haiku-4-5-20251001",
    include: (values.include ?? []) as string[],
  };
}
