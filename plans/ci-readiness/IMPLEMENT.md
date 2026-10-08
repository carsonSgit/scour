# Run the implementation loop

Preview the dependency order.

```sh
uv run plans/ci-readiness/implement-loop.py
```

Start the loop from this checkout in a new terminal.

```sh
uv run plans/ci-readiness/implement-loop.py --execute
```

The runner starts fresh Codex implementation and read-only review sessions for each of the 21 issues. It invokes `$implement`, `$tdd` at approved seams, and `$code-review` against each issue's fixed base.

Keep the 21 local specification files beside the script. They are the approved task snapshot; the runner rejects changed specifications on resume. Install `uv` and authenticate Codex before starting. The controller supports macOS and Linux.

Each issue gets a branch named `feature/scour-<number>` based on the preceding verified branch. The first branch targets the branch where the loop starts. These are local stacked branches, with one issue per branch delta.

Implementation sessions run with filesystem access to install required local tools and create verified commits. Review sessions use a read-only sandbox. The implementation agent must preserve the handoff files and run the existing scope/review gates before advancing.

The runner checks acceptance coverage, committed ancestry, clean tracked files, and review results. It independently reruns scope/review gates for each issue. After all issues pass, it runs `nimble test -y`, distribution tests, and a final review of the combined change.

## Resume and inspect

State and evidence live in the checkout's Git directory under `scour-readiness-loop/`. Each issue has separate attempt directories containing prompts, Codex JSONL logs, implementation results, and review results. Retries preserve earlier attempts and tell the new session where to read them. `state.json` records completed issues, pending work, branch targets, commit IDs, and specification hashes.

Rerun the same command to resume. Return to the branch recorded in `state.json` and resolve remaining tracked changes first. Completed issues are skipped only when their commits remain in the current ancestry. Concurrent controllers cannot acquire the same lock.

Any failed check, missing acceptance evidence, review finding, malformed report, or changed specification stops the loop with exit 1. Fix the reported blocker before resuming. The pending issue remains pending; the runner never discards work or resets Git history.

## External acceptance

Issue filing authorization does not authorize code pushes, hosted pipelines, or releases. The loop pauses when an issue needs those actions and records the exact approval needed. Actual GitLab/GitHub pipeline evidence and platform archive runs remain required by the approved issues.

No issues are closed by this script. A completed local commit is not proof that a hosted integration has passed. After approving and performing a required external action, resume with its observed evidence available to the agent.
