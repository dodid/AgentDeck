# r2-relay-core (Python)

Host-agnostic Python shared transport core for the ClawChat/OpenClaw/Hermes R2 relay.

This package is intended to hold reusable relay transport behavior below the host boundary:
- keyspace helpers
- checkpoint helpers
- object-store interface
- transport logic for head/message traversal and CAS append

It should not own host-specific Hermes adapter wiring or OpenClaw plugin lifecycle behavior.
