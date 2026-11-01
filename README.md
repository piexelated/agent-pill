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

| Pill | When |
|---|---|
| <img src="docs/images/working.png" alt="Working pill showing 4" height="30"> | Agents are running and nothing needs you. |
| <img src="docs/images/approval.png" alt="Approval pill showing 4" height="30"> | A thread is waiting for your approval. |
| <img src="docs/images/input.png" alt="Input pill showing 4" height="30"> | A thread is waiting for your answer. |
| <img src="docs/images/out-of-date.png" alt="Out of date pill" height="30"> | The plugin can't read T3 Code's state. The tooltip has the error. |

The count is active threads plus their subagents. Hover for each thread's status. The pill hides when nothing is running.

## Install

Requires Noctalia 5 and `sqlite3` on your `PATH`.

```sh
noctalia msg plugins source add agent-pill git https://github.com/piexelated/agent-pill
noctalia msg plugins enable piexelated/agent-pill
```

Add Agent Pill to a bar in Noctalia's settings. For the black capsule shown above, define the widget in `config.toml` and put `t3_agents` in a bar section:

```toml
[widget.t3_agents]
type = "piexelated/agent-pill:agents"
capsule_fill = "#000000"
```

## How it works?

Every 2 seconds the widget runs one read-only query on `~/.t3/userdata/statev2.sqlite`. Works for now 

## License

MIT. Not affiliated with T3 Code or Noctalia; the T3 mark belongs to its owners.
