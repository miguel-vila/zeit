import { execFileSync } from "node:child_process";

function git(repoDir: string, ...args: string[]): string {
  return execFileSync("git", args, { cwd: repoDir, encoding: "utf-8" }).trim();
}

export function branchExists(repoDir: string, branchName: string): boolean {
  try {
    git(repoDir, "rev-parse", "--verify", branchName);
    return true;
  } catch {
    return false;
  }
}

export function createBranch(repoDir: string, branchName: string): void {
  if (branchExists(repoDir, branchName)) {
    deleteBranch(repoDir, branchName);
  }
  git(repoDir, "checkout", "-b", branchName);
}

export function commitAllChanges(repoDir: string, message: string): void {
  git(repoDir, "add", "-A");
  git(repoDir, "commit", "-m", message);
}

export function pushBranch(repoDir: string, branchName: string): void {
  git(repoDir, "push", "--force", "-u", "origin", branchName);
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

export function hasChanges(repoDir: string): boolean {
  const status = git(repoDir, "status", "--porcelain");
  return status.length > 0;
}
