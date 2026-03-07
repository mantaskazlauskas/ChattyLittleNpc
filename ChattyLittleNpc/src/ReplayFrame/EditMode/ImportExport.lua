-- ============================================================================
-- ImportExport.lua — CLN2 Edit Mode layout bundle import / export
-- ============================================================================
-- Handles import/export of Edit Mode layout bundles in CLN2 format
-- (two-window: conversation + model), with backward-compatible CLN1 import.
--
-- Bundle format:  <BlizzardLayoutString>#CLN2#<Base64(payload)>
-- Payload:        Semicolon-delimited key=value pairs with namespace prefixes
--   v=2;c.*=...;m.*=...;
-- ============================================================================

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame
local EditMode = ReplayFrame.EditMode

local ImportExport = {}
EditMode.ImportExport = ImportExport

-- ---------------------------------------------------------------------------
-- Lazy-resolved module references (safe across any load order)
-- ---------------------------------------------------------------------------
local Registry, Persistence, Window

local function resolve()
    Registry    = Registry    or EditMode.Registry
    Persistence = Persistence or EditMode.Persistence
    Window      = Window      or EditMode.Window
end

-- ---------------------------------------------------------------------------
-- API availability guard (local per-file, same pattern as Persistence/Init)
-- ---------------------------------------------------------------------------
local hasAPI = (C_EditMode and type(C_EditMode.GetLayouts) == "function")

-- ---------------------------------------------------------------------------
-- Logging helpers
-- ---------------------------------------------------------------------------
local function logDebug(msg)
    if CLN and CLN.Logger then CLN.Logger:debug(msg, false, CLN.Utils.LogCategories.ui) end
end
local function logInfo(msg, chat)
    if CLN and CLN.Logger then CLN.Logger:info(msg, chat or false, CLN.Utils.LogCategories.ui) end
end
local function logWarn(msg)
    if CLN and CLN.Logger then CLN.Logger:warn(msg, false, CLN.Utils.LogCategories.ui) end
end

-- ---------------------------------------------------------------------------
-- Constants
-- ---------------------------------------------------------------------------
local CLN1_MARK = "#CLN1#"
local CLN2_MARK = "#CLN2#"

local BOUNDS = {
    scale       = { min = 0.5,  max = 2.0  },
    textScale   = { min = 0.75, max = 1.5  },
    width       = { min = 200,  max = 1000 },
    height      = { min = 100,  max = 600  },
    modelHeight = { min = 50,   max = 300  },
    modelWidth  = { min = 100,  max = 600  },
}

-- Defaults used when imported data is incomplete
local DEFAULTS = {
    conversation = {
        scale     = 1.0,
        textScale = 1.0,
        width     = 475,
        height    = 165,
    },
    model = {
        docked = true,
        width  = 475,
        height = 140,
    },
}

-- ---------------------------------------------------------------------------
-- Numeric helpers
-- ---------------------------------------------------------------------------

local function clamp(val, bound)
    return math.max(bound.min, math.min(bound.max, val))
end

local function safeNum(v)
    return tonumber(v)
end

local function round(n, decimals)
    decimals = decimals or 0
    local mult = 10 ^ decimals
    return math.floor(n * mult + 0.5) / mult
end

-- ============================================================================
-- BUILD / PARSE — CLN2
-- ============================================================================

--- Build the CLN2 payload string from both windows' current state.
---@return string payload  Semicolon-delimited namespaced key=value pairs
function ImportExport:BuildV2Meta()
    resolve()

    local parts = {}
    local function add(k, v)
        if v ~= nil then
            parts[#parts + 1] = k .. "=" .. tostring(v)
        end
    end

    add("v", 2)

    -- Conversation window --------------------------------------------------
    local convCtrl = Registry and Registry:Get("conversation")
    if convCtrl then
        local st = convCtrl:ReadState()
        if st then
            add("c.scale", round(st.scale or DEFAULTS.conversation.scale, 2))
            add("c.ts",    round(st.textScale or DEFAULTS.conversation.textScale, 2))
            if st.size then
                add("c.size.w", math.floor((st.size.width  or DEFAULTS.conversation.width)  + 0.5))
                add("c.size.h", math.floor((st.size.height or DEFAULTS.conversation.height) + 0.5))
            end
            if st.pos then
                add("c.pos.pt", st.pos.point         or "CENTER")
                add("c.pos.rp", st.pos.relativePoint  or "BOTTOMLEFT")
                add("c.pos.x",  round(st.pos.x or 0, 1))
                add("c.pos.y",  round(st.pos.y or 0, 1))
                add("c.pos.xp", round(st.pos.x_pct or 0, 4))
                add("c.pos.yp", round(st.pos.y_pct or 0, 4))
            end
        end
    end

    -- Model window ---------------------------------------------------------
    local modelCtrl = Registry and Registry:Get("model")
    if modelCtrl then
        local st = modelCtrl:ReadState()
        if st then
            add("m.docked", st.docked and 1 or 0)
            if st.size then
                add("m.size.w", math.floor((st.size.width  or DEFAULTS.model.width)  + 0.5))
                add("m.size.h", math.floor((st.size.height or DEFAULTS.model.height) + 0.5))
            end
            if st.pos then
                add("m.pos.pt", st.pos.point         or "CENTER")
                add("m.pos.rp", st.pos.relativePoint  or "BOTTOMLEFT")
                add("m.pos.x",  round(st.pos.x or 0, 1))
                add("m.pos.y",  round(st.pos.y or 0, 1))
                add("m.pos.xp", round(st.pos.x_pct or 0, 4))
                add("m.pos.yp", round(st.pos.y_pct or 0, 4))
            end
        end
    end

    return table.concat(parts, ";") .. ";"
end

--- Parse CLN2 payload into structured tables.
--- Conversation and model blocks are parsed independently — a failure in one
--- does not prevent the other from succeeding.
---@param str string  Semicolon-delimited payload
---@return table parsed  { version, conversation?, model? }
function ImportExport:ParseV2Meta(str)
    -- Tokenise all key=value pairs (keys may contain dots)
    local kv = {}
    for k, v in string.gmatch(str or "", "([%w%.]+)=([^;]*)") do
        kv[k] = v
    end

    local result = {
        version      = safeNum(kv["v"]) or 2,
        conversation = nil,
        model        = nil,
    }

    -- Conversation block (c.*) ---------------------------------------------
    local cOk, cErr = pcall(function()
        local c = {}

        if safeNum(kv["c.scale"]) then
            c.scale = clamp(safeNum(kv["c.scale"]), BOUNDS.scale)
        end
        if safeNum(kv["c.ts"]) then
            c.textScale = clamp(safeNum(kv["c.ts"]), BOUNDS.textScale)
        end

        local cw = safeNum(kv["c.size.w"])
        local ch = safeNum(kv["c.size.h"])
        if cw or ch then
            c.size = {
                width  = clamp(cw or DEFAULTS.conversation.width,  BOUNDS.width),
                height = clamp(ch or DEFAULTS.conversation.height, BOUNDS.height),
            }
        end

        if kv["c.pos.pt"] then
            c.pos = {
                point         = kv["c.pos.pt"]  or "CENTER",
                relativePoint = kv["c.pos.rp"]  or "BOTTOMLEFT",
                x             = safeNum(kv["c.pos.x"])  or 0,
                y             = safeNum(kv["c.pos.y"])  or 0,
                x_pct         = safeNum(kv["c.pos.xp"]) or 0,
                y_pct         = safeNum(kv["c.pos.yp"]) or 0,
            }
        end

        if next(c) then result.conversation = c end
    end)
    if not cOk then
        logWarn("CLN2 parse: conversation block error: " .. tostring(cErr))
    end

    -- Model block (m.*) ----------------------------------------------------
    local mOk, mErr = pcall(function()
        local m = {}

        if kv["m.docked"] ~= nil then
            m.docked = (kv["m.docked"] == "1")
        end

        local mw = safeNum(kv["m.size.w"])
        local mh = safeNum(kv["m.size.h"])
        if mw or mh then
            m.size = {
                width  = clamp(mw or DEFAULTS.model.width,  BOUNDS.modelWidth),
                height = clamp(mh or DEFAULTS.model.height, BOUNDS.modelHeight),
            }
        end

        if kv["m.pos.pt"] then
            m.pos = {
                point         = kv["m.pos.pt"]  or "CENTER",
                relativePoint = kv["m.pos.rp"]  or "BOTTOMLEFT",
                x             = safeNum(kv["m.pos.x"])  or 0,
                y             = safeNum(kv["m.pos.y"])  or 0,
                x_pct         = safeNum(kv["m.pos.xp"]) or 0,
                y_pct         = safeNum(kv["m.pos.yp"]) or 0,
            }
        end

        if next(m) then result.model = m end
    end)
    if not mOk then
        logWarn("CLN2 parse: model block error: " .. tostring(mErr))
    end

    return result
end

-- ============================================================================
-- BUILD / PARSE — CLN1 (legacy)
-- ============================================================================

--- Parse legacy CLN1 meta and map to conversation-only data with model defaults.
--- CLN1 keys: fs, ts, w, h, mh, pt, rp, px, py
---@param str string  Semicolon-delimited CLN1 payload
---@return table parsed  { version = 1, conversation?, model? }
function ImportExport:ParseV1Meta(str)
    local kv = {}
    for pair in string.gmatch(str or "", "([%w]+=[^;]*);") do
        local k, v = pair:match("^(%w+)=([^;]*)$")
        if k then kv[k] = v end
    end

    local result = { version = 1, conversation = nil, model = nil }

    -- Map CLN1 keys → conversation state -----------------------------------
    local cOk, cErr = pcall(function()
        local c = {}

        if safeNum(kv.fs) then c.scale    = clamp(safeNum(kv.fs), BOUNDS.scale)     end
        if safeNum(kv.ts) then c.textScale = clamp(safeNum(kv.ts), BOUNDS.textScale) end

        local w = safeNum(kv.w)
        local h = safeNum(kv.h)
        if w or h then
            c.size = {
                width  = clamp(w or DEFAULTS.conversation.width,  BOUNDS.width),
                height = clamp(h or DEFAULTS.conversation.height, BOUNDS.height),
            }
        end

        if kv.pt then
            c.pos = {
                point         = kv.pt or "CENTER",
                relativePoint = kv.rp or "CENTER",
                x             = safeNum(kv.px) or 0,
                y             = safeNum(kv.py) or 0,
            }
        end

        if next(c) then result.conversation = c end
    end)
    if not cOk then
        logWarn("CLN1 parse: conversation block error: " .. tostring(cErr))
    end

    -- Map mh → model (docked, height only — CLN1 had no model position) ----
    local mOk, mErr = pcall(function()
        local mh = safeNum(kv.mh)
        if mh then
            result.model = {
                docked = true,
                size   = {
                    width  = DEFAULTS.model.width,
                    height = clamp(mh, BOUNDS.modelHeight),
                },
            }
        end
    end)
    if not mOk then
        logWarn("CLN1 parse: model block error: " .. tostring(mErr))
    end

    return result
end

-- ============================================================================
-- Blizzard Layout Helper
-- ============================================================================

--- Save a Blizzard layout info table as a new named layout.
---@param layoutInfo table  Layout from ConvertStringToLayoutInfo
---@param name string|nil   Optional layout name override
---@return boolean ok, string|nil error
function ImportExport:SaveBlizzardLayout(layoutInfo, name)
    if not hasAPI then return false, "Edit Mode API unavailable" end

    local ok, all = pcall(C_EditMode.GetLayouts)
    if not ok or not all or not all.layouts then
        return false, "Could not retrieve layouts"
    end

    layoutInfo.layoutName = name
        or ((layoutInfo.layoutName or "Layout") .. " (CLN)")

    -- Validate name if the API is available
    if C_EditMode.IsValidLayoutName then
        local validOk, isValid = pcall(C_EditMode.IsValidLayoutName, layoutInfo.layoutName)
        if validOk and not isValid then
            layoutInfo.layoutName = layoutInfo.layoutName:sub(1, 20)
        end
    end

    table.insert(all.layouts, layoutInfo)

    local saveOk, saveErr = pcall(C_EditMode.SaveLayouts, all)
    if not saveOk then
        return false, "SaveLayouts failed: " .. tostring(saveErr)
    end

    pcall(C_EditMode.SetActiveLayout, #all.layouts)
    return true
end

-- ============================================================================
-- Import — format-specific handlers
-- ============================================================================

--- Apply parsed state tables to controllers with per-block error isolation.
---@param parsed table  { conversation?, model? }
---@return table summary  Array of human-readable result strings
local function applyParsedState(parsed)
    resolve()
    local summary = {}

    -- Conversation ---------------------------------------------------------
    if parsed.conversation then
        local ctrl = Registry and Registry:Get("conversation")
        if ctrl then
            local ok, err = pcall(ctrl.ApplyState, ctrl, parsed.conversation)
            if ok then
                summary[#summary + 1] = "Conversation settings applied"
            else
                logWarn("Failed to apply conversation state: " .. tostring(err))
                summary[#summary + 1] = "Conversation settings failed"
            end
        else
            summary[#summary + 1] = "Conversation controller not available"
        end
    end

    -- Model (independent — conversation failure does not affect this) -------
    if parsed.model then
        local ctrl = Registry and Registry:Get("model")
        if ctrl then
            local ok, err = pcall(ctrl.ApplyState, ctrl, parsed.model)
            if ok then
                summary[#summary + 1] = "Model settings applied"
            else
                logWarn("Failed to apply model state: " .. tostring(err))
                summary[#summary + 1] = "Model settings failed"
            end
        else
            summary[#summary + 1] = "Model controller not available"
        end
    end

    -- Persist all changes to the active layout bucket
    if Persistence and (parsed.conversation or parsed.model) then
        pcall(Persistence.PersistAll, Persistence)
    end

    return summary
end

--- Import a CLN2 bundle.
---@param bundle string  Full bundle string
---@param opts   table   Import options
---@return boolean ok, string result
function ImportExport:ImportV2(bundle, opts)
    resolve()
    opts = opts or {}

    local base, encoded = bundle:match("^(.-)#CLN2#([A-Za-z0-9%+/=]+)$")
    if not encoded then
        return false, "CLN2 marker found but payload is missing or malformed"
    end

    local decOk, decoded = pcall(function() return CLN.Base64:Decode(encoded) end)
    if not decOk or not decoded or decoded == "" then
        return false, "CLN2 Base64 decode failed: " .. tostring(decoded)
    end

    logDebug("CLN2 decoded payload: " .. decoded)
    local parsed = self:ParseV2Meta(decoded)
    local summary = {}

    -- Blizzard layout (failure here doesn't abort Chatty settings) ----------
    if base and base ~= "" then
        local lOk, layoutInfo = pcall(function() return C_EditMode.ConvertStringToLayoutInfo(base) end)
        if lOk and layoutInfo then
            if opts.saveLayout then
                local saveOk, saveErr = self:SaveBlizzardLayout(layoutInfo, opts.layoutName)
                if saveOk then
                    summary[#summary + 1] = "Blizzard layout saved"
                else
                    summary[#summary + 1] = "Blizzard layout save failed: " .. tostring(saveErr)
                end
            end
        else
            summary[#summary + 1] = "Blizzard layout parse failed (Chatty settings still applied)"
        end
    end

    -- Chatty settings -------------------------------------------------------
    local stateResults = applyParsedState(parsed)
    for _, s in ipairs(stateResults) do
        summary[#summary + 1] = s
    end

    local summaryStr = table.concat(summary, "; ")
    logInfo("CLN2 import complete: " .. summaryStr)
    return true, summaryStr
end

--- Import a CLN1 (legacy) bundle.
---@param bundle string  Full bundle string
---@param opts   table   Import options
---@return boolean ok, string result
function ImportExport:ImportV1(bundle, opts)
    resolve()
    opts = opts or {}

    local base, encoded = bundle:match("^(.-)#CLN1#([A-Za-z0-9%+/=]+)$")
    if not encoded then
        return false, "CLN1 marker found but payload is missing or malformed"
    end

    local decOk, decoded = pcall(function() return CLN.Base64:Decode(encoded) end)
    if not decOk or not decoded or decoded == "" then
        return false, "CLN1 Base64 decode failed"
    end

    logDebug("CLN1 decoded payload: " .. decoded)
    local parsed = self:ParseV1Meta(decoded)
    local summary = {}

    -- Blizzard layout -------------------------------------------------------
    if base and base ~= "" then
        local lOk, layoutInfo = pcall(function() return C_EditMode.ConvertStringToLayoutInfo(base) end)
        if lOk and layoutInfo then
            if opts.saveLayout then
                local saveOk, saveErr = self:SaveBlizzardLayout(layoutInfo, opts.layoutName)
                if saveOk then
                    summary[#summary + 1] = "Blizzard layout saved"
                else
                    summary[#summary + 1] = "Blizzard layout save failed: " .. tostring(saveErr)
                end
            end
        else
            summary[#summary + 1] = "Blizzard layout parse failed"
        end
    end

    -- Chatty settings (v1 → mapped to two-window state) --------------------
    local stateResults = applyParsedState(parsed)
    for _, s in ipairs(stateResults) do
        summary[#summary + 1] = s
    end

    local summaryStr = table.concat(summary, "; ")
    logInfo("CLN1 import complete: " .. summaryStr)
    return true, summaryStr
end

-- ============================================================================
-- Public API: Export
-- ============================================================================

--- Locate the active Blizzard layout info from C_EditMode.
---@return table|nil layoutInfo, string|nil error
local function getActiveLayoutInfo()
    resolve()
    if not hasAPI then return nil, "Edit Mode API unavailable" end

    local lOk, layouts = pcall(C_EditMode.GetLayouts)
    if not lOk or not layouts or not layouts.layouts then
        return nil, "No layouts available"
    end

    local li
    local activeName = Persistence and Persistence.GetActiveLayoutName
        and Persistence:GetActiveLayoutName()
    if activeName then
        for _, l in ipairs(layouts.layouts) do
            if l.layoutName == activeName then li = l; break end
        end
    end
    if not li then
        local idx = layouts.activeLayout
        li = idx and layouts.layouts[idx]
    end
    if not li then
        return nil, "Active layout not found"
    end
    return li
end

--- Export the current Edit Mode state as a CLN2 bundle.
---@return string|nil bundle, string|nil error
function ImportExport:ExportBundle()
    resolve()

    local li, err = getActiveLayoutInfo()
    if not li then return nil, err end

    local convOk, base = pcall(C_EditMode.ConvertLayoutInfoToString, li)
    if not convOk or not base then
        return nil, "Layout conversion failed"
    end

    local meta = self:BuildV2Meta()

    local encOk, encoded = pcall(function() return CLN.Base64:Encode(meta) end)
    if not encOk or not encoded then
        return nil, "Metadata encoding failed"
    end

    local bundle = base .. CLN2_MARK .. encoded
    logInfo("Exported CLN2 bundle (len=" .. #bundle .. ")")
    return bundle
end

--- Export Blizzard layout string only (no Chatty suffix).
--- Useful for sharing with non-Chatty users.
---@return string|nil layoutStr, string|nil error
function ImportExport:ExportBlizzardOnly()
    local li, err = getActiveLayoutInfo()
    if not li then return nil, err end

    local convOk, base = pcall(C_EditMode.ConvertLayoutInfoToString, li)
    if not convOk or not base then
        return nil, "Layout conversion failed"
    end

    logInfo("Exported Blizzard-only layout (len=" .. #base .. ")")
    return base
end

-- ============================================================================
-- Public API: Import
-- ============================================================================

--- Import a bundle string (auto-detects CLN2, CLN1, or plain Blizzard).
---@param bundle string       The bundle string to import
---@param opts   table|nil    { saveLayout = bool, layoutName = string }
---@return boolean ok, string result
function ImportExport:ImportBundle(bundle, opts)
    resolve()

    if type(bundle) ~= "string" or bundle:match("^%s*$") then
        return false, "Empty or invalid input"
    end
    if not hasAPI then return false, "Edit Mode API unavailable" end

    opts = opts or {}

    -- Detect format by marker presence
    if bundle:find(CLN2_MARK, 1, true) then
        logDebug("Detected CLN2 format")
        return self:ImportV2(bundle, opts)

    elseif bundle:find(CLN1_MARK, 1, true) then
        logDebug("Detected CLN1 format (legacy)")
        return self:ImportV1(bundle, opts)

    else
        -- Plain Blizzard layout string — no Chatty metadata
        logDebug("Detected plain Blizzard layout (no Chatty metadata)")
        local lOk, layoutInfo = pcall(function() return C_EditMode.ConvertStringToLayoutInfo(bundle) end)
        if not lOk or not layoutInfo then
            return false, "Not a valid layout string"
        end
        if opts.saveLayout then
            local saveOk, saveErr = self:SaveBlizzardLayout(layoutInfo, opts.layoutName)
            if not saveOk then
                return false, "Layout save failed: " .. tostring(saveErr)
            end
            return true, "Blizzard layout saved (no Chatty settings)"
        end
        return true, "Blizzard layout parsed (no Chatty settings, not saved)"
    end
end

-- ============================================================================
-- Slash Commands
-- ============================================================================

SLASH_CLNEXP1 = "/clnexp"
SlashCmdList["CLNEXP"] = function()
    local bundle, err = ImportExport:ExportBundle()
    if not bundle then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff2020CLN Export failed:|r " .. tostring(err))
        end
        return
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200Chatty Layout Bundle:|r " .. bundle)
    end
end

SLASH_CLNIMP1 = "/clnimp"
SlashCmdList["CLNIMP"] = function(msg)
    local str = msg and msg:match("^%s*(.-)%s*$")
    if not str or str == "" then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("Usage: /clnimp <bundleString>")
        end
        return
    end
    local ok, result = ImportExport:ImportBundle(str, { saveLayout = true })
    if DEFAULT_CHAT_FRAME then
        if ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cff20ff20CLN Import success:|r " .. tostring(result))
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff2020CLN Import failed:|r " .. tostring(result))
        end
    end
end

return ImportExport
