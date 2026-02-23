#!/usr/bin/env node
/**
 * verify-docs-in-sync-with-code — Verify that documentation linked from CLAUDE.md is up to date.
 * Recursively follows markdown links to build the transitive closure of all docs,
 * then uses the Anthropic API with tool use to verify each against the codebase.
 *
 * Usage: verify-docs-in-sync-with-code [options] [repo_dir]
 *
 * Requires ANTHROPIC_API_KEY env var.
 */

import { existsSync, writeFileSync, mkdtempSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { parseCli } from "./cli.js";
import { enableVerbose } from "./log.js";
import { collectFiles } from "./markdown.js";
import { verifyFile, fixFile } from "./agent.js";
import {
  createBranch,
  commitAllChanges,
  pushBranch,
  createPR,
  restoreMainBranch,
  deleteBranch,
  hasChanges,
} from "./git.js";

interface VerifyResult {
  file: string;
  result: string;
}

const UP_TO_DATE = "UP_TO_DATE";

async function main(): Promise<void> {
  const cli = parseCli();
  if (cli.verbose) enableVerbose();

  const repoDir = resolve(cli.repoDir);
  const claudeMd = join(repoDir, "CLAUDE.md");

  if (!existsSync(claudeMd)) {
    console.error(`ERROR: ${claudeMd} not found`);
    process.exit(1);
  }

  const files = await collectFiles(repoDir, ["CLAUDE.md", ...cli.include]);

  const resultsDir = mkdtempSync(join(tmpdir(), "verify-docs-in-sync-with-code-"));
  console.log(`Results will be saved to: ${resultsDir}`);
  console.log("=========================================");
  console.log(`Discovered ${files.length} files (transitive closure):`);
  for (const f of files) console.log(`  - ${f}`);
  console.log(`\nVerifying files...\n`);

  // -- Verify phase --
  const results: VerifyResult[] = [];
  for (const file of files) {
    const fullPath = join(repoDir, file);
    const result = await verifyFile(fullPath, repoDir, cli.model);
    console.log(`--- ${file} ---`);
    console.log(result);
    console.log();
    results.push({ file, result });
  }

  for (const { file, result } of results) {
    const safeName = file.replace(/\//g, "_");
    writeFileSync(join(resultsDir, `${safeName}.txt`), result + "\n");
  }

  console.log("=========================================");
  console.log(`Done. Full results saved in: ${resultsDir}`);

  // -- Fix phase --
  const outdated = results.filter(
    (r) => !r.result.trimEnd().endsWith(UP_TO_DATE),
  );

  if (cli.verifyOnly || outdated.length === 0) {
    if (outdated.length === 0) {
      console.log("\nAll docs are up to date — nothing to fix.");
    } else {
      console.log(
        `\n--verify-only — skipping fix phase for ${outdated.length} outdated file(s).`,
      );
    }
    return;
  }

  console.log(`\n=========================================`);
  console.log(`Fixing ${outdated.length} outdated file(s)...\n`);

  for (const { file, result: mismatches } of outdated) {
    const fullPath = join(repoDir, file);
    const safeName = file.replace(/[/.]/g, "-").replace(/^-+|-+$/g, "");
    const branch = `docs/fix-${safeName}`;

    console.log(`--- Fixing ${file} ---`);
    try {
      restoreMainBranch(repoDir);
      createBranch(repoDir, branch);

      const fixResult = await fixFile(fullPath, repoDir, mismatches, cli.model);
      console.log(fixResult);

      if (!hasChanges(repoDir)) {
        console.log(`  No changes made, skipping PR.\n`);
        continue;
      }

      commitAllChanges(repoDir, `docs: fix outdated content in ${file}`);
      pushBranch(repoDir, branch);
      const prUrl = createPR(
        repoDir,
        branch,
        `docs: fix outdated content in ${file}`,
        [
          "## Summary",
          "",
          `Auto-generated fix for outdated documentation in \`${file}\`.`,
          "",
          "### Mismatches found",
          "",
          mismatches,
          "",
          "---",
          "_Created by `verify-docs-in-sync-with-code` script._",
        ].join("\n"),
      );
      console.log(`  PR created: ${prUrl}\n`);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(`  Error fixing ${file}: ${message}\n`);
    } finally {
      try {
        restoreMainBranch(repoDir);
      } catch {
        // already on main or repo in weird state — continue
      }
      try {
        deleteBranch(repoDir, branch);
      } catch {
        // branch may not exist or may have been pushed — continue
      }
    }
  }

  console.log("=========================================");
  console.log("Fix phase complete.");
}

main().catch((err: unknown) => {
  const message = err instanceof Error ? err.message : String(err);
  console.error(`\nFATAL: ${message}`);
  process.exit(1);
});
