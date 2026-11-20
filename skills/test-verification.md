# Skill: test and build verification

## Trigger
Any claim that code works, CI is green, a package is ready or a feature is complete.

## Inputs
Changed paths, target platforms, acceptance criteria, available test/device environments.

## Steps
1. Map changed code to unit, integration, native, build/package and device tests.
2. Run the narrowest relevant tests first, then the full required CI workflow.
3. Record exact run ID, commit SHA, job/step status and artifact presence.
4. Separate analyzer success, unit-test success, APK/AAB build, ABI inspection and device behavior.
5. Report blocked/unavailable tests and risks without converting them to successes.

## Outputs
Evidence matrix and unresolved acceptance gates.

## Validation
Every reported result must match an observed command or CI result. A test not run is pending, not passed.
