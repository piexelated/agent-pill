local Pill = require("./pill.luau")

local POLL_INTERVAL_MS = 2000

local ORCA_CONFIG_DIR = noctalia.expandPath("~/.config/orca")
local ORCA_RUNTIME_PATH = ORCA_CONFIG_DIR .. "/orca-runtime.json"
-- Orca registers its CLI here on Linux; the bar's PATH usually lacks it.
local ORCA_CLI_SHIM_PATH = ORCA_CONFIG_DIR .. "/linux-orca-cli-shim/orca"

-- worktree ps only covers the runtime it asks. It lists each paired server it left out as
-- hostId "runtime:<environment id>" with selector "--environment <name>".
local PAIRED_SERVER_HOST_ID_PREFIX = "runtime:"
local ENVIRONMENT_SELECTOR_PREFIX = "--environment "

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

local function agentTitle(agent, worktree, serverName)
  local title = agent.conversationName or agent.displayName or agent.taskTitle or worktree.displayName or agent.agentType or "Agent"
  if serverName then
    return string.format("%s · %s", title, serverName)
  end
  return title
end

local function agentPhase(agent)
  if agent.workingMode == MONITORING_WORKING_MODE then
    return nil
  end
  return PHASE_BY_ORCA_STATE[agent.state]
end

local function collectActiveAgents(into, worktrees, serverName)
  for _, worktree in worktrees do
    for _, agent in worktree.agents or {} do
      local phase = agentPhase(agent)
      if phase then
        table.insert(into, { title = agentTitle(agent, worktree, serverName), phase = phase })
      end
    end
  end
end

local function sortedByAttention(agents)
  table.sort(agents, function(left, right)
    if (left.phase == "working") ~= (right.phase == "working") then
      return right.phase == "working"
    end
    return left.title < right.title
  end)
  return agents
end

local function worktreePsCommand(environmentId)
  -- agent list leaves out workingMode, so the agents come from the worktree summary.
  local command = { orcaCliPath(), "worktree", "ps", "--json" }
  if environmentId then
    table.insert(command, "--environment")
    table.insert(command, environmentId)
  end
  return command
end

-- Returns the worktree summary, or nil and why it could not be read.
local function decodeWorktreeSummary(result)
  if result.timedOut then
    return nil, "orca worktree ps timed out"
  end

  local response = noctalia.json.decode(result.stdout)
  if response and response.error and response.error.message then
    return nil, response.error.message
  end
  if result.exitCode ~= 0 then
    local reason = noctalia.string.trim(result.stderr)
    return nil, reason ~= "" and reason or "orca worktree ps failed"
  end
  if not response or not response.ok or not response.result or not response.result.worktrees then
    return nil, "orca worktree ps returned no worktrees"
  end
  return response.result
end

local function pairedServersLeftOut(hostScope)
  local servers = {}
  for _, omitted in (hostScope and hostScope.omittedHostSelectors) or {} do
    local hostId, selector = omitted.hostId or "", omitted.selector or ""
    if string.sub(hostId, 1, #PAIRED_SERVER_HOST_ID_PREFIX) == PAIRED_SERVER_HOST_ID_PREFIX then
      local environmentId = string.sub(hostId, #PAIRED_SERVER_HOST_ID_PREFIX + 1)
      local name = environmentId
      if string.sub(selector, 1, #ENVIRONMENT_SELECTOR_PREFIX) == ENVIRONMENT_SELECTOR_PREFIX then
        name = string.sub(selector, #ENVIRONMENT_SELECTOR_PREFIX + 1)
      end
      table.insert(servers, { environmentId = environmentId, name = name })
    end
  end
  return servers
end

local function finishPoll(state)
  pollInFlight = false
  pill.render(state)
end

-- A paired server that cannot be read is named in the tooltip instead of hiding the others.
local function pollPairedServers(localSummary)
  local agents = {}
  collectActiveAgents(agents, localSummary.worktrees, nil)

  local servers = pairedServersLeftOut(localSummary.hostScope)
  local unreachableServers = {}
  local pendingCount = #servers
  if pendingCount == 0 then
    finishPoll(Pill.active(sortedByAttention(agents)))
    return
  end

  local function settleServer()
    pendingCount -= 1
    if pendingCount > 0 then
      return
    end
    table.sort(unreachableServers)
    finishPoll(Pill.active(sortedByAttention(agents), unreachableServers))
  end

  for _, server in servers do
    local started = noctalia.runAsync(worktreePsCommand(server.environmentId), function(result)
      local summary = decodeWorktreeSummary(result)
      if summary then
        collectActiveAgents(agents, summary.worktrees, server.name)
      else
        table.insert(unreachableServers, server.name)
      end
      settleServer()
    end)
    if not started then
      table.insert(unreachableServers, server.name)
      settleServer()
    end
  end
end

local function pollActiveAgents()
  pollInFlight = true
  local started = noctalia.runAsync(worktreePsCommand(nil), function(result)
    local localSummary, failure = decodeWorktreeSummary(result)
    if not localSummary then
      finishPoll(Pill.stale(failure))
      return
    end
    pollPairedServers(localSummary)
  end)

  if not started then
    finishPoll(Pill.stale("orca CLI not found"))
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
