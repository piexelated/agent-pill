# Agent Pill

A [Noctalia](https://noctalia.dev) bar pill that shows how many T3 Code agents are working. It follows the design of T3 Code's iOS Dynamic Island: a bare T3 mark tinted by phase, a bold count, and the dashed Working glyph.

| Phase | Tint | Shows |
|---|---|---|
| Working | sky | count and dashed glyph |
| Approval needed | amber | count and `Approval` |
| Waiting for input | indigo | count and `Input` |
| Can't read T3 Code's state | grey | `Out of date` |

The count is every active thread plus its live subagents. Hover the pill to see each thread and its status. The pill hides when nothing is working or T3 Code isn't running.

Not affiliated with T3 Code or Noctalia. The T3 mark belongs to its owners.

## Install

Needs `sqlite3` on `PATH` and Noctalia 5.

```toml
[plugins]
enabled = ["piexelated/agent-pill"]

[[plugins.source]]
name = "agent-pill"
kind = "path"
location = "~/Projects/side-projects/agent-pill"
enabled = true

[widget.t3_agents]
type = "piexelated/agent-pill:agents"
capsule_fill = "#000000"
```

Then add `t3_agents` to a bar section.

## How it works

Every 2 seconds the widget runs a read-only query on `~/.t3/userdata/statev2.sqlite`, using the same rules the T3 Code server uses to resolve a thread's phase.

This database is T3 Code's private schema, so an update can break the query. When that happens the pill shows `Out of date` with the SQLite error in its tooltip.
