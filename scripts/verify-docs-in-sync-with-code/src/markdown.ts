import MarkdownIt from "markdown-it";
import type Token from "markdown-it/lib/token.mjs";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { dirname, join, resolve, relative } from "node:path";

const md = new MarkdownIt();

function extractLinks(source: string, filePath: string, repoDir: string): string[] {
  const tokens = md.parse(source, {});
  const links: string[] = [];

  function walk(tokens: Token[]): void {
    for (const token of tokens) {
      if (token.type === "inline" && token.children) walk(token.children);
      if (token.type === "link_open") {
        const href = token.attrGet("href");
        if (!href || /^(https?:|mailto:|#)/.test(href)) continue;
        const clean = href.split("#")[0];
        if (!clean) continue;
        const fileDir = dirname(filePath);
        const resolved = resolve(repoDir, fileDir, clean);
        if (!existsSync(resolved)) continue;
        links.push(relative(repoDir, resolved));
      }
      if (token.children) walk(token.children);
    }
  }

  walk(tokens);
  return links;
}

export async function collectFiles(repoDir: string, seeds: string[]): Promise<string[]> {
  const visited = new Set<string>();
  const queue = [...seeds];
  const files: string[] = [];

  while (queue.length > 0) {
    const current = queue.shift()!;
    if (visited.has(current)) continue;
    visited.add(current);

    const fullPath = join(repoDir, current);
    if (!existsSync(fullPath)) continue;
    files.push(current);

    const source = await readFile(fullPath, "utf-8");
    for (const link of extractLinks(source, current, repoDir)) {
      if (!visited.has(link)) queue.push(link);
    }
  }

  return files;
}
