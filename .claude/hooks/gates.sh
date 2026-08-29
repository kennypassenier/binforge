#!/usr/bin/env bash
# binforge quality gates (Phase 5, H1).
# Called by .githooks/pre-commit and by the Claude Code PreToolUse hook
# before every git commit; non-zero blocks.
# Benchmarks (K11: the G8 baseline harness) and the full D1 validation
# (100 puzzles per size through the real binsolve binary) run in CI, not
# here: they take minutes and would make every commit painful.
set -euo pipefail

# ── Standing rule 7: a gate that does not predict the build is not a gate ──
# The checks below rewrite files. cargo updates Cargo.lock, formatters
# rewrite sources — and anything rewritten AFTER `git add` is green here
# and absent from the commit. mailbox's 1.0.0 commit carried a lock file
# still naming version 0.0.0; the container build refused it one step
# before a release tag, and nothing local had objected. So: fingerprint
# the tree now, compare once the checks are done, and refuse rather than
# report a green run over a tree that moved underneath it.
gate_tree_fingerprint() {
  { git status --porcelain; git diff; } | sha256sum | cut -d' ' -f1
}
gate_tree_before=$(gate_tree_fingerprint)

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

# Before L0 the workspace has no manifest yet, so the cargo gates have
# nothing to run against. Announced, never silent (standing rule 12):
# this branch disappears the moment L0 creates Cargo.toml.
if [ ! -f Cargo.toml ]; then
  echo "gates: no Cargo.toml yet (pre-L0) — cargo gates skipped, purity check still runs"
else
  cargo fmt --all -- --check
  cargo clippy --workspace --all-targets -- -D warnings
  cargo test --workspace
fi

./.claude/hooks/core-purity.sh

# Standing rule 7, second clause: see gate_tree_fingerprint above.
if [ "$(gate_tree_fingerprint)" != "$gate_tree_before" ]; then
  {
    echo "gates: the checks rewrote the working tree while they ran."
    echo "A file changed after it was staged, so what this commit carries is"
    echo "NOT what was just tested. Most often this is cargo refreshing"
    echo "Cargo.lock; the changed paths are listed below."
    echo
    git status --porcelain
    echo
    echo "What now: run 'git add -A' and commit again."
  } >&2
  exit 1
fi
