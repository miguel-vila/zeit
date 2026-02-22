import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import type Anthropic from "@anthropic-ai/sdk";

// -- Tool names as a union for type-safe dispatch --

export type ToolName = "read_file" | "glob" | "grep" | "write_file";

// -- Typed tool inputs --

interface ReadFileInput {
  path: string;
  limit?: number;
}

interface GlobInput {
  pattern: string;
  cwd: string;
}

interface GrepInput {
  pattern: string;
  path: string;
  glob?: string;
}

interface WriteFileInput {
  path: string;
  content: string;
}

// -- Tool definitions (Anthropic SDK Tool type) --

export const verifyTools: Anthropic.Tool[] = [
  {
    name: "read_file",
    description:
      "Read the contents of a file. Returns the file content as text. Use absolute paths.",
    input_schema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Absolute path to the file to read" },
        limit: {
          type: "number",
          description: "Max number of lines to read from the start. Omit to read entire file.",
        },
      },
      required: ["path"],
    },
  },
  {
    name: "glob",
    description:
      "Find files matching a glob pattern. Returns matching file paths, one per line.",
    input_schema: {
      type: "object",
      properties: {
        pattern: {
          type: "string",
          description: 'Glob pattern, e.g. "**/*.swift" or "Sources/**/CLI/*.swift"',
        },
        cwd: { type: "string", description: "Directory to search in (absolute path)" },
      },
      required: ["pattern", "cwd"],
    },
  },
  {
    name: "grep",
    description:
      "Search file contents using a regex pattern. Returns matching lines with file paths and line numbers.",
    input_schema: {
      type: "object",
      properties: {
        pattern: { type: "string", description: "Regex pattern to search for" },
        path: { type: "string", description: "Directory or file to search in (absolute path)" },
        glob: {
          type: "string",
          description: 'Optional glob to filter files, e.g. "*.swift" or "*.md"',
        },
      },
      required: ["pattern", "path"],
    },
  },
];

export const writeFileTool: Anthropic.Tool = {
  name: "write_file",
  description: "Write content to a file. Only allowed for the target doc file.",
  input_schema: {
    type: "object",
    properties: {
      path: { type: "string", description: "Absolute path to the file to write" },
      content: { type: "string", description: "Full file content to write" },
    },
    required: ["path", "content"],
  },
};

export const fixTools: Anthropic.Tool[] = [...verifyTools, writeFileTool];

// -- Tool execution --

export interface ExecuteOptions {
  allowedWritePath?: string;
}

function rg(args: string[]): string {
  const result = execFileSync("rg", args, {
    encoding: "utf-8",
    maxBuffer: 1024 * 1024,
    timeout: 10_000,
  });
  return result || "(no matches)";
}

export function executeTool(
  name: string,
  input: unknown,
  opts: ExecuteOptions = {},
): string {
  try {
    switch (name as ToolName) {
      case "read_file": {
        const { path, limit } = input as ReadFileInput;
        const content = readFileSync(path, "utf-8");
        return limit ? content.split("\n").slice(0, limit).join("\n") : content;
      }
      case "glob": {
        const { pattern, cwd } = input as GlobInput;
        return rg(["--files", "--glob", pattern, cwd]);
      }
      case "grep": {
        const { pattern, path, glob } = input as GrepInput;
        const args = ["-n", "--no-heading", pattern, path];
        if (glob) args.splice(1, 0, "--glob", glob);
        return rg(args);
      }
      case "write_file": {
        const { path, content } = input as WriteFileInput;
        if (!opts.allowedWritePath || resolve(path) !== resolve(opts.allowedWritePath)) {
          return `Error: write_file is only allowed for ${opts.allowedWritePath}`;
        }
        writeFileSync(path, content, "utf-8");
        return "File written successfully.";
      }
      default:
        return `Unknown tool: ${name}`;
    }
  } catch (err: unknown) {
    const e = err as { stdout?: string; message?: string };
    // rg returns exit code 1 for no matches
    if (e.stdout) return e.stdout || "(no matches)";
    return `Error: ${e.message ?? String(err)}`;
  }
}
