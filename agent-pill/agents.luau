local Pill = require("./pill.luau")

local POLL_INTERVAL_MS = 2000

local T3_USERDATA_DIR = noctalia.expandPath("~/.t3/userdata")
local SERVER_RUNTIME_PATH = T3_USERDATA_DIR .. "/server-runtime.json"
local STATE_DATABASE_PATH = T3_USERDATA_DIR .. "/statev2.sqlite"

-- Mirrors T3 Code's AgentActivity: one row per listed thread, so subagents, side chats and
-- workflow steps never count. A subagent's approval request or background work shows on its
-- root thread, and an approval outranks a question on the same thread.
local ACTIVE_THREADS_QUERY = [[
  WITH listed_threads AS (
    SELECT thread_id, title FROM orchestration_v2_projection_threads
    WHERE deleted_at IS NULL
      AND archived_at IS NULL
      AND json_extract(payload_json, '$.lineage.relationshipToParent') IS NOT 'subagent'
      AND json_extract(payload_json, '$.lineage.sideChat') IS NOT 1
      AND json_extract(payload_json, '$.lineage.workflowStep') IS NOT 1
  ),
  active_runs AS (
    SELECT thread_id FROM orchestration_v2_projection_runs
    WHERE status IN ('preparing', 'starting', 'running', 'waiting')
  ),
  background_subagents AS (
    SELECT
      CASE json_extract(owner.payload_json, '$.lineage.relationshipToParent')
        WHEN 'subagent' THEN json_extract(owner.payload_json, '$.lineage.rootThreadId')
        ELSE subagent.thread_id
      END AS thread_id
    FROM orchestration_v2_projection_subagents AS subagent
    JOIN orchestration_v2_projection_threads AS owner ON owner.thread_id = subagent.thread_id
    WHERE subagent.status IN ('pending', 'running', 'waiting')
  ),
  shown_requests AS (
    SELECT thread_id, kind FROM (
      SELECT thread_id, kind, ROW_NUMBER() OVER (
        PARTITION BY thread_id ORDER BY kind = 'user_input', created_at DESC
      ) AS rank
      FROM orchestration_v2_projection_runtime_requests
      WHERE status = 'pending'
    )
    WHERE rank = 1 AND kind <> 'auth_refresh'
  ),
  subagent_approvals AS (
    SELECT json_extract(child.payload_json, '$.lineage.rootThreadId') AS thread_id
    FROM shown_requests AS request
    JOIN orchestration_v2_projection_threads AS child ON child.thread_id = request.thread_id
    WHERE request.kind <> 'user_input'
      AND json_extract(child.payload_json, '$.lineage.relationshipToParent') = 'subagent'
      AND json_extract(child.payload_json, '$.creationSource') IS NOT 'provider'
      AND child.thread_id IN (SELECT thread_id FROM active_runs)
  )
  SELECT
    thread.title AS title,
    CASE
      WHEN request.kind = 'user_input' THEN 'input'
      WHEN request.kind IS NOT NULL THEN 'approval'
      WHEN thread.thread_id IN (SELECT thread_id FROM subagent_approvals) THEN 'approval'
      ELSE 'working'
    END AS phase
  FROM listed_threads AS thread
  LEFT JOIN shown_requests AS request USING (thread_id)
  WHERE request.kind IS NOT NULL
    OR thread.thread_id IN (SELECT thread_id FROM subagent_approvals)
    OR thread.thread_id IN (SELECT thread_id FROM active_runs)
    OR thread.thread_id IN (SELECT thread_id FROM background_subagents)
  ORDER BY phase = 'working', thread.title
]]

local pill = Pill.new({
  name = "T3 Code",
  marks = {
    working = "marks/t3-working.svg",
    approval = "marks/t3-approval.svg",
    input = "marks/t3-input.svg",
    stale = "marks/t3-stale.svg",
  },
})
local pollInFlight = false

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

local function stateFromQueryResult(result)
  if result.exitCode ~= 0 or result.timedOut then
    local reason = noctalia.string.trim(result.stderr)
    return Pill.stale(reason ~= "" and reason or "sqlite3 failed")
  end

  local output = noctalia.string.trim(result.stdout)
  if output == "" then
    return Pill.idle()
  end

  local threads, decodeError = noctalia.json.decode(output)
  if not threads then
    return Pill.stale(decodeError)
  end
  return Pill.active(threads)
end

local function pollActiveThreads()
  pollInFlight = true
  local started = noctalia.runAsync({
    "sqlite3",
    "-readonly",
    "-json",
    "-cmd",
    ".timeout 1000",
    STATE_DATABASE_PATH,
    ACTIVE_THREADS_QUERY,
  }, function(result)
    pollInFlight = false
    pill.render(stateFromQueryResult(result))
  end)

  if not started then
    pollInFlight = false
    pill.render(Pill.stale("sqlite3 not found"))
  end
end

noctalia.setUpdateInterval(POLL_INTERVAL_MS)

function update()
  if pollInFlight then
    return
  end
  if not isT3ServerRunning() then
    pill.render(Pill.idle())
    return
  end
  pollActiveThreads()
end
