# Fabric M-LSD Plugin Guidance

## Scope and architecture

- This repository owns the reusable M-LSD structural-line package and the Fabric plug-in that adapts it to Fabric.
- The Fabric plug-in must be self-contained. It must not import, link, reference, or require MESS or any MESS-owned target at build time or runtime.
- Keep the core package independent of Fabric, Satin, and application-specific types.
- Keep Fabric graph scheduling, port conversion, and rendering in the plug-in layer.
- Do not duplicate M-LSD inference or decoding implementations in MESS and Fabric. The root Swift package here is the canonical implementation; any later MESS adoption must depend in this direction, never the reverse.
- M-LSD outputs independent scored segments. Do not imply shared junction topology, depth, camera pose, or temporal tracking.

## Engineering constraints

- Use Swift 5.9 and target macOS 15 or later.
- Do not add third-party frameworks without explicit user approval.
- Prefer Apple frameworks and Metal for realtime image work; do not introduce Core Image into the inference or render path.
- Preserve the official 512-by-512 stretch behavior and fixed displacement-length criterion unless an explicitly named experiment changes them.
- Retain the pinned model, Apache-2.0 license, provenance, and artifact hash validation.
- Use descriptive names, typed Fabric ports, stable registration keys, and one file per Node class.
- Keep inference separate from presentation. Analysis outputs reusable line data; rendering belongs to a separate node.
- Respect `FabricImage` presentation size and texture transform at the Fabric boundary.
- Do not block Fabric's render command buffer waiting for Core ML inference. Use bounded latest-pending asynchronous analysis and publish completed results through a safe Fabric invalidation path.

## Testing and verification

- Use the narrowest meaningful checks for each milestone.
- Keep CPU-only reference verification deterministic. Production `.cpuAndGPU` results may vary slightly near confidence thresholds.
- Preserve model and license SHA-256 checks.
- Do not add tests that merely restate implementation constants without an independent fixture or external contract.
- After focused checks pass, broaden verification only when a changed integration boundary justifies it.

## Long-running task recovery

Use this workflow when requested or when work spans multiple implementation stages.

- Before implementation, create or update `docs/internal/handoffs/<task-slug>.md` from the established handoff format.
- Keep the handoff concise: record decisions, paths, state, commands, outcomes, risks, and the next exact action.
- Work on one bounded milestone at a time and checkpoint it before starting another.
- Update the handoff after a coherent stage, after verification, after an authorized commit, before an expensive build, before the next milestone, and before stopping due to constraints.
- Do not update it after every small edit.
- Commits require explicit user authorization.
- On resume, read the handoff, then inspect scoped `git status`, `git diff`, and recent commits before continuing.
- Preserve unrelated dirty work in this repository and in connected repositories.
- For an asynchronous command with no new output, wait 30–60 seconds between polls and stop after three unchanged polls.
