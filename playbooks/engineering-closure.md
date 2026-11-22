# Playbook: engineering closure

## Goal
Finish an existing feature rather than expanding scope indefinitely.

## Steps
1. Inspect the actual main/head commits, PR state, callers and tests.
2. Write a short acceptance matrix and explicit non-goals.
3. Select one writer and the smallest coherent patch.
4. Add regression tests at the correct layer; preserve public contracts.
5. Run focused tests, analyzer, full CI and artifact checks.
6. Request one independent review for meaningful risk.
7. Fix blockers, document remaining device gates, update `.ai/`.

## Acceptance
CI passes for the exact head SHA; blockers are resolved; unperformed device tests remain explicitly pending; no false production-ready claim.

## Rollback
Revert the isolated commit or close the PR without merging. Keep known-good main intact.
