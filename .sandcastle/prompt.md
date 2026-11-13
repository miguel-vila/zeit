# Context

Repository: !`gh repo view --json nameWithOwner --jq .nameWithOwner`

Open issues, lowest number first:

!`gh issue list --state open --limit 50 --json number,title --jq '.[] | "#\(.number) \(.title)"' | sort -V`

Issue numbers already implemented on this branch:

!`git log --no-merges -200 --pretty=%B | grep -oE '#[0-9]+' | sort -u -V | tr '\n' ' '`

# Task

Implement exactly one GitHub issue, then end your turn. You are one iteration of
a loop: the next iteration starts a fresh session with this prompt re-expanded
against the state you leave behind, and picks up the next issue. Stopping the
whole loop with an error is a correct outcome, and a better one than guessing.

## 1. Check the baseline build

Run `swift build --disable-sandbox` before changing anything. The flag is
required: SwiftPM sandboxes manifest evaluation with `sandbox-exec`, and macOS
refuses a nested sandbox (`sandbox_apply: Operation not permitted`).

If the baseline fails for a reason that is not your issue, stop the loop with
`BLOCKED` and quote the failures. Nothing you write could be verified against a
red build. Do not repair the build and do not change the pins in `Package.swift`
or `Package.resolved` to make it pass.

## 2. Pick the issue

Read each open issue in full: `gh issue view <n> --json number,title,body,labels`.

Rule out each of these, in order:

- **Already done.** Its number appears in the implemented list above. Issues are
  left open on purpose; a commit referencing the number is what marks the work
  done.
- **A tracker.** Its body lists child issues that already exist and carry the
  implementable scope. Skip it; it is not blocked and it is not work.
- **Blocked.** Its body names a dependency that is neither closed nor in the
  implemented list — a `## Blocked by` section, or wording like "blocked by #N",
  "depends on #N", "after #N". In this repository the blockers live in the issue
  bodies: GitHub's own dependency graph is empty, so a clean `blockedBy` from
  the API proves nothing. Read the `## Blocked by` section of every candidate.
  The API is a second check, not the first:
  `gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){blockedBy(first:20){nodes{number state}} subIssues(first:50){nodes{number state}} parent{number state}}}}' -F o=<owner> -F r=<repo> -F n=<n>`

Take the lowest-numbered issue that survives.

## 3. Stop the whole loop instead of implementing when

- Nothing survives step 2. Say so, and end with `NOTHING-LEFT`.
- Every remaining candidate is an epic whose child issues have not been filed
  yet — its scope section is a placeholder such as "filled in once the slice
  issues exist". Deciding how to slice an epic is not yours to make. End with
  `BLOCKED`.
- Your issue needs a decision it does not make, and the decision is
  significant: a schema or on-disk format it does not specify, a CLI or public
  API surface it does not define, a new third-party dependency, a UX choice, or
  two defensible designs with different consequences. End with `BLOCKED`.
- Your issue contradicts the code, the specs under `large-features-specs/`, or
  another issue. End with `BLOCKED`.

For `BLOCKED`, make no commits, and end your final message with the issue number
you stopped on, the specific decision or blocker, the options you see, and then
the single line:

```
<promise>BLOCKED</promise>
```

For `NOTHING-LEFT`, end your final message with one line per remaining open
issue saying why it was ruled out, and then the single line:

```
<promise>NOTHING-LEFT</promise>
```

## 4. Implementing

- Follow `CLAUDE.md`, `ARCHITECTURE.md` and the conventions already in the code.
- Satisfy every acceptance-criteria checkbox in the issue. Where the issue names
  behaviour, add tests for it — `Tests/ZeitAppTests`, swift-testing.
- Verify with `swift build --disable-sandbox` and `swift test --disable-sandbox`.
  Both must pass before you commit.
- Commit in Conventional Commits form. The footer must reference the issue
  number as `Refs #<n>`, because the next iteration reads commit messages to
  know what is already done.
- Do not push, do not open a PR, and do not change any issue's state or labels.

# Done

When the issue is implemented, tested and committed, write a short summary of
the change and the commit, and end your turn. Emit no signal line: an iteration
that finishes an issue lets the loop continue to the next one.
