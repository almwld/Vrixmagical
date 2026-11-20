# VRIX Magical — Unified AI Delegation Protocol

This is the repository-wide operating contract for coding agents, assistants and human-led automation. Project-specific instructions may narrow it, but must not contradict it.

## 1. One orchestrator, one writer

- One **Orchestrator** owns the task: inspect, decompose, choose skills/playbooks, assign work, reconcile results and report evidence.
- One **Writer** owns a given working tree/branch at a time. The orchestrator may also be the writer.
- Specialists are invoked only when a task materially benefits from domain expertise. Prefer a skill/playbook and shared tools over spawning an agent for every small step.
- A **Reviewer** is read-only and challenges correctness, safety and scope. A **Verifier** independently runs the acceptance checks. One person/agent may fill more than one role, but review must be independent of the author.
- Parallel implementation is allowed only in separate branches/worktrees with explicit ownership and a planned integration point.

## 2. Delegation contract

Every delegated task must carry:
- objective and non-goals;
- exact repository, branch/commit and relevant paths;
- constraints, public contracts and safety boundaries;
- inputs and expected artifacts;
- tests/acceptance criteria and how to report evidence;
- known risks, unresolved questions and rollback path.

A specialist returns: changes made (or review findings), paths/commit, commands/tests actually run, results, remaining risks, alternatives and confidence. Never claim execution that did not occur.

## 3. Skills and playbooks

- **Skills** are reusable domain knowledge, tools and validation rules.
- **Playbooks** are ordered workflows that compose skills into a deliverable.
- The registry in `.ai/registry.json` is canonical. Each entry points to a maintained file and declares inputs, outputs and validation.
- The orchestrator chooses one playbook for the main task and only the necessary supporting skills. Avoid duplicate or overlapping autonomous agents.

## 4. Shared toolbox and permissions

Use the narrowest available tool/API for the task. Validate inputs at dispatch, preserve structured outputs, redact secrets and user data from logs, and propagate cancellation to in-flight work.

Permission classes:
1. **Read** — inspect files, issues, logs, docs and test results.
2. **Write** — edit files on the assigned branch and run local checks.
3. **External side effect** — publish, deploy, delete, purchase, alter credentials/permissions or merge. Require explicit human approval unless the human has clearly authorized that exact action in the current task.

Never bypass a sandbox or permission boundary to make a task easier. Never replay a side-effecting action automatically after an uncertain result.

## 5. Memory and durable handoffs

The `.ai/` directory stores concise project memory:
- `.ai/PROJECT_STATE.md`: current architecture, active branches/PRs, verified status and open gates.
- `.ai/decisions.md`: durable decisions with date, rationale and consequences.
- `.ai/handoffs/current.md`: current task, owner, branch, next action and acceptance gates.
- `.ai/registry.json`: skill/playbook index.

Record facts, decisions, test evidence, unresolved risks and links. Do **not** store hidden chain-of-thought, secrets, tokens, private user data or raw agent transcripts. Replace stale status rather than appending contradictory claims. Update handoff/state at task boundaries.

## 6. Bounded collaboration

- No recursive or indefinite agent-to-agent delegation.
- Default maximum: one specialist consultation and one rebuttal per decision. If disagreement remains, present both positions to the human.
- Cancel obsolete work and its subprocesses; do not leave background work silently running.
- Ask the human only for information or approval that materially changes the outcome.

## 7. Completion standard

A task is complete only when:
1. implementation matches the inspected architecture and preserves public contracts;
2. relevant unit/integration tests pass;
3. build/package checks pass for affected targets;
4. independent review has no unresolved blocking finding;
5. docs and durable memory reflect the actual state;
6. device/runtime acceptance is explicitly marked pending unless performed.

**Code present ≠ tested ≠ built ≠ device-verified ≠ production-ready.** Report these states separately.
