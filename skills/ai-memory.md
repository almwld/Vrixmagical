# Skill: delegation and durable memory

## Trigger
Agent orchestration, delegation, skills/playbooks registry, cross-session continuation or handoff.

## Inputs
Objective, current branch, task owner, acceptance gates and known decisions.

## Steps
1. Read root `AI_TEAM.md` and `.ai/PROJECT_STATE.md`.
2. Select one orchestrator and one writer for the working branch.
3. Choose a registry-backed playbook and only relevant skills.
4. Delegate bounded work with objective, constraints, inputs, outputs and validation.
5. Keep reviewer read-only; verifier reports actual commands/results.
6. Update current handoff, project state and decisions at task boundaries.
7. Remove stale status instead of accumulating contradictory memory.

## Outputs
Updated handoff, decision record and valid registry entries.

## Validation
Run `python3 tool/validate_ai_handoff.py`. Do not store secrets, private data, raw transcripts or hidden reasoning.
