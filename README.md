# Agent Pill

A [Noctalia](https://noctalia.dev) bar pill that shows how many T3 Code subagents are working. Hover it to see each subagent and its thread.

The pill hides when nothing is working or T3 Code isn't running. It shows `!` when it can't read T3 Code's state.

Not affiliated with T3 Code or Noctalia. The T3 logo belongs to its owners.

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

[widget.t3_subagents]
type = "piexelated/agent-pill:subagents"
```

Then add `t3_subagents` to a bar section.

## How it works

Every 2 seconds the widget runs a read-only query on `~/.t3/userdata/statev2.sqlite`. It counts subagents with status `pending`, `running` or `waiting`, the same statuses the T3 Code server treats as live.

This database is T3 Code's private schema, so an update can break the query. When that happens the pill shows `!` with the SQLite error in its tooltip.
