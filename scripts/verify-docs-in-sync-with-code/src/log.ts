let enabled = false;

export function enableVerbose(): void {
  enabled = true;
}

export function verbose(...args: unknown[]): void {
  if (!enabled) return;
  console.error(`\x1b[2m[verbose]\x1b[0m`, ...args);
}
