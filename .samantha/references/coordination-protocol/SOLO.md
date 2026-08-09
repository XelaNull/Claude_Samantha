# Solo protocol (stub)

Star mode has the full novel under `README.md`. **Solo** is the default when work fits one session.

| | Solo | Star |
|--|------|------|
| Entry skill | `coordinate-solo` | `coordinate-star` |
| Workers | In-session subagents | Peer processes + mailbox |
| Bus | Optional local only | Required STAR files |
| Wake filter | N/A (no shared hub) | PROTOCOL 1.2.1 addressed filter |

Shared substrate: skill **`coordinate`**. Install the Reference Pack once; choose mode at arm time.
