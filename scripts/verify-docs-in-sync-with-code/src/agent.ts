import { query, type SDKMessage } from "@anthropic-ai/claude-agent-sdk";
import { relative, resolve } from "node:path";
import { verbose } from "./log.js";

// Allow running inside a Claude Code session by stripping the nesting guard.
const cleanEnv: Record<string, string> = Object.fromEntries(
  Object.entries(process.env)
    .filter(([k]) => k !== "CLAUDECODE")
    .map(([k, v]) => [k, v ?? ""]),
);

// -- Verbose logging of SDK messages --

function logMessages(label: string, messages: SDKMessage[]): void {
  for (const msg of messages) {
    if (msg.type === "assistant" && Array.isArray(msg.content)) {
      for (const block of msg.content) {
        if (typeof block === "object" && block !== null && "type" in block && block.type === "tool_use") {
          verbose(`[${label}] tool: ${(block as { name: string }).name}`);
        }
      }
    }
    if (msg.type === "result") {
      if (msg.subtype === "success") {
        verbose(
          `[${label}] done — turns=${msg.num_turns} ` +
            `tokens=${msg.usage.input_tokens}in/${msg.usage.output_tokens}out ` +
            `cost=$${msg.total_cost_usd.toFixed(4)}`,
        );
      } else {
        verbose(`[${label}] error — subtype=${msg.subtype}`);
      }
    }
  }
}

// -- Public API --

export async function verifyFile(
  filePath: string,
  repoDir: string,
  model: string,
): Promise<string> {
  const relPath = relative(repoDir, filePath);
  const label = `verify ${relPath}`;

  const messages: SDKMessage[] = [];
  for await (const msg of query({
    prompt: [
      `The repository root is '${repoDir}'.`,
      `Read the file at '${resolve(repoDir, relPath)}' and then explore the codebase`,
      "to verify that the information in the document is not obsolete or out of date",
      "with respect to the actual code. Check file paths, module names, class names,",
      "patterns described, and any technical claims.",
      "If everything is up to date, output exactly 'UP_TO_DATE'.",
      "Otherwise, output a concise description of each mismatch you found.",
    ].join(" "),
    options: {
      systemPrompt: [
        "You verify documentation accuracy against a codebase.",
        "Be efficient: use Glob to check if referenced paths exist, use Grep to spot-check key names.",
        "Do NOT exhaustively read every file — just verify the specific claims in the document.",
        "Use as few tool calls as possible. Batch multiple checks into single Glob/Grep calls when you can.",
        "When done, give your final answer as plain text with no tool calls.",
      ].join(" "),
      allowedTools: ["Read", "Glob", "Grep"],
      model,
      cwd: repoDir,
      maxTurns: 50,
      permissionMode: "bypassPermissions",
      allowDangerouslySkipPermissions: true,
      env: cleanEnv,
    },
  })) {
    messages.push(msg);
  }

  logMessages(label, messages);

  const result = messages.find(
    (m): m is Extract<SDKMessage, { type: "result" }> => m.type === "result",
  );
  if (result && result.subtype === "success") {
    return result.result;
  }
  const errorResult = result as { subtype: string; errors?: string[] } | undefined;
  throw new Error(
    `Agent failed during [${label}]: ${errorResult?.subtype ?? "no result"} — ${errorResult?.errors?.join("; ") ?? "unknown error"}`,
  );
}

export async function fixFile(
  filePath: string,
  repoDir: string,
  mismatches: string,
  model: string,
): Promise<string> {
  const relPath = relative(repoDir, filePath);
  const label = `fix ${relPath}`;
  const resolvedPath = resolve(filePath);

  const messages: SDKMessage[] = [];
  for await (const msg of query({
    prompt: [
      `The repository root is '${repoDir}'.`,
      `The documentation file is '${filePath}'.`,
      `\nThe following mismatches were found:\n${mismatches}`,
      `\nRead the doc file and explore the codebase to understand the current state.`,
      `Then use the Write tool to rewrite '${filePath}' so it is accurate.`,
      `Only fix the mismatches listed above — do not rewrite unrelated sections.`,
    ].join("\n"),
    options: {
      systemPrompt: [
        "You fix documentation mismatches in a codebase.",
        "Read the doc file, explore the codebase to understand the current state,",
        "then use the Write tool to rewrite the doc so it accurately reflects the code.",
        "Only fix factual inaccuracies — preserve the doc's tone, structure, and style.",
        "When done, state what you changed as plain text with no tool calls.",
      ].join(" "),
      allowedTools: ["Read", "Glob", "Grep", "Write", "Edit"],
      model,
      cwd: repoDir,
      maxTurns: 50,
      permissionMode: "bypassPermissions",
      allowDangerouslySkipPermissions: true,
      env: cleanEnv,
      hooks: {
        PreToolUse: [
          {
            matcher: "Write|Edit",
            hooks: [
              async (input) => {
                const toolInput = (input as { tool_input?: Record<string, unknown> }).tool_input;
                const targetPath = (toolInput?.file_path as string) ?? "";
                if (resolve(targetPath) !== resolvedPath) {
                  return {
                    hookSpecificOutput: {
                      hookEventName: "PreToolUse" as const,
                      permissionDecision: "deny" as const,
                      permissionDecisionReason: `Writes are only allowed to ${filePath}`,
                    },
                  };
                }
                return {};
              },
            ],
          },
        ],
      },
    },
  })) {
    messages.push(msg);
  }

  logMessages(label, messages);

  const result = messages.find(
    (m): m is Extract<SDKMessage, { type: "result" }> => m.type === "result",
  );
  if (result && result.subtype === "success") {
    return result.result;
  }
  const errorResult = result as { subtype: string; errors?: string[] } | undefined;
  throw new Error(
    `Agent failed during [${label}]: ${errorResult?.subtype ?? "no result"} — ${errorResult?.errors?.join("; ") ?? "unknown error"}`,
  );
}
