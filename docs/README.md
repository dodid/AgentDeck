# Project Docs

This folder is the maintained documentation hub for the ClawChat monorepo.

## Purpose

These docs are meant to reduce drift during autonomous coding work across:

- `apps/ios/` — the iOS client
- `integrations/openclaw/` — the OpenClaw channel plugin

Older design documents in this folder are retained for context and may be stale.
The files in `docs/` should be kept aligned with the current source code.

## Source of truth order

When documents disagree, use this order:

1. Current source code
2. `docs/ARCHITECTURE_TRUTH.md`
3. `docs/WORKING_CONVENTIONS.md`
4. Older design/spec files in the repo root

## Core docs

- `ARCHITECTURE_TRUTH.md` — current implementation-oriented architecture map
- `WORKING_CONVENTIONS.md` — coding and change-management guardrails
- `TASK_WORKFLOW.md` — default execution loop for feature and bug work
- `MAINTENANCE_AUTOMATION.md` — scheduled upstream tests, repair-PR workflow, and release gates
- `PUBLIC_REPOSITORY_SETUP.md` — GitHub and Xcode Cloud settings required after the first push

## Maintenance rule

When code and docs disagree, update the docs in this folder as part of the task or note the mismatch explicitly.
