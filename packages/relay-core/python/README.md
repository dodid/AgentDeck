# r2-relay-core (Python)

Host-neutral Python transport primitives for the AgentDeck, OpenClaw, and Hermes R2 relay.

The package provides:

- keyspace helpers
- checkpoint helpers
- object-store interface
- transport logic for head/message traversal and CAS append

Host-specific lifecycle and event mapping remain in their platform integrations.
