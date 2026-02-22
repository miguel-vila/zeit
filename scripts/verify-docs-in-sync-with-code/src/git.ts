import { execFileSync } from "node:child_process";

function git(repoDir: string, ...args: string[]): string {
  return execFileSync("git", args, { cwd: repoDir, encoding: "utf-8" }).trim();
}

export function createBranch(repoDir: string, branchName: string): void {
  git(repoDir, "checkout", "-b", branchName);
}

export function commitChanges(repoDir: string, filePath: string, message: string): void {
  git(repoDir, "add", filePath);
  git(repoDir, "commit", "-m", message);
}

export function createPR(repoDir: string, branch: string, title: string, body: string): string {
  return execFileSync(
    "gh",
    ["pr", "create", "--head", branch, "--title", title, "--body", body],
    { cwd: repoDir, encoding: "utf-8" },
  ).trim();
}

export function restoreMainBranch(repoDir: string): void {
  git(repoDir, "checkout", "main");
}

export function deleteBranch(repoDir: string, branchName: string): void {
  git(repoDir, "branch", "-D", branchName);
}

export function hasChanges(repoDir: string, filePath: string): boolean {
  const status = git(repoDir, "status", "--porcelain", filePath);
  return status.length > 0;
}
