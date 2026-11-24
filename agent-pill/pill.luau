local MARK_WIDTH_PX = 21
local MARK_HEIGHT_PX = 14
local COUNT_FONT_SIZE = 13
local LABEL_FONT_SIZE = 12
local WORKING_GLYPH = "circle-dashed"
local WORKING_GLYPH_SIZE_PX = 14
local ROW_GAP_PX = 6
local MAX_TOOLTIP_ROWS = 8

-- Tints and labels follow T3 Code's AgentActivity live activity.
local PHASE_STYLES = {
  working = { tint = "#7dd3fc", status = "Working" },
  approval = { tint = "#fcd34d", label = "Approval", status = "Approval needed" },
  input = { tint = "#a5b4fc", label = "Input", status = "Waiting for input" },
  stale = { tint = "#a1a1aa", label = "Out of date" },
}

local function attentionCount(agents)
  local count = 0
  for _, agent in agents do
    if agent.phase ~= "working" then
      count += 1
    end
  end
  return count
end

local function summaryLabel(agents)
  local summary = string.format("%d active %s", #agents, #agents == 1 and "agent" or "agents")
  local needingAttention = attentionCount(agents)
  if needingAttention == 0 then
    return summary
  end
  return string.format("%s · %d %s attention", summary, needingAttention, needingAttention == 1 and "needs" or "need")
end

local function tooltipRows(appName, agents)
  local rows = { { key = appName, value = summaryLabel(agents) } }
  for index = 1, math.min(#agents, MAX_TOOLTIP_ROWS) do
    table.insert(rows, { key = agents[index].title, value = PHASE_STYLES[agents[index].phase].status })
  end
  local hiddenCount = #agents - MAX_TOOLTIP_ROWS
  if hiddenCount > 0 then
    table.insert(rows, { key = "More", value = string.format("+%d", hiddenCount) })
  end
  return rows
end

local function pillContents(markPath, style, count)
  local contents = {
    ui.image({ path = markPath, width = MARK_WIDTH_PX, height = MARK_HEIGHT_PX, fit = "contain" }),
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

local function showPill(markPath, style, count, tooltip)
  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = ROW_GAP_PX, align = "center" }, pillContents(markPath, style, count)))
  barWidget.setTooltip(tooltip)
  barWidget.setVisible(true)
end

local function stateKey(state)
  if state.kind ~= "active" then
    return state.kind .. ":" .. (state.reason or "")
  end
  local parts = {}
  for _, agent in state.agents do
    table.insert(parts, agent.phase .. "\0" .. agent.title)
  end
  return "active:" .. table.concat(parts, "\0")
end

local Pill = {}

function Pill.idle()
  return { kind = "idle" }
end

function Pill.stale(reason)
  return { kind = "stale", reason = reason }
end

-- agents: rows of { title, phase }, phase being working, approval or input; attention rows first.
function Pill.active(agents)
  if #agents == 0 then
    return Pill.idle()
  end
  return { kind = "active", agents = agents }
end

-- app: { name, marks = { working, approval, input, stale } } with mark paths relative to the plugin.
function Pill.new(app)
  local renderedKey = nil

  local function render(state)
    local key = stateKey(state)
    if key == renderedKey then
      return
    end
    renderedKey = key

    if state.kind == "idle" then
      barWidget.setVisible(false)
    elseif state.kind == "active" then
      local phase = state.agents[1].phase
      showPill(app.marks[phase], PHASE_STYLES[phase], #state.agents, tooltipRows(app.name, state.agents))
    else
      noctalia.log(string.format("cannot read %s state: %s", app.name, state.reason))
      showPill(app.marks.stale, PHASE_STYLES.stale, nil, state.reason)
    end
  end

  return { render = render }
end

return Pill
