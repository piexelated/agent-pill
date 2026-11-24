local Pill = require("./pill.luau")

local POLL_INTERVAL_MS = 2000

local ORCA_CONFIG_DIR = noctalia.expandPath("~/.config/orca")
local ORCA_RUNTIME_PATH = ORCA_CONFIG_DIR .. "/orca-runtime.json"
-- Orca registers its CLI here on Linux; the bar's PATH usually lacks it.
local ORCA_CLI_SHIM_PATH = ORCA_CONFIG_DIR .. "/linux-orca-cli-shim/orca"

-- Orca folds subagents into their lead agent and has one "needs you" state for permission
-- prompts and questions alike, so waiting and blocked both show as approval.
local PHASE_BY_ORCA_STATE = {
  working = "working",
  waiting = "approval",
  blocked = "approval",
}

-- An agent whose turn ended but which still has a background task running reports working with
-- this mode. Orca shows it as monitoring, not working, so it does not count.
local MONITORING_WORKING_MODE = "monitoring"

local pill = Pill.new({
  name = "Orca",
  marks = {
    working = "marks/orca-working.svg",
    approval = "marks/orca-approval.svg",
    stale = "marks/orca-stale.svg",
  },
})
local pollInFlight = false

local function isOrcaRunning()
  local runtimeJson = noctalia.readFile(ORCA_RUNTIME_PATH)
  if not runtimeJson then
    return false
  end
  local runtime = noctalia.json.decode(runtimeJson)
  if not runtime or not runtime.pid then
    return false
  end
  return noctalia.readFile(string.format("/proc/%d/comm", runtime.pid)) ~= nil
end

local function orcaCliPath()
  if noctalia.readFile(ORCA_CLI_SHIM_PATH) then
    return ORCA_CLI_SHIM_PATH
  end
  return "orca"
end

local function agentTitle(agent, worktree)
  return agent.conversationName or agent.displayName or agent.taskTitle or worktree.displayName or agent.agentType or "Agent"
end

local function agentPhase(agent)
  if agent.workingMode == MONITORING_WORKING_MODE then
    return nil
  end
  return PHASE_BY_ORCA_STATE[agent.state]
end

local function activeAgents(worktrees)
  local agents = {}
  for _, worktree in worktrees do
    for _, agent in worktree.agents or {} do
      local phase = agentPhase(agent)
      if phase then
        table.insert(agents, { title = agentTitle(agent, worktree), phase = phase })
      end
    end
  end
  table.sort(agents, function(left, right)
    if (left.phase == "working") ~= (right.phase == "working") then
      return right.phase == "working"
    end
    return left.title < right.title
  end)
  return agents
end

local function stateFromCliResult(result)
  if result.exitCode ~= 0 or result.timedOut then
    local reason = noctalia.string.trim(result.stderr)
    return Pill.stale(reason ~= "" and reason or "orca worktree ps failed")
  end

  local response, decodeError = noctalia.json.decode(result.stdout)
  if not response then
    return Pill.stale(decodeError)
  end
  if not response.ok or not response.result or not response.result.worktrees then
    return Pill.stale("orca worktree ps returned no worktrees")
  end
  return Pill.active(activeAgents(response.result.worktrees))
end

local function pollActiveAgents()
  pollInFlight = true
  -- agent list leaves out workingMode, so the agents come from the worktree summary.
  local started = noctalia.runAsync({ orcaCliPath(), "worktree", "ps", "--json" }, function(result)
    pollInFlight = false
    pill.render(stateFromCliResult(result))
  end)

  if not started then
    pollInFlight = false
    pill.render(Pill.stale("orca CLI not found"))
  end
end

noctalia.setUpdateInterval(POLL_INTERVAL_MS)

function update()
  if pollInFlight then
    return
  end
  if not isOrcaRunning() then
    pill.render(Pill.idle())
    return
  end
  pollActiveAgents()
end
