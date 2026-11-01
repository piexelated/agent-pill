local POLL_INTERVAL_MS = 2000
local LOGO_PATH = "t3-logo.svg"
local LOGO_SIZE_PX = 18
local MAX_TOOLTIP_ROWS = 8
local UNAVAILABLE_LABEL = "!"

local T3_USERDATA_DIR = noctalia.expandPath("~/.t3/userdata")
local SERVER_RUNTIME_PATH = T3_USERDATA_DIR .. "/server-runtime.json"
local STATE_DATABASE_PATH = T3_USERDATA_DIR .. "/statev2.sqlite"

-- The status list mirrors how the T3 Code server decides a subagent is still live.
local WORKING_SUBAGENTS_QUERY = [[
  SELECT
    COALESCE(NULLIF(json_extract(subagent.payload_json, '$.title'), ''), 'Subagent') AS title,
    thread.title AS thread
  FROM orchestration_v2_projection_subagents AS subagent
  JOIN orchestration_v2_projection_threads AS thread ON thread.thread_id = subagent.thread_id
  WHERE subagent.status IN ('pending', 'running', 'waiting')
    AND thread.deleted_at IS NULL
  ORDER BY subagent.started_at
]]

local pollInFlight = false
local renderedState = nil

local function isT3ServerRunning()
  local runtimeJson = noctalia.readFile(SERVER_RUNTIME_PATH)
  if not runtimeJson then
    return false
  end
  local runtime = noctalia.json.decode(runtimeJson)
  if not runtime or not runtime.pid then
    return false
  end
  return noctalia.readFile(string.format("/proc/%d/comm", runtime.pid)) ~= nil
end

local function tooltipRows(subagents)
  local rows = {}
  for index = 1, math.min(#subagents, MAX_TOOLTIP_ROWS) do
    table.insert(rows, { key = subagents[index].title, value = subagents[index].thread })
  end
  local hiddenCount = #subagents - MAX_TOOLTIP_ROWS
  if hiddenCount > 0 then
    table.insert(rows, { key = string.format("+%d more", hiddenCount), value = "" })
  end
  return rows
end

local function showPill(text, color, tooltip)
  barWidget.setImage(LOGO_PATH, false, LOGO_SIZE_PX)
  barWidget.setText(text)
  barWidget.setColor(color)
  barWidget.setTooltip(tooltip)
  barWidget.setVisible(true)
end

local function renderState(state)
  if state.key == renderedState then
    return
  end
  renderedState = state.key

  if state.kind == "idle" then
    barWidget.setVisible(false)
  elseif state.kind == "working" then
    showPill(tostring(#state.subagents), "on_surface", tooltipRows(state.subagents))
  else
    noctalia.log("cannot read T3 Code state: " .. state.reason)
    showPill(UNAVAILABLE_LABEL, "error", state.reason)
  end
end

local function idleState()
  return { kind = "idle", key = "idle" }
end

local function unavailableState(reason)
  return { kind = "unavailable", key = "unavailable:" .. reason, reason = reason }
end

local function stateFromQueryResult(result)
  if result.exitCode ~= 0 or result.timedOut then
    local reason = noctalia.string.trim(result.stderr)
    return unavailableState(reason ~= "" and reason or "sqlite3 failed")
  end

  local output = noctalia.string.trim(result.stdout)
  if output == "" then
    return idleState()
  end

  local subagents, decodeError = noctalia.json.decode(output)
  if not subagents then
    return unavailableState(decodeError)
  end
  return { kind = "working", key = "working:" .. output, subagents = subagents }
end

local function pollWorkingSubagents()
  pollInFlight = true
  local started = noctalia.runAsync({
    "sqlite3",
    "-readonly",
    "-json",
    "-cmd",
    ".timeout 1000",
    STATE_DATABASE_PATH,
    WORKING_SUBAGENTS_QUERY,
  }, function(result)
    pollInFlight = false
    renderState(stateFromQueryResult(result))
  end)

  if not started then
    pollInFlight = false
    renderState(unavailableState("sqlite3 not found"))
  end
end

noctalia.setUpdateInterval(POLL_INTERVAL_MS)

function update()
  if pollInFlight then
    return
  end
  if not isT3ServerRunning() then
    renderState(idleState())
    return
  end
  pollWorkingSubagents()
end
