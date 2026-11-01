<p align="center">
  <img src="docs/images/bar.png" alt="Noctalia bar with Agent Pill between the clock and the media pill, showing 4 agents working" width="680">
</p>

<h1 align="center">Agent Pill</h1>

<p align="center">How many T3 Code agents are working, right on your Noctalia bar.</p>

<p align="center">
  <img src="https://img.shields.io/badge/Noctalia-5-7dd3fc?style=flat-square&labelColor=000000" alt="Noctalia 5">
  <img src="https://img.shields.io/badge/plugin_API-24-a5b4fc?style=flat-square&labelColor=000000" alt="Plugin API 24">
  <img src="https://img.shields.io/badge/license-MIT-fcd34d?style=flat-square&labelColor=000000" alt="MIT license">
</p>

## What it shows

The pill copies the design of T3 Code's iOS Dynamic Island: a black capsule, a bare T3 mark tinted by phase, and a bold count.

| Pill | Phase | When |
|---|---|---|
| <img src="docs/images/working.png" alt="Working pill showing 4" height="30"> | Working | Agents are running and nothing needs you. |
| <img src="docs/images/approval.png" alt="Approval pill showing 4" height="30"> | Approval | A thread is waiting for your approval. |
| <img src="docs/images/input.png" alt="Input pill showing 4" height="30"> | Input | A thread is waiting for your answer. |
| <img src="docs/images/out-of-date.png" alt="Out of date pill" height="30"> | Out of date | The plugin can't read T3 Code's state. The tooltip has the error. |

The number is every active thread plus its live subagents, so 3 threads and 1 subagent show `4`. Hover the pill to see each thread and its status.

The pill hides when nothing is working or T3 Code isn't running.

## Install

You need Noctalia 5 and `sqlite3` on your `PATH`.

```sh
git clone https://github.com/piexelated/agent-pill ~/Projects/agent-pill
```

Add this to your Noctalia `config.toml`:

```toml
[plugins]
enabled = ["piexelated/agent-pill"]

[[plugins.source]]
name = "agent-pill"
kind = "path"
location = "~/Projects/agent-pill"
enabled = true

[widget.t3_agents]
type = "piexelated/agent-pill:agents"
capsule_fill = "#000000"
```

Then add `t3_agents` to a bar section, such as `start = ["launcher", "t3_agents"]`.

## How it works

Every 2 seconds the widget runs one read-only query on `~/.t3/userdata/statev2.sqlite`. It needs no token and never writes to the database. The phase rules match the ones the T3 Code server uses.

That database is T3 Code's private schema, so an update can break the query. If it does, the pill shows `Out of date` with SQLite's error in the tooltip.

## License

The code is MIT. The T3 mark belongs to its owners, and this project isn't affiliated with T3 Code or Noctalia.
