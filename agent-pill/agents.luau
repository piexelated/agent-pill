local POLL_INTERVAL_MS = 2000
local MARK_WIDTH_PX = 21
local MARK_HEIGHT_PX = 14
local COUNT_FONT_SIZE = 13
local LABEL_FONT_SIZE = 12
local WORKING_GLYPH = "circle-dashed"
local WORKING_GLYPH_SIZE_PX = 14
local ROW_GAP_PX = 6
local MAX_TOOLTIP_ROWS = 8

local T3_USERDATA_DIR = noctalia.expandPath("~/.t3/userdata")
local SERVER_RUNTIME_PATH = T3_USERDATA_DIR .. "/server-runtime.json"
local STATE_DATABASE_PATH = T3_USERDATA_DIR .. "/statev2.sqlite"

-- Tints and labels follow T3 Code's AgentActivity live activity.
local PHASE_STYLES = {
  working = { mark = "marks/running.svg", tint = "#7dd3fc", status = "Working" },
  approval = { mark = "marks/approval.svg", tint = "#fcd34d", label = "Approval", status = "Approval needed" },
  input = { mark = "marks/input.svg", tint = "#a5b4fc", label = "Input", status = "Waiting for input" },
  stale = { mark = "marks/stale.svg", tint = "#a1a1aa", label = "Out of date" },
}

-- Mirrors how the T3 Code server resolves a thread's phase. Subagent threads count
-- through their root thread, and attention rows sort first.
local ACTIVE_AGENTS_QUERY = [[
  WITH live_subagents AS (
    SELECT
      CASE json_extract(owner.payload_json, '$.lineage.relationshipToParent')
        WHEN 'subagent' THEN json_extract(owner.payload_json, '$.lineage.rootThreadId')
        ELSE subagent.thread_id
      END AS thread_id,
      COUNT(*) AS count
    FROM orchestration_v2_projection_subagents AS subagent
    JOIN orchestration_v2_projection_threads AS owner ON owner.thread_id = subagent.thread_id
    WHERE subagent.status IN ('pending', 'running', 'waiting')
    GROUP BY 1
  ),
  active_threads AS (
    SELECT thread_id FROM orchestration_v2_projection_runs
    WHERE status IN ('preparing', 'starting', 'running', 'waiting')
    UNION
    SELECT thread_id FROM live_subagents
  ),
  pending_requests AS (
    SELECT thread_id, kind FROM orchestration_v2_projection_runtime_requests
    WHERE status = 'pending' AND kind <> 'auth_refresh'
  )
  SELECT
    thread.title AS title,
    COALESCE(live_subagents.count, 0) AS subagents,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM pending_requests AS request
        WHERE request.thread_id = thread.thread_id AND request.kind = 'user_input'
      ) THEN 'input'
      WHEN EXISTS (
        SELECT 1 FROM pending_requests AS request
        WHERE request.thread_id = thread.thread_id
      ) THEN 'approval'
      ELSE 'working'
    END AS phase
  FROM active_threads
  JOIN orchestration_v2_projection_threads AS thread USING (thread_id)
  LEFT JOIN live_subagents USING (thread_id)
  WHERE thread.deleted_at IS NULL
    AND json_extract(thread.payload_json, '$.lineage.relationshipToParent') IS NOT 'subagent'
  ORDER BY phase = 'working', thread.title
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

local function activeAgentCount(threads)
  local count = 0
  for _, thread in threads do
    count += 1 + thread.subagents
  end
  return count
end

local function attentionCount(threads)
  local count = 0
  for _, thread in threads do
    if thread.phase ~= "working" then
      count += 1
    end
  end
  return count
end

local function summaryLabel(threads)
  local activeCount = activeAgentCount(threads)
  local summary = string.format("%d active %s", activeCount, activeCount == 1 and "agent" or "agents")
  local needingAttention = attentionCount(threads)
  if needingAttention == 0 then
    return summary
  end
  return string.format("%s · %d %s attention", summary, needingAttention, needingAttention == 1 and "needs" or "need")
end

local function threadStatus(thread)
  local status = PHASE_STYLES[thread.phase].status
  if thread.subagents == 0 then
    return status
  end
  return string.format("%s · %d %s", status, thread.subagents, thread.subagents == 1 and "subagent" or "subagents")
end

local function tooltipRows(threads)
  local rows = { { key = "T3 Code", value = summaryLabel(threads) } }
  for index = 1, math.min(#threads, MAX_TOOLTIP_ROWS) do
    table.insert(rows, { key = threads[index].title, value = threadStatus(threads[index]) })
  end
  local hiddenCount = #threads - MAX_TOOLTIP_ROWS
  if hiddenCount > 0 then
    table.insert(rows, { key = "More", value = string.format("+%d", hiddenCount) })
  end
  return rows
end

local function pillContents(style, count)
  local contents = {
    ui.image({ path = style.mark, width = MARK_WIDTH_PX, height = MARK_HEIGHT_PX, fit = "contain" }),
  }
  if count then
    table.insert(contents, ui.label({
      text = tostring(count),
      fontSize = COUNT_FONT_SIZE,
      fontWeight = "bold",
      color = style.tint,
    }))
  end
  if style.label then
    table.insert(contents, ui.label({
      text = style.label,
      fontSize = LABEL_FONT_SIZE,
      fontWeight = "semibold",
      color = style.tint,
    }))
  else
    table.insert(contents, ui.glyph({ name = WORKING_GLYPH, size = WORKING_GLYPH_SIZE_PX, color = style.tint }))
  end
  return contents
end

local function showPill(style, count, tooltip)
  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = ROW_GAP_PX, align = "center" }, pillContents(style, count)))
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
  elseif state.kind == "active" then
    showPill(PHASE_STYLES[state.threads[1].phase], activeAgentCount(state.threads), tooltipRows(state.threads))
  else
    noctalia.log("cannot read T3 Code state: " .. state.reason)
    showPill(PHASE_STYLES.stale, nil, state.reason)
  end
end

local function idleState()
  return { kind = "idle", key = "idle" }
end

local function staleState(reason)
  return { kind = "stale", key = "stale:" .. reason, reason = reason }
end

local function stateFromQueryResult(result)
  if result.exitCode ~= 0 or result.timedOut then
    local reason = noctalia.string.trim(result.stderr)
    return staleState(reason ~= "" and reason or "sqlite3 failed")
  end

  local output = noctalia.string.trim(result.stdout)
  if output == "" then
    return idleState()
  end

  local threads, decodeError = noctalia.json.decode(output)
  if not threads then
    return staleState(decodeError)
  end
  return { kind = "active", key = "active:" .. output, threads = threads }
end

local function pollActiveAgents()
  pollInFlight = true
  local started = noctalia.runAsync({
    "sqlite3",
    "-readonly",
    "-json",
    "-cmd",
    ".timeout 1000",
    STATE_DATABASE_PATH,
    ACTIVE_AGENTS_QUERY,
  }, function(result)
    pollInFlight = false
    renderState(stateFromQueryResult(result))
  end)

  if not started then
    pollInFlight = false
    renderState(staleState("sqlite3 not found"))
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
  pollActiveAgents()
end
