import { run, claudeCode } from "@ai-hero/sandcastle";
import { seatbelt } from "@ai-hero/sandcastle/sandboxes/seatbelt";
import { execFileSync } from "node:child_process";
import { mkdirSync, realpathSync } from "node:fs";
import { join } from "node:path";

// Run this with: npx tsx .sandcastle/main.mts
//
// seatbelt() keeps the host's macOS toolchain, which no Linux container can
// offer this project. It runs every command through a pipe, so it has no tty
// and interactive() rejects it: the agent runs headless from prompt.md.

const darwinDir = (name: string) =>
  realpathSync(execFileSync("getconf", [name], { encoding: "utf8" }).trim());

// Claude Code builds this scratch root itself rather than from TMPDIR, so the
// sandbox has to expose that exact path.
const claudeScratch = `/private/tmp/claude-${process.getuid()}`;
mkdirSync(claudeScratch, { recursive: true, mode: 0o700 });

// Finishing one issue ends an iteration but not the run: the next iteration is
// a fresh agent session whose prompt is re-expanded against the current issue
// list. Only these two signals end the loop.
const DRAINED = "<promise>NOTHING-LEFT</promise>";
const BLOCKED = "<promise>BLOCKED</promise>";
const MAX_ISSUES_PER_RUN = 12;

const result = await run({
  agent: claudeCode("claude-opus-5[1m]", {
    effort: "xhigh",
    permissionMode: "bypassPermissions",
  }),
  sandbox: seatbelt({
    mounts: [
      // The /usr/bin git and swift shims load libxcrun and the DVT frameworks
      // from the active Xcode; compiling then needs the shared clang module
      // cache and the temp dir SwiftPM writes through.
      {
        hostPath: "/Applications/Xcode.app",
        sandboxPath: "/Applications/Xcode.app",
        readonly: true,
      },
      { hostPath: claudeScratch, sandboxPath: claudeScratch },
      ...[
        join(darwinDir("DARWIN_USER_CACHE_DIR"), "clang"),
        darwinDir("DARWIN_USER_TEMP_DIR"),
      ].map((p) => ({ hostPath: p, sandboxPath: p })),
    ],
  }),
  promptFile: "./.sandcastle/prompt.md",
  completionSignal: [DRAINED, BLOCKED],
  maxIterations: MAX_ISSUES_PER_RUN,
  // A cold SwiftPM build of MLX and swift-transformers can run for minutes
  // with no output, which the 600s default reads as an idle agent.
  idleTimeoutSeconds: 1800,
});

const log = result.logFilePath ?? ".sandcastle/logs/main.log";
const commits = `${result.commits.length} commit(s)`;

if (result.completionSignal === BLOCKED) {
  throw new Error(
    `Stopped on a decision the agent would not make, after ${commits}. Its reasoning is above and in ${log}.`,
  );
}
if (result.completionSignal === DRAINED) {
  console.log(`Nothing left to implement. ${commits}.`);
} else {
  console.log(
    `Stopped at the ${MAX_ISSUES_PER_RUN}-issue cap after ${commits}; issues may remain. Raise MAX_ISSUES_PER_RUN or run again. Log: ${log}`,
  );
}
