# Skill: independent review and safety

## Trigger
Native FFI, camera/microphone, filesystem, network, security-sensitive code, substantial diffs or consequential actions.

## Inputs
Diff, architecture contract, threat model, permissions and external side effects.

## Steps
1. Review independently from the writer's assumptions.
2. Check ownership, disposal, cancellation, stale callbacks and error paths.
3. Check bounds, finite values, coordinate spaces, ABI and data lifetime at FFI boundaries.
4. Check least privilege, secret redaction and user-data handling.
5. Classify findings as blocker/high/medium/low with file/line and reproducible rationale.
6. Require explicit approval for destructive/external actions and merge/deploy unless clearly authorized.

## Outputs
Prioritized findings, recommendation, alternatives and confidence.

## Validation
Review is read-only. Do not claim tests were run unless the reviewer actually ran them.
