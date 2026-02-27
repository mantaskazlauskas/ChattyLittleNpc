---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = {}
CLN.ReplayFrame = ReplayFrame

-- Pure helpers namespace
ReplayFrame.Pure = ReplayFrame.Pure or {}

-- =============================================================
-- Model metadata cache (keyed by displayID, fallback to npcId)
-- =============================================================
-- Usage:
--   local meta = ReplayFrame:GetModelMeta(displayID, npcId, true)
--   ReplayFrame:UpdateModelMeta(displayID, npcId, { framing = { scale = 1.1 } })
-- Keys are strings prefixed to avoid collisions: 'd:<displayID>' or 'n:<npcId>'.
ReplayFrame._modelMeta = ReplayFrame._modelMeta or {}

function ReplayFrame:ResolveModelMetaKey(displayID, npcId)
    local d = tonumber(displayID)
    if d and d > 0 then return "d:" .. tostring(d) end
    local n = tonumber(npcId)
    if n and n > 0 then return "n:" .. tostring(n) end
    return nil
end

function ReplayFrame:GetModelMeta(displayID, npcId, createIfMissing)
    local key = self:ResolveModelMetaKey(displayID, npcId)
    if not key then return nil end
    local t = self._modelMeta[key]
    if not t and createIfMissing then
        t = { displayID = tonumber(displayID), npcId = tonumber(npcId) }
        self._modelMeta[key] = t
    end
    return t
end

function ReplayFrame:SetModelMeta(displayID, npcId, meta)
    if type(meta) ~= "table" then return end
    local key = self:ResolveModelMetaKey(displayID, npcId)
    if not key then return end
    meta.displayID = tonumber(displayID) or meta.displayID
    meta.npcId = tonumber(npcId) or meta.npcId
    self._modelMeta[key] = meta
end

function ReplayFrame:UpdateModelMeta(displayID, npcId, patch)
    if type(patch) ~= "table" then return end
    local meta = self:GetModelMeta(displayID, npcId, true)
    if not meta then return end
    for k, v in pairs(patch) do meta[k] = v end
end

-- Lightweight debug logger (disabled unless profile.debugMode is true)
function ReplayFrame:Debug(...)
    local ok = CLN and CLN.db and CLN.db.profile and CLN.db.profile.debugMode
    if not ok then return end
    local args = {...}
    local strs = {}
    for i, arg in ipairs(args) do
        strs[i] = tostring(arg)
    end
    if CLN and CLN.Logger then CLN.Logger:debug(table.concat(strs, " "), false, CLN.Utils.LogCategories.ui) end
end

-- ============================================================================
-- INITIALIZATION AND BINDING
-- ============================================================================

-- Track if the user explicitly hid the window while audio is playing
ReplayFrame.userHidden = false

-- Defer binding to after addon init to ensure globals exist
local function CLN_InitEditModeBinding()
    -- Legacy BindBlizzardEditMode now a thin adapter; prefer direct integration init
    if ReplayFrame and ReplayFrame.InitEditModeIntegration then
        ReplayFrame:InitEditModeIntegration()
    elseif ReplayFrame and ReplayFrame.BindBlizzardEditMode then
        -- Fallback (should not be needed after deprecation)
        ReplayFrame:BindBlizzardEditMode()
    end
end

if CreateFrame then
    local binder = CreateFrame("Frame")
    binder:RegisterEvent("PLAYER_LOGIN")
    binder:SetScript("OnEvent", function()
        CLN_InitEditModeBinding()
    end)
end

-- ============================================================================
-- CORE REPLAY FRAME LOGIC
-- ============================================================================

-- Removed GetFirstLine; use ToSingleLine for UI strings

-- Convert any multi-line WoW-formatted string to a clean single line suitable for headers (pure)
function ReplayFrame.Pure.ToSingleLine(text)
    if not text or type(text) ~= "string" then return text end
    local s = text
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("|T.-|t", "")
    s = s:gsub("|H.-|h", ""):gsub("|h", "")
    s = s:gsub("|n", " ")
    s = s:gsub("\r\n", " "):gsub("\r", " "):gsub("\n", " ")
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

function ReplayFrame:ToSingleLine(text)
    return ReplayFrame.Pure.ToSingleLine(text)
end

-- =============================================================
-- Framer (pure math helpers for camera/framing)
-- =============================================================
ReplayFrame.Framer = ReplayFrame.Framer or {}

-- Compute scale to fit at distance D (vertical FOV in radians), with margin m (0..1)
function ReplayFrame.Framer.FitScale(meta, D, margin)
    if not (meta and meta.size and meta.size.h and meta.size.w and meta.fovV and meta.aspect) then return 1.0 end
    local fovV = tonumber(meta.fovV) or math.rad(60)
    local aspect = tonumber(meta.aspect) or 1.0
    local Hobj = tonumber(meta.size.h) or 1.0
    local Wobj = tonumber(meta.size.w) or 1.0
    local m = math.max(0, math.min(0.5, tonumber(margin) or 0))
    local V = 2 * (tonumber(D) or 10) * math.tan(fovV * 0.5)
    local Hview = V * aspect
    local sV = (V * (1 - m)) / math.max(1e-6, Hobj)
    local sH = (Hview * (1 - (m + 0.03))) / math.max(1e-6, Wobj) -- add small extra horizontal margin
    local s = math.min(sV, sH)
    return math.max(0.05, math.min(10, s))
end

-- Percent range framing [p0,p1] from feet->head (0..1); returns zCenter and scale for distance D
function ReplayFrame.Framer.PercentRange(meta, p0, p1, D, margin)
    if not (meta and meta.size and meta.bottomZ and meta.center and meta.fovV and meta.aspect) then return nil end
    local Hobj = tonumber(meta.size.h) or 1.0
    local bottom = tonumber(meta.bottomZ) or 0
    local p0n = math.max(0, math.min(1, tonumber(p0) or 0))
    local p1n = math.max(0, math.min(1, tonumber(p1) or 1))
    if p1n <= p0n then p1n = math.min(1, p0n + 0.01) end
    local zCenter = bottom + ((p0n + p1n) * 0.5) * Hobj
    -- Base scale to fit full height at D
    local sBase = ReplayFrame.Framer.FitScale(meta, D, margin)
    local sRange = sBase / math.max(1e-3, (p1n - p0n))
    -- Width clamp as in FitScale
    local fovV = tonumber(meta.fovV) or math.rad(60)
    local aspect = tonumber(meta.aspect) or 1.0
    local V = 2 * (tonumber(D) or 10) * math.tan(fovV * 0.5)
    local Hview = V * aspect
    local Wobj = tonumber(meta.size.w) or 1.0
    local m = math.max(0, math.min(0.5, tonumber(margin) or 0)) + 0.03
    local sH = (Hview * (1 - m)) / math.max(1e-6, Wobj)
    local s = math.min(sRange, sH)
    return zCenter, math.max(0.05, math.min(10, s))
end

-- =============================================================
-- Standardized model-relative animation helpers (backend-agnostic)
-- =============================================================

-- Internal: get current displayID (if any)
function ReplayFrame:_GetCurrentDisplayID()
    local m = self.NpcModelFrame
    return m and m._currentDisplayID or nil
end

-- Internal: fetch or synthesize minimal bounds from cached meta
local function _getBoundsFromMeta(meta)
    if not (meta and meta.bottomZ and meta.size and meta.size.h) then return nil end
    local h = tonumber(meta.size.h) or 2.0
    local bottom = tonumber(meta.bottomZ) or 0
    return {
        bottomZ = bottom,
        topZ = bottom + h,
        height = h,
        centerZ = bottom + h * 0.5,
    }
end

-- Convert model-relative vertical coordinate p∈[0,1] (0=feet,1=head) to world Z
function ReplayFrame:WorldZFromPercent(p)
    local pn = math.max(0, math.min(1, tonumber(p) or 0.5))
    local displayID = self:_GetCurrentDisplayID()
    local cur = CLN and CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local npcId = cur and cur.npcId or nil
    local meta = self:GetModelMeta(displayID, npcId, false)
    local b = _getBoundsFromMeta(meta)
    if b then
        return b.bottomZ + pn * b.height
    end
    -- Try live bounds from the host (same coordinate system as scene camera)
    local host = self.NpcModelFrame
    if host and host.GetBounds then
        local lb = host:GetBounds()
        if lb and lb.min and lb.max then
            local bottomZ = math.min(lb.min.z or 0, lb.max.z or 0)
            local height = math.abs((lb.max.z or 0) - (lb.min.z or 0))
            if height > 0.01 then
                return bottomZ + pn * height
            end
        end
    end
    -- Last-resort fallback
    local base = (self.modelZOffset ~= nil) and self.modelZOffset or (self._currentZOffset or 0)
    return base + (pn - 0.5) * 2.0
end

-- Compute camera target (zoom numeric and centerZ) to show vertical range [p0,p1]
-- Uses PercentRange + a unified mapping from scale->portrait zoom.
function ReplayFrame:ZoomForRangePercent(p0, p1, opts)
    opts = opts or {}
    local displayID = self:_GetCurrentDisplayID()
    local cur = CLN and CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local npcId = cur and cur.npcId or nil
    local meta = self:GetModelMeta(displayID, npcId, false)
    if not meta then return nil end
    local D = tonumber(opts.distance) or (meta.distance or 10)
    local margin = tonumber(opts.margin) or 0.10
    local zCenter, scale = ReplayFrame.Framer.PercentRange(meta, p0, p1, D, margin)
    if not (zCenter and scale) then return nil end
    -- Map scale to portrait zoom via the standard shim mapping: zoom = base / scale
    local baseZoom = 0.65
    local targetZoom = math.max(0.01, math.min(1.5, baseZoom / math.max(0.05, scale)))
    return { zoom = targetZoom, centerZ = zCenter, scale = scale }
end

-- Instant: show a vertical range in percent via renderer projection (works on both backends)
function ReplayFrame:ShowRangePercent(p0, p1, opts)
    opts = opts or {}
    local p0n = math.max(0, math.min(1, tonumber(p0) or 0))
    local p1n = math.max(0, math.min(1, tonumber(p1) or 1))
    if p1n <= p0n then p1n = math.min(1, p0n + 0.01) end
    local m = self.NpcModelFrame
    if not m then return false end
    local z = self:WorldZFromPercent((p0n + p1n) * 0.5)
    local zt = { z = z }
    local zData = self:ZoomForRangePercent(p0n, p1n, opts)
    if zData and m.ProjectFit then
        pcall(m.ProjectFit, m, zData.scale, zt)
        self._currentZOffset = z
        -- Best-effort keep zoom cache in sync if our animation system references it
        self._currentZoom = zData.zoom
        return true
    end
    -- Fallback: set zoom/pan directly if projection not available
    if zData and m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, zData.zoom) end
    if m.SetPosition then pcall(m.SetPosition, m, 0, 0, z) end
    self._currentZOffset = z
    return true
end

-- Animated: pan to a model-relative focus point p in [0,1]
function ReplayFrame:AnimPanToPercent(p, duration, options)
    local z = self:WorldZFromPercent(p)
    if not z then return false end
    if self.AnimPanTo then return self:AnimPanTo(z, duration or 0.25, options) end
    local m = self.NpcModelFrame
    if m and m.SetPosition then pcall(m.SetPosition, m, 0, 0, z) end
    self._currentZOffset = z
    return true
end

-- Animated: zoom to show vertical range [p0,p1] consistently across backends
function ReplayFrame:AnimZoomToRangePercent(p0, p1, duration, options)
    local data = self:ZoomForRangePercent(p0, p1, options)
    if not data then return false end
    if self.AnimZoomTo then return self:AnimZoomTo(data.zoom, duration or 0.5, options) end
    local m = self.NpcModelFrame
    if m and m.SetPortraitZoom then pcall(m.SetPortraitZoom, m, data.zoom) end
    self._currentZoom = data.zoom
    return true
end

-- Presets expressed in model-relative ranges
ReplayFrame.ModelPresets = ReplayFrame.ModelPresets or {
    FullBody = { p0 = 0.0, p1 = 1.0, padding = 0.12 },
    UpperBody = { p0 = 0.50, p1 = 1.0, padding = 0.10 },
    HeadShoulders = { p0 = 0.65, p1 = 1.0, padding = 0.10 },
    FaceCloseup = { p0 = 0.80, p1 = 1.0, padding = 0.08 },
    Torso = { p0 = 0.20, p1 = 0.80, padding = 0.10 },
    HandGesture = { p0 = 0.30, p1 = 0.60, padding = 0.15 },
}

-- Convenience: apply a preset instantly
function ReplayFrame:ShowPreset(name)
    local p = self.ModelPresets and self.ModelPresets[name]
    if not p then return false end
    return self:ShowRangePercent(p.p0, p.p1, { margin = p.padding })
end

-- Emote-named presets for readability; include a focus point for panPercent
ReplayFrame.EmotePresets = ReplayFrame.EmotePresets or {
    Talk  = { p0 = 0.50, p1 = 1.00, focus = 0.75, padding = 0.10 },
    Wave  = { p0 = 0.30, p1 = 0.60, focus = 0.40, padding = 0.15 },
    Idle  = { p0 = 0.00, p1 = 1.00, focus = 0.50, padding = 0.12 },
    Bow   = { p0 = 0.20, p1 = 0.70, focus = 0.45, padding = 0.12 },
    Point = { p0 = 0.40, p1 = 0.85, focus = 0.60, padding = 0.10 },
}

function ReplayFrame:GetEmotePreset(name)
    if not name then return nil end
    local p = self.EmotePresets and self.EmotePresets[name]
    return p
end

-- Apply an emote preset instantly or animated (duration>0 animates zoom)
function ReplayFrame:ApplyEmotePreset(name, duration, opts)
    local p = self:GetEmotePreset(name)
    if not p then return false end
    opts = opts or {}
    local ok
    if duration and duration > 0 and self.AnimZoomToRangePercent then
        ok = self:AnimZoomToRangePercent(p.p0, p.p1, duration, { easing = opts.easing or "easeOutCubic", margin = p.padding }) ~= false
    else
        ok = self:ShowRangePercent(p.p0, p.p1, { margin = p.padding }) ~= false
    end
    -- Focus pan (animated if panDur provided)
    local panDur = opts.panDur or 0.25
    if self.AnimPanToPercent and p.focus then
        self:AnimPanToPercent(p.focus, panDur, { easing = opts.easing or "easeOutCubic" })
    end
    return ok
end


-- Pure: choose header text given state
function ReplayFrame.Pure.BuildHeaderText(playingTitle, npcName, isQuest, qcount, collapsed)
    local total = (playingTitle and 1 or 0) + (qcount or 0)
    if total <= 0 then
        return "Conversations"
    end
    if collapsed then
        local title = ReplayFrame.Pure.ToSingleLine(playingTitle or "")
        if title == nil or title == "" then title = "Conversations" end
        if npcName and not isQuest and title ~= "" then
            title = npcName .. ": " .. title
        end
        return string.format("%s (%d)", title, total)
    else
        return string.format("Conversations (%d)", total)
    end
end

-- Pure: label/tooltip formatting for queue entries
function ReplayFrame.Pure.FormatEntryLabel(npcName, content, isQuest)
    local safeContent = content or ""
    if isQuest then
        if safeContent ~= "" then
            return npcName and (npcName .. " — " .. safeContent) or safeContent
        end
        return npcName or "Unknown"
    else
        local single = ReplayFrame.Pure.ToSingleLine(safeContent)
        if npcName and single ~= "" then
            return npcName .. ": " .. single
        elseif npcName then
            return npcName
        else
            return (single ~= "" and single) or "Unknown"
        end
    end
end

function ReplayFrame.Pure.FormatEntryTooltip(npcName, content)
    local safeContent = content or ""
    if npcName and safeContent ~= "" then
        return npcName .. ": " .. safeContent
    end
    return safeContent ~= "" and safeContent or (npcName or "")
end

-- Header truncation: compute max width once and truncate consistently
function ReplayFrame:ApplyHeaderTruncation(fs, text)
    if not (fs and text) then return end
    -- Set desired text first so fs:GetWidth() reflects the anchored region width
    fs:SetText(text)
    local maxW = 0
    if fs.GetWidth then maxW = fs:GetWidth() or 0 end
    maxW = math.max(40, maxW)
    if self.TruncateToWidth then
        self:TruncateToWidth(fs, text, maxW)
    end
end

-- Pure: choose talk animation id based on punctuation proportions; rng optional
function ReplayFrame.Pure.ChooseTalkAnimIdForText(text, rng)
    local s = ReplayFrame.Pure.ToSingleLine(text or "") or ""
    -- Count sentences (rough): split on . ! ?
    local total = 0
    s:gsub("[%.%!%?]+", function() total = total + 1 end)
    if total == 0 then total = 1 end
    local q = 0; s:gsub("%?", function() q = q + 1 end)
    local e = 0; s:gsub("%!", function() e = e + 1 end)
    local pQ = math.min(1, math.max(0, q / total))
    local pE = math.min(1, math.max(0, e / total))
    local sum = pQ + pE
    if sum > 1 then pQ = pQ / sum; pE = pE / sum end
    local remaining = math.max(0, 1 - (pQ + pE))
    -- subdued maps to 60 as well; kept for conceptual parity
    local pSubdued = remaining * 0.75
    local pNormal = remaining * 0.25
    local draw = (type(rng) == "function") and rng() or math.random()
    if draw < pE then
        return 64
    elseif draw < (pE + pQ) then
        return 65
    else
        return 60
    end
end

-- Helper: Try to resolve an NPC name from saved DB by npcId
function ReplayFrame:GetNpcNameById(npcId)
    if not npcId then return nil end
    self._npcNameCache = self._npcNameCache or {}
    local loc = CLN.locale or "enUS"
    local byLoc = self._npcNameCache[loc]
    if byLoc and byLoc[npcId] ~= nil then return byLoc[npcId] end
    local db = type(NpcInfoDB) == "table" and NpcInfoDB or nil
    local name = nil
    if db and db[npcId] and db[npcId][loc] and db[npcId][loc].name then
        name = db[npcId][loc].name
    end
    if not self._npcNameCache[loc] then self._npcNameCache[loc] = {} end
    self._npcNameCache[loc][npcId] = name -- cache misses as nil to avoid re-lookup churn
    return name
end

-- ============================================================================
-- REPLAY HISTORY (Ring Buffer)
-- ============================================================================
ReplayFrame._replayHistory = ReplayFrame._replayHistory or {}
ReplayFrame._replayHistoryMax = 20

function ReplayFrame:PushHistory(entry)
    if not entry then return end
    local max = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.queueHistoryMaxEntries) or self._replayHistoryMax
    if max <= 0 then return end
    -- Ensure timestamp exists
    if not entry.completedAt then entry.completedAt = GetTime and GetTime() or 0 end
    -- Deduplicate: remove existing entry with same identity before re-inserting at top
    for i = #self._replayHistory, 1, -1 do
        local h = self._replayHistory[i]
        if h.npcId == entry.npcId and h.title == entry.title
           and (h.questId or "") == (entry.questId or "")
           and (h.phase or "") == (entry.phase or "") then
            table.remove(self._replayHistory, i)
        end
    end
    table.insert(self._replayHistory, 1, entry) -- newest first
    while #self._replayHistory > max do
        table.remove(self._replayHistory)
    end
    -- Prune entries older than configured TTL
    self:PruneOldHistory()
end

local HISTORY_TTL_DEFAULT = 300 -- 5 minutes in seconds (fallback)

function ReplayFrame:GetHistoryTTL()
    local minutes = CLN and CLN.db and CLN.db.profile and CLN.db.profile.historyTTLMinutes
    if type(minutes) == "number" and minutes > 0 then
        return minutes * 60
    end
    return HISTORY_TTL_DEFAULT
end

function ReplayFrame:PruneOldHistory()
    if not self._replayHistory then return end
    local now = GetTime and GetTime() or 0
    local ttl = self:GetHistoryTTL()
    for i = #self._replayHistory, 1, -1 do
        local h = self._replayHistory[i]
        if h.completedAt and (now - h.completedAt) > ttl then
            table.remove(self._replayHistory, i)
        end
    end
end

function ReplayFrame:GetHistory()
    return self._replayHistory or {}
end

function ReplayFrame:ClearHistory()
    self._replayHistory = {}
    self._scrollOffset = 0
    if self.MarkQueueDirty then self:MarkQueueDirty() end
end

-- Build a normalized list of entries for the queue view
-- Each entry: { isPlaying=bool, queueIndex=number|nil, label=string, tooltip=string }
function ReplayFrame:BuildQueueEntries()
    local entries = {}
    local now = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil

    -- Only show "now playing" if the sound is actually still active (playing or paused)
    -- Use grace-aware check to stay consistent with the watcher/visibility system;
    -- raw C_Sound.IsPlaying can briefly return false during dialog transitions.
    local isActive = false
    if now and (now.title or now.questId) then
        local stillPlaying = CLN.VoiceoverPlayer.IsEffectivelyPlaying
            and CLN.VoiceoverPlayer:IsEffectivelyPlaying()
            or (now.isPlaying and now:isPlaying())
        local isPaused = CLN.VoiceoverPlayer._paused or (now._pausedForNativeVO)
        isActive = stillPlaying or isPaused
    end

    if isActive then
        local isQuest = not not now.questId
        local npcName = self:GetNpcNameById(now.npcId)
        local content = now.title
        local label = ReplayFrame.Pure.FormatEntryLabel(npcName, content, isQuest)
        local tooltip = ReplayFrame.Pure.FormatEntryTooltip(npcName, content)

        table.insert(entries, { isPlaying = true, label = label, tooltip = tooltip, entryType = now.entryType or (isQuest and "quest" or "unknown") })
    elseif now and (now.title or now.questId) and now.soundHandle then
        -- Stale currentlyPlaying: sound finished but object wasn't cleared.
        -- Push to history and clear it now.
        CLN.VoiceoverPlayer:PushToHistory(now)
        CLN.VoiceoverPlayer.currentlyPlaying = CLN.VoiceoverPlayer:GetCurrentlyPlayingObject()
    end

    if CLN.questsQueue then
        for i, q in ipairs(CLN.questsQueue) do
            local npcName = self:GetNpcNameById(q.npcId)
            local questTitle = q.title
            local label = ReplayFrame.Pure.FormatEntryLabel(npcName, questTitle, true)
            local tooltip = ReplayFrame.Pure.FormatEntryTooltip(npcName, questTitle)
            table.insert(entries, { queueIndex = i, label = label, tooltip = tooltip, entryType = q.entryType or "quest" })
        end
    end

    -- Append history entries (most recent first), pruning expired ones
    self:PruneOldHistory()
    local history = self:GetHistory()
    if history and #history > 0 then
        table.insert(entries, { isDivider = true, label = "— History —" })
        for i, h in ipairs(history) do
            local npcName = self:GetNpcNameById(h.npcId)
            local label = ReplayFrame.Pure.FormatEntryLabel(npcName, h.title, h.entryType == "quest")
            local tooltip = ReplayFrame.Pure.FormatEntryTooltip(npcName, h.title)
            table.insert(entries, {
                isHistory = true,
                historyIndex = i,
                label = label,
                tooltip = tooltip,
                entryType = h.entryType or "unknown",
                questId = h.questId,
                phase = h.phase,
                npcId = h.npcId,
                gender = h.gender,
                title = h.title,
                displayID = h.displayID,
            })
        end
    end

    return entries
end

-- Build or refresh the queue data provider used by the ScrollBox
function ReplayFrame:RefreshQueueDataProvider()
    if not (self.SetQueueData and self.QueueListFrame) then return end

    local entries = self:BuildQueueEntries()
    local nowPlayingIndex = (entries[1] and entries[1].isPlaying) and 1 or nil

    -- Compute how many rows fit, and keep the latest that fit (always include now playing)
    local rowsFit = 6
    if self.ContentFrame and self.ContentFrame.GetHeight then
        local h = self.ContentFrame:GetHeight() or 0
        local available = h - 36 - 8 -- subtract header + divider + padding
        if available < 20 then
            -- Not enough space for even one row — hide list entirely
            if self.QueueListFrame then self.QueueListFrame:Hide() end
            return
        end
        rowsFit = math.max(1, math.floor(available / 24))
    end
    -- Ensure list is visible when we have space
    if self.QueueListFrame and not self.QueueListFrame:IsShown() then
        self.QueueListFrame:Show()
    end
    -- Scroll-aware: show a window of entries based on scroll offset
    self._scrollOffset = self._scrollOffset or 0
    local maxOffset = math.max(0, #entries - rowsFit)
    if self._scrollOffset > maxOffset then self._scrollOffset = maxOffset end
    if self._scrollOffset < 0 then self._scrollOffset = 0 end

    local selected = {}
    local startIdx = self._scrollOffset + 1
    local endIdx = math.min(#entries, self._scrollOffset + rowsFit)
    for i = startIdx, endIdx do
        table.insert(selected, entries[i])
    end

    -- Feed directly to manual list (no scrolling)
    self:SetQueueData(selected)
    -- Update scroll indicator
    if self._scrollIndicator then
        local totalEntries = #entries
        if totalEntries > rowsFit and maxOffset > 0 then
            local listHeight = self.QueueListFrame and self.QueueListFrame:GetHeight() or 100
            local thumbHeight = math.max(12, listHeight * (rowsFit / totalEntries))
            local trackHeight = listHeight - thumbHeight
            local thumbOffset = (trackHeight > 0 and maxOffset > 0) and (trackHeight * (self._scrollOffset / maxOffset)) or 0
            self._scrollMaxOffset = maxOffset
            self._scrollIndicator:SetHeight(thumbHeight)
            self._scrollIndicator:ClearAllPoints()
            self._scrollIndicator:SetPoint("TOPRIGHT", self.QueueListFrame, "TOPRIGHT", 1, -thumbOffset)
            self._scrollIndicator:Show()
        else
            self._scrollMaxOffset = 0
            self._scrollIndicator:Hide()
        end
    end
end

-- Mark queue data dirty; coalesce refreshes to avoid churn during bursts
function ReplayFrame:MarkQueueDirty()
    -- Debounce: if already scheduled, just mark dirty and exit
    self._queueDirty = true
    self._scrollOffset = 0
    if self._queueDirtyPending then return end
    self._queueDirtyPending = true
    local delay = 0.12 -- slightly higher than old 0.05 to absorb bursts
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function()
            self._queueDirtyPending = nil
            if not self._queueDirty then return end
            self._queueDirty = false
            if self.RefreshQueueDataProvider then self:RefreshQueueDataProvider() end
            if self.ApplyQueueTextScale then self:ApplyQueueTextScale() end
            if self.UpdateQueueBadge then self:UpdateQueueBadge() end
        end)
    else
        -- Fallback: immediate
        self._queueDirtyPending = nil
        self._queueDirty = false
        self:RefreshQueueDataProvider()
        if self.ApplyQueueTextScale then self:ApplyQueueTextScale() end
        if self.UpdateQueueBadge then self:UpdateQueueBadge() end
    end
end

-- =============================
-- Visibility and header helpers
-- =============================

-- Centralized header builder (wraps pure version)
function ReplayFrame:BuildHeaderText(playingTitle, npcName, isQuest, qcount, collapsed)
    return ReplayFrame.Pure.BuildHeaderText(playingTitle, npcName, isQuest, qcount, collapsed)
end

-- Show/hide frame, user-hidden/minimized handling; returns true if visible and should continue
function ReplayFrame:UpdateVisibility()
    local forced = self._forceShow
    local alwaysShow = CLN and CLN.db and CLN.db.profile and CLN.db.profile.alwaysShowReplayFrame
    if (not forced) and (not alwaysShow) and (not self:IsShowReplayFrameToggleIsEnabled() or not CLN.VoiceoverPlayer.currentlyPlaying) then
        if (self.DisplayFrame) then self.DisplayFrame:Hide() end
        if self.MinButton then self.MinButton:Hide() end
        if self.HideSubtitle then self:HideSubtitle() end
        self.userHidden = false
        return false
    end

    if (not forced) and (not alwaysShow) and (not self:IsVoiceoverCurrenltyPlaying() and self:IsQuestQueueEmpty()) then
        if (self.DisplayFrame) then self.DisplayFrame:Hide() end
        if self.MinButton then self.MinButton:Hide() end
        if self.HideSubtitle then self:HideSubtitle() end
        self.userHidden = false
        return false
    end

    if (not forced) and (not alwaysShow) and (self:IsDisplayFrameHideNeeded()) then
        if self.DisplayFrame then self.DisplayFrame:Hide() end
        if self.MinButton then self.MinButton:Hide() end
        if self.HideSubtitle then self:HideSubtitle() end
        self.userHidden = false
        return false
    end

    -- Respect user-hidden during playback: keep minimized indicator instead of reopening
    if (not forced) and self.userHidden and self:IsVoiceoverCurrenltyPlaying() then
        self:EnsureMinimizedButton()
        if self.MinButton then self.MinButton:Show() end
        if self.HideSubtitle then self:HideSubtitle() end
        return false
    end

    self:UpdateParent()
    if self.DisplayFrame then self.DisplayFrame:Show() end
    -- Clear stuck animation flags on frame show
    self._animatingCollapse = false
    if self.DisplayFrame then self.DisplayFrame._animatingCollapse = false end
    -- First-time edit mode glow hint
    if self.StartEditGlowPulse and not self._glowTriggered then
        self._glowTriggered = true
        if C_Timer and C_Timer.After then
            C_Timer.After(1.0, function()
                if self.StartEditGlowPulse then self:StartEditGlowPulse() end
            end)
        end
    end
    if self.MinButton then self.MinButton:Hide() end
    self:CheckAndShowModel()
    self.userHidden = false
    return true
end

-- Combat auto-collapse: hide frame during combat (FSM skips all frame
-- manipulation in combat lockdown, so showing a stale frame is worse than hiding)
function ReplayFrame:OnCombatStart()
    if CLN and CLN.db and CLN.db.profile and CLN.db.profile.combatAutoCollapse == false then return end
    if self.DisplayFrame and self.DisplayFrame:IsShown() then
        self._combatAutoCollapsed = true
        self.DisplayFrame:Hide()
    end
    if self.NpcModelFrame then self.NpcModelFrame:Hide() end
    if self.ModelContainer then self.ModelContainer:Hide() end
end

function ReplayFrame:OnCombatEnd()
    if self._combatAutoCollapsed then
        self._combatAutoCollapsed = nil
        if self.UpdateDisplayFrameState then self:UpdateDisplayFrameState() end
    end
end

-- List refresh debounce/dirty handling
function ReplayFrame:RefreshListIfNeeded(sig, nowT)
    local needRefresh = false
    if self._lastDisplaySig == sig then
        local dt = nowT - (self._lastDisplaySigT or 0)
        if dt >= 0.25 then
            needRefresh = true
        end
    else
        needRefresh = true
    end
    if self._queueDirty then
        needRefresh = true
        self._queueDirty = false
    end
    if needRefresh then
        self:RefreshQueueDataProvider()
        if self.ApplyQueueTextScale then self:ApplyQueueTextScale() end
        self._lastDisplaySig = sig
        self._lastDisplaySigT = nowT
    end
end

-- Visible + playing animation update helper
function ReplayFrame:UpdateAnimationsIfNeeded()
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local playing = self:IsVoiceoverCurrenltyPlaying()
    -- Consider both the model frame and its container, and prefer IsVisible
    local shown = false
    if self.NpcModelFrame and self.NpcModelFrame.IsVisible and self.NpcModelFrame:IsVisible() then shown = true end
    if (not shown) and self.ModelContainer and self.ModelContainer.IsVisible and self.ModelContainer:IsVisible() then shown = true end
    if (not shown) and self.NpcModelFrame and self.NpcModelFrame.IsShown and self.NpcModelFrame:IsShown() then shown = true end
    if (not shown) and self.ModelContainer and self.ModelContainer.IsShown and self.ModelContainer:IsShown() then shown = true end
    local inGrace = false
    if cur and cur.startTime and GetTime then
        local dt = GetTime() - (cur.startTime or 0)
        inGrace = dt >= 0 and dt < 0.6
    end
    if (playing or inGrace) and shown and self.UpdateConversationAnimation then
    if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.modelFrame) then
        CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.modelFrame, string.format("UpdateDisplayFrame - calling UpdateConversationAnimation (shown=%s, playing=%s, grace=%s)", tostring(shown), tostring(playing), tostring(inGrace)))
    end
        self:UpdateConversationAnimation()
        -- Show subtitle if enabled and not already showing
        if self.ShowSubtitle and not self._subtitleSentences then
            local cur2 = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
            if cur2 and cur2.title then
                self:ShowSubtitle(cur2.title)
            end
        end
    else
    if CLN.Utils and CLN.Utils.ShouldLogAnimDebug and CLN.Utils:ShouldLogAnimDebug(CLN.Utils.LogCategories.modelFrame) then
        CLN.Utils:LogAnimDebug(CLN.Utils.LogCategories.modelFrame, string.format("UpdateDisplayFrame - skipping UpdateConversationAnimation (shown=%s, playing=%s, grace=%s)", tostring(shown), tostring(playing), tostring(inGrace)))
    end
        -- If we are playing but not yet visible, schedule a short deferred retry
        if (playing or inGrace) and (not shown) and (not self._deferAnimTimer) and C_Timer and C_Timer.After then
            self._deferAnimTimer = true
            C_Timer.After(0.1, function()
                self._deferAnimTimer = nil
                if self.UpdateAnimationsIfNeeded then self:UpdateAnimationsIfNeeded() end
            end)
        end
    end
end

-- Main update function for the display frame
function ReplayFrame:UpdateDisplayFrame()
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
    local qcount = (CLN.questsQueue and #CLN.questsQueue or 0)
    local collapsed = self.CollapseButton and self.CollapseButton._collapsed or false
    local w = self.DisplayFrame and self.DisplayFrame.GetWidth and math.floor((self.DisplayFrame:GetWidth() or 0) + 0.5) or 0
    local h = self.DisplayFrame and self.DisplayFrame.GetHeight and math.floor((self.DisplayFrame:GetHeight() or 0) + 0.5) or 0
    local handle = cur and cur.soundHandle or nil
    local title = cur and cur.title or nil
    local playing = cur and cur.isPlaying and cur:isPlaying() or false
    local sig = table.concat({ tostring(handle), tostring(title or ""), qcount, collapsed and 1 or 0, w, h, playing and 1 or 0 }, ":")
    local nowT = GetTime and GetTime() or 0

    -- Early visibility checks and show/min logic
    if not self:UpdateVisibility() then return end

    -- Self-healing: detect stuck collapsed state (height too small but not collapsed)
    if not collapsed and not self._combatAutoCollapsed
        and not self._animatingCollapse
        and not (self.DisplayFrame and self.DisplayFrame._animatingCollapse)
        and h > 0 and h < 80
    then
        local safeH = self:GetSafeExpandHeight()
        if safeH and safeH >= 80 and self.DisplayFrame and self.DisplayFrame.SetHeight then
            self.DisplayFrame:SetHeight(safeH)
        end
    end

    if (self.HeaderText) then
        local qcount = (CLN.questsQueue and #CLN.questsQueue or 0)
        local cur2 = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
        local playingTitle = cur2 and cur2.title or nil
        local npcName = cur2 and self:GetNpcNameById(cur2.npcId) or nil
        local isQuest = cur2 and cur2.questId or nil
        local collapsed2 = self.CollapseButton and self.CollapseButton._collapsed
        local header = self:BuildHeaderText(playingTitle, npcName, isQuest, qcount, collapsed2)
        self:ApplyHeaderTruncation(self.HeaderText, header)
    end

    -- Refresh the ScrollBox list from current state
    -- Refresh list if needed
    self:RefreshListIfNeeded(sig, nowT)

    -- Animation updates gated by visibility and playback
    self:UpdateAnimationsIfNeeded()
    if self.UpdateProgressBar then self:UpdateProgressBar() end

end

-- Update display frame state
function ReplayFrame:UpdateDisplayFrameState()
    if self._editMode or self._isDragging then return end
    if self.GetDisplayFrame then self:GetDisplayFrame() end
    self:UpdateDisplayFrame()
end

-- ============================================================================
-- ACCESSIBILITY AND SCALING
-- ============================================================================

-- Get accessibility text scale from CVars
function ReplayFrame:GetAccessibilityTextScale()
    if C_CVar and C_CVar.GetCVar then
        local keys = { "uiTextScale", "textScale", "uiTextSize" }
        for _, key in ipairs(keys) do
            local ok, val = pcall(C_CVar.GetCVar, key)
            if ok and val then
                local num = tonumber(val)
                if num and num > 0 then
                    return num
                end
            end
        end
    end
    return 1
end

-- Apply text scaling to queue and header text
function ReplayFrame:ApplyQueueTextScale()
    local userScale = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.queueTextScale) or 1.0
    local a11y = self:GetAccessibilityTextScale() or 1
    local finalScale = math.max(0.5, math.min(2.0, userScale * a11y))

    -- Skip if effectively unchanged (epsilon)
    if self._lastQueueTextScale and math.abs((self._lastQueueTextScale or 0) - finalScale) < 0.001 then
        return
    end
    self._lastQueueTextScale = finalScale

    -- Header
    if self.HeaderText and self.DisplayFrame then
        local h = self.DisplayFrame:GetHeight() or 165
        local base = math.max(10, math.min(20, math.floor(h / 8)))
        self.HeaderText:SetFont("Fonts\\FRIZQT__.TTF", base * finalScale, "")
    end

    -- Active rows only
    if self.QueueScrollBox then
        local baseHeight = 12
        -- Manual rows only
        if self.QueueRows and #self.QueueRows > 0 then
            for _, row in ipairs(self.QueueRows) do
                if row:IsShown() and row.text then
                    local _, _, flags = row.text:GetFont()
                    row.text:SetFont("Fonts\\FRIZQT__.TTF", baseHeight * finalScale, flags)
                    -- Re-fit the text to the new size/scale
                    if self.FitRowText then self:FitRowText(row) end
                end
                if row:IsShown() and row.bulletTex and row.bulletTex.SetSize then
                    local sz = math.max(3, math.floor((baseHeight * finalScale) * 0.33))
                    row.bulletTex:SetSize(sz, sz)
                end
            end
        end
    end
end

-- Modules are loaded via .toc; dev-time loadfile fallbacks removed for clarity.
