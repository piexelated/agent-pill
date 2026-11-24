<p align="center">
  <img src="docs/images/bar.png" alt="Noctalia bar with the T3 Code pill showing 4 agents and the Orca pill showing 2, next to the clock" width="680">
</p>

<h1 align="center">Agent Pill</h1>

<p align="center">How many T3 Code and Orca agents are working, right on your Noctalia bar.</p>

<p align="center">
  <img src="https://img.shields.io/badge/Noctalia-5-7dd3fc?style=flat-square&labelColor=000000" alt="Noctalia 5">
  <img src="https://img.shields.io/badge/plugin_API-24-a5b4fc?style=flat-square&labelColor=000000" alt="Plugin API 24">
  <img src="https://img.shields.io/badge/license-MIT-fcd34d?style=flat-square&labelColor=000000" alt="MIT license">
</p>

## What it shows

Each app gets its own pill. A pill hides when nothing is running.

| T3 Code | Orca | When |
|---|---|---|
| <img src="docs/images/working.png" alt="T3 Code working pill showing 4" height="30"> | <img src="docs/images/orca-working.png" alt="Orca working pill showing 4" height="30"> | Agents are running and nothing needs you. |
| <img src="docs/images/approval.png" alt="T3 Code approval pill showing 4" height="30"> | <img src="docs/images/orca-approval.png" alt="Orca approval pill showing 4" height="30"> | An agent is waiting for your approval. |
| <img src="docs/images/input.png" alt="T3 Code input pill showing 4" height="30"> | <img src="docs/images/orca-approval.png" alt="Orca approval pill showing 4" height="30"> | A thread is waiting for your answer. |
| <img src="docs/images/out-of-date.png" alt="T3 Code out of date pill" height="30"> | <img src="docs/images/orca-out-of-date.png" alt="Orca out of date pill" height="30"> | The plugin can't read the app's state. The tooltip has the error. |

The T3 Code count is the active threads in your thread list. Subagents, side chats and workflow steps don't count, but a subagent's approval request shows on its thread.

The Orca count is the agents that are working or waiting on you. Orca reports permission prompts and questions the same way, so both show as Approval.

Hover a pill for each agent's status.

## Install

Requires Noctalia 5. The T3 Code pill needs `sqlite3` on your `PATH`. The Orca pill needs the Orca CLI, which Orca registers itself.

```sh
noctalia msg plugins source add agent-pill git https://github.com/piexelated/agent-pill
noctalia msg plugins enable piexelated/agent-pill
```

Add the pills you want to a bar in Noctalia's settings. For the black capsules shown above, define the widgets in `config.toml` and put `t3_agents` and `orca_agents` in a bar section:

```toml
[widget.t3_agents]
type = "piexelated/agent-pill:agents"
capsule_fill = "#000000"

[widget.orca_agents]
type = "piexelated/agent-pill:orca"
capsule_fill = "#000000"
```

## How it works

Each pill polls every 2 seconds, and only while its app is running.

- T3 Code: one read-only query on `~/.t3/userdata/statev2.sqlite`. That schema is internal to T3 Code, so an update can break the pill.
- Orca: `orca agent list --json`.

## License

MIT. Not affiliated with T3 Code, Orca or Noctalia. Their marks belong to their owners.
