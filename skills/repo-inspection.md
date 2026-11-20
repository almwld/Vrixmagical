# Skill: repository inspection

## Trigger
Use before modifying an unfamiliar area, continuing work from another session, or changing a cross-layer feature.

## Inputs
Repository/branch, task objective, known constraints, relevant PRs or commits.

## Steps
1. Confirm current branch, base/head commits, open PRs and active CI.
2. Read the owning screen/service/domain contract, native adapter and tests.
3. Trace lifecycle and data ownership from UI to native boundary.
4. Identify callers, shared state owners, coordinate spaces, permissions and side effects.
5. Record only verified findings and smallest safe change.

## Outputs
Architecture map, exact paths/symbols, public contracts, risks and proposed acceptance checks.

## Validation
Do not infer code from filenames. Fetch/read the implementation and cite commit/path evidence in the handoff.
