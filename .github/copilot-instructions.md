# Copilot Instructions

## Lua — Multi-Model Collaboration

When working on Lua code — whether coding, investigating bugs, or researching behavior — GPT 5.3 Codex and Claude Opus 4.6 must always work as a pair:

- **One leads, the other reviews** — at any given time, one model performs the primary work (implementing, investigating, or researching) while the other reviews and validates the output.
- **Roles are swappable** — the orchestrator decides which model leads and which reviews. Roles can be swapped at any point during the task.
- **Applies to all Lua work** — this includes coding, bug investigations, root-cause analysis, codebase exploration, and any research into Lua/addon behavior.
- **No solo work** — neither model should perform Lua tasks without the other providing a review pass.

## Verification — Never Assume It Works

After implementing a fix or change, **never declare it fixed or working**. This is a WoW addon — there is no local build or automated UI test that can verify runtime behavior. Always:

- **Ask the user to test in-game** — after making changes, tell the user what to verify and how (e.g. "/reload", open a specific UI, trigger a specific action).
- **Describe what should look different** — be specific about what the user should see if the fix worked, and what they'd see if it didn't.
- **Wait for confirmation** — do not move on to the next task or commit a "fix" message until the user confirms it works. Use phrasing like "please test this in-game" rather than "this should now work" or "this is fixed".

## Reversibility — Never Destroy History

All changes must be reversible. Never perform destructive operations that cannot be undone:

- **No force pushes** (`git push --force`) or history rewrites (`git rebase`, `git reset --hard`, `git commit --amend` on pushed commits).
- **Use `git revert`** to undo changes, never `git reset --hard`.
- **Every deletion must be a tracked commit** with a clear message explaining what was removed and why.
- **No destructive file operations** — always use git-tracked removals (`git rm`) so the history preserves what was deleted.
