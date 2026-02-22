import Anthropic from "@anthropic-ai/sdk";
import type { MessageParam } from "@anthropic-ai/sdk/resources/messages/messages.js";
import { relative } from "node:path";
import {
  executeTool,
  verifyTools,
  fixTools,
  type ExecuteOptions,
} from "./tools.js";
import { verbose } from "./log.js";

const MAX_TOKENS = 4096;
const MAX_TURNS = 50;
const MAX_RETRIES = 8;
const TOOL_RESULT_MAX_CHARS = 10_000;

const client = new Anthropic();

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

// -- API call with retry --

async function createWithRetry(
  params: Anthropic.MessageCreateParamsNonStreaming,
): Promise<Anthropic.Message> {
  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      return await client.messages.create(params);
    } catch (err: unknown) {
      const e = err as { status?: number; headers?: Record<string, string> };
      if (e.status === 429) {
        const retryAfter = Number(e.headers?.["retry-after"]) || 10;
        const backoff = retryAfter * 1000 + attempt * 2000;
        console.error(
          `  [rate-limited] waiting ${(backoff / 1000).toFixed(0)}s before retry ${attempt + 1}/${MAX_RETRIES}...`,
        );
        await sleep(backoff);
        continue;
      }
      throw err;
    }
  }
  throw new Error("Max retries exceeded for rate limit");
}

// -- Generic agentic loop --

interface AgentLoopParams {
  label: string;
  system: string;
  prompt: string;
  tools: Anthropic.Tool[];
  model: string;
  executeOpts?: ExecuteOptions;
}

async function agentLoop({
  label,
  system,
  prompt,
  tools,
  model,
  executeOpts = {},
}: AgentLoopParams): Promise<string> {
  const messages: MessageParam[] = [{ role: "user", content: prompt }];

  for (let turn = 0; turn < MAX_TURNS; turn++) {
    verbose(`[${label}] turn ${turn + 1}/${MAX_TURNS}`);

    const response = await createWithRetry({
      model,
      max_tokens: MAX_TOKENS,
      system,
      tools,
      messages,
    });

    const { input_tokens, output_tokens } = response.usage;
    verbose(`[${label}] stop=${response.stop_reason} tokens=${input_tokens}in/${output_tokens}out`);

    if (response.stop_reason === "end_turn") {
      return response.content
        .filter((b): b is Anthropic.TextBlock => b.type === "text")
        .map((b) => b.text)
        .join("\n")
        .trim();
    }

    if (response.stop_reason === "tool_use") {
      const toolResults: Anthropic.ToolResultBlockParam[] = [];

      for (const block of response.content) {
        if (block.type === "tool_use") {
          verbose(`[${label}] tool: ${block.name}`);
          const result = executeTool(block.name, block.input, executeOpts);

          const content =
            result.length > TOOL_RESULT_MAX_CHARS
              ? result.slice(0, TOOL_RESULT_MAX_CHARS) + "\n... (truncated)"
              : result;

          toolResults.push({
            type: "tool_result",
            tool_use_id: block.id,
            content,
          });
        }
      }

      messages.push({ role: "assistant", content: response.content });
      messages.push({ role: "user", content: toolResults });
      continue;
    }

    throw new Error(`Unexpected stop_reason: ${response.stop_reason}`);
  }

  throw new Error(`max turns exceeded (${MAX_TURNS}) during [${label}]`);
}

// -- Public API --

export async function verifyFile(
  filePath: string,
  repoDir: string,
  model: string,
): Promise<string> {
  const relPath = relative(repoDir, filePath);

  return agentLoop({
    label: `verify ${relPath}`,
    model,
    tools: verifyTools,
    system: [
      "You verify documentation accuracy against a codebase.",
      "Be efficient: use glob to check if referenced paths exist, use grep to spot-check key names.",
      "Do NOT exhaustively read every file — just verify the specific claims in the document.",
      "Use as few tool calls as possible. Batch multiple checks into single glob/grep calls when you can.",
      "When done, give your final answer as plain text with no tool calls.",
    ].join(" "),
    prompt: [
      `The repository root is '${repoDir}'.`,
      `Read the file at '${relPath}' (relative to the repo root) and then explore the codebase`,
      "to verify that the information in the document is not obsolete or out of date",
      "with respect to the actual code. Check file paths, module names, class names,",
      "patterns described, and any technical claims.",
      "If everything is up to date, output exactly 'UP_TO_DATE'.",
      "Otherwise, output a concise description of each mismatch you found.",
    ].join(" "),
  });
}

export async function fixFile(
  filePath: string,
  repoDir: string,
  mismatches: string,
  model: string,
): Promise<string> {
  const relPath = relative(repoDir, filePath);

  return agentLoop({
    label: `fix ${relPath}`,
    model,
    tools: fixTools,
    executeOpts: { allowedWritePath: filePath },
    system: [
      "You fix documentation mismatches in a codebase.",
      "Read the doc file, explore the codebase to understand the current state,",
      "then use write_file to rewrite the doc so it accurately reflects the code.",
      "Only fix factual inaccuracies — preserve the doc's tone, structure, and style.",
      "When done, state what you changed as plain text with no tool calls.",
    ].join(" "),
    prompt: [
      `The repository root is '${repoDir}'.`,
      `The documentation file is '${filePath}'.`,
      `\nThe following mismatches were found:\n${mismatches}`,
      `\nRead the doc file and explore the codebase to understand the current state.`,
      `Then use the write_file tool to rewrite '${filePath}' so it is accurate.`,
      `Only fix the mismatches listed above — do not rewrite unrelated sections.`,
    ].join("\n"),
  });
}
