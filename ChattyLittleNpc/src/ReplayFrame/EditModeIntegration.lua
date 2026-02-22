---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- ============================================================================
-- Blizzard Edit Mode Integration (per-layout settings for ChattyLittleNpc)
-- ============================================================================
-- Provides: per-layout persistence of frameScale, queueTextScale, frameSize,
-- npcModelFrameHeight, position; overlay highlight + drag/resize while in
-- Edit Mode; injected button on Edit Mode UI to open addon edit panel.
-- ============================================================================

local Integration = {}
ReplayFrame.EditModeIntegration = Integration

-- Blizzard reserves two internal presets (Modern=0, Classic=1) that don't appear in the
-- returned layouts list we enumerate. We treat them as hidden so any numeric prefixing
-- or index correlation with C_EditMode.activeLayout must subtract this offset.
local HIDDEN_BASE_LAYOUTS = 2

local function logDebug(msg)
    if CLN and CLN.Logger then CLN.Logger:debug(msg, false, CLN.Utils.LogCategories.ui) end
end
local function logInfo(msg, chat)
    if CLN and CLN.Logger then CLN.Logger:info(msg, chat or false, CLN.Utils.LogCategories.ui) end
end

local hasAPI = (C_EditMode and type(C_EditMode.GetLayouts) == "function")
-- Marker for appended Chatty settings bundle versioned
local BUNDLE_MARK = "#CLN1#"

local function ensureStore()
    CLN.db.profile.editModeLayouts = CLN.db.profile.editModeLayouts or {}
    return CLN.db.profile.editModeLayouts
end

local function ensureExcludeConfig()
    local p = CLN.db.profile
    p.editModeExclude = p.editModeExclude or {
        frameScale = false,
        queueTextScale = false,
        frameSize = false,
        npcModelFrameHeight = false,
        framePos = false,
    }
    return p.editModeExclude
end

-- One-time migration: move any legacy displayFramePos keys to framePos (unified naming)
local migratedPositions = false
local function migratePositions()
    if migratedPositions then return end
    local store = CLN.db and CLN.db.profile and CLN.db.profile.editModeLayouts
    if not store then return end
    for name, bucket in pairs(store) do
        if bucket.displayFramePos and not bucket.framePos then
            local p = bucket.displayFramePos
            bucket.framePos = { point = p.point, relativePoint = p.relPoint or p.relativePoint, x = p.x, y = p.y }
            bucket.displayFramePos = nil
        end
    end
    migratedPositions = true
end

---@return string|nil activeLayoutName
function Integration:GetActiveLayoutName()
    if not hasAPI then return nil end
    local ok, layouts = pcall(C_EditMode.GetLayouts)
    if not ok or not layouts or not layouts.layouts then return nil end
    local list = layouts.layouts
    local idx = tonumber(layouts.activeLayout)
    -- Primary: direct index lookup (expected API contract)
    if idx then
        -- Direct attempt (some clients may already align)
        if list[idx] and list[idx].layoutName then
            return list[idx].layoutName
        end
        -- Adjust for hidden Modern/Classic presets (activeLayout uses full list including them)
        local adj = idx - HIDDEN_BASE_LAYOUTS
        if adj >= 1 and list[adj] and list[adj].layoutName then
            if CLN and CLN.Logger then
                CLN.Logger:debug(string.format("Active layout index %d adjusted -> %d (hidden base=%d)", idx, adj, HIDDEN_BASE_LAYOUTS), false, CLN.Utils.LogCategories.ui)
            end
            return list[adj].layoutName
        end
    end
    -- Fallback 1: scan for explicit active flag Blizzard sometimes exposes
    for i, l in ipairs(list) do
        if l.isActive or l.active or l.isLayoutActive then
            if CLN and CLN.Logger then
                CLN.Logger:debug("Active layout determined by isActive flag scan (index="..i..")", false, CLN.Utils.LogCategories.ui)
            end
            return l.layoutName
        end
    end
    -- Fallback 2: some users report index offset (+2). Probe nearby indices.
    if idx then
        for shift = -3, 3 do
            local cand = list[idx + shift]
            if cand and cand.layoutName and (cand.isActive or cand.active or cand.isLayoutActive) then
                if CLN and CLN.Logger then
                    CLN.Logger:debug("Active layout index adjusted by "..shift.." (reported="..tostring(idx)..")", false, CLN.Utils.LogCategories.ui)
                end
                return cand.layoutName
            end
        end
    end
    -- Fallback 3: last resort: return first entry (least desirable but better than nil)
    if list[1] and list[1].layoutName then
        if CLN and CLN.Logger then
            CLN.Logger:warn("Could not confidently determine active layout; defaulting to first entry", false, CLN.Utils.LogCategories.ui)
            -- Provide diagnostic dump
            for i,l in ipairs(list) do
                CLN.Logger:debug(string.format("Layout[%d] name=%s activeFlags=%s%s%s", i, l.layoutName or "?", l.isActive and "isActive " or "", l.active and "active " or "", l.isLayoutActive and "isLayoutActive" or ""), false, CLN.Utils.LogCategories.ui)
            end
        end
        return list[1].layoutName
    end
    return nil
end

-- Persist current profile settings to the active layout bucket
function Integration:PersistCurrentToLayout()
    local name = self:GetActiveLayoutName()
    if not name then return end
    local store = ensureStore()
    local bucket = store[name] or {}
    local exclude = ensureExcludeConfig()
    bucket.frameScale = CLN.db.profile.frameScale
    bucket.queueTextScale = CLN.db.profile.queueTextScale
    bucket.frameSize = CLN.db.profile.frameSize and {
        width = CLN.db.profile.frameSize.width,
        height = CLN.db.profile.frameSize.height
    } or nil
    bucket.npcModelFrameHeight = CLN.db.profile.npcModelFrameHeight
    if ReplayFrame.DisplayFrame then
        local p, _, r, x, y = ReplayFrame.DisplayFrame:GetPoint(1)
        bucket.framePos = { point = p, relativePoint = r, x = x, y = y }
    end
    -- Respect opt-out by clearing values (so they won't override later)
    if exclude.frameScale then bucket.frameScale = nil end
    if exclude.queueTextScale then bucket.queueTextScale = nil end
    if exclude.frameSize then bucket.frameSize = nil end
    if exclude.npcModelFrameHeight then bucket.npcModelFrameHeight = nil end
    if exclude.framePos then bucket.framePos = nil end
    store[name] = bucket
    logInfo("Saved per-layout settings for '"..name.."'")
end

-- Apply stored settings for layout if present
function Integration:ApplyLayout(name)
    if not name then return end
    local store = CLN.db.profile.editModeLayouts
    local data = store and store[name]
    if not data then logDebug("No saved settings for layout '"..name.."'") return end
    local exclude = ensureExcludeConfig()
    local changed = false
    if data.frameScale and not exclude.frameScale and data.frameScale ~= CLN.db.profile.frameScale then
        CLN.db.profile.frameScale = data.frameScale
        if ReplayFrame.ApplyFrameScale then ReplayFrame:ApplyFrameScale() end
        changed = true
    end
    if data.queueTextScale and not exclude.queueTextScale and data.queueTextScale ~= CLN.db.profile.queueTextScale then
        CLN.db.profile.queueTextScale = data.queueTextScale
        if ReplayFrame.ApplyQueueTextScale then ReplayFrame:ApplyQueueTextScale() end
        changed = true
    end
    if data.frameSize and not exclude.frameSize and data.frameSize.width and data.frameSize.height then
        CLN.db.profile.frameSize = { width = data.frameSize.width, height = data.frameSize.height }
        if ReplayFrame.DisplayFrame then
            ReplayFrame.DisplayFrame:SetSize(data.frameSize.width, data.frameSize.height)
            if ReplayFrame.Relayout then ReplayFrame:Relayout() end
        end
        changed = true
    end
    if data.npcModelFrameHeight and not exclude.npcModelFrameHeight and data.npcModelFrameHeight ~= CLN.db.profile.npcModelFrameHeight then
        CLN.db.profile.npcModelFrameHeight = data.npcModelFrameHeight
        if ReplayFrame.NpcModelFrame then
            ReplayFrame.NpcModelFrame:SetHeight(data.npcModelFrameHeight)
            if ReplayFrame.Relayout then ReplayFrame:Relayout() end
        end
        changed = true
    end
    local pos = (not exclude.framePos) and (data.framePos or data.displayFramePos) or nil -- accept legacy key
    if pos and ReplayFrame.DisplayFrame and pos.point and (pos.relativePoint or pos.relPoint) then
        local rp = pos.relativePoint or pos.relPoint
        ReplayFrame.DisplayFrame:ClearAllPoints()
        ReplayFrame.DisplayFrame:SetPoint(pos.point, UIParent, rp, pos.x or 0, pos.y or 0)
        -- also write back to profile global framePos for other systems consistency
        CLN.db.profile.framePos = { point = pos.point, relativePoint = rp, xOfs = pos.x or 0, yOfs = pos.y or 0 }
    end
    if changed then logInfo("Applied settings for layout '"..name.."'") else logDebug("Layout '"..name.."' already matched current settings") end
end

-- Overlay for drag/resize when Edit Mode is open
function Integration:EnsureOverlay()
    if self.overlay or not ReplayFrame.DisplayFrame then return end
    local parent = ReplayFrame.DisplayFrame
    local ov = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ov:SetAllPoints(parent)
    ov:Hide()
    ov:SetFrameStrata("FULLSCREEN_DIALOG")
    ov:SetFrameLevel(parent:GetFrameLevel() + 50)
    -- Border (retain tooltip style for clear contrast)
    ov:SetBackdrop({ edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 12, insets = { left=2,right=2,top=2,bottom=2 } })
    ov:SetBackdropBorderColor(1.0,0.82,0,0.85)

    -- Legacy visual polish: subtle blue base fill + brighter hover layer
    local baseFill = ov:CreateTexture(nil, "BACKGROUND")
    baseFill:SetAllPoints()
    -- #7299AA (0.447, 0.600, 0.667) @ 0.20 alpha
    baseFill:SetColorTexture(0.447, 0.600, 0.667, 0.20)
    ov._baseFill = baseFill

    local hoverFill = ov:CreateTexture(nil, "BACKGROUND")
    hoverFill:SetAllPoints()
    -- #A9DBED (0.663, 0.859, 0.929) @ 0.30 alpha
    hoverFill:SetColorTexture(0.663, 0.859, 0.929, 0.30)
    hoverFill:Hide()
    ov._hoverFill = hoverFill

    -- Simple 1px inner border (hover color) for sharper silhouette
    local inner = {}
    local edges = {"TOP","BOTTOM","LEFT","RIGHT"}
    for _, edge in ipairs(edges) do
        local t = ov:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.663, 0.859, 0.929, 0.85)
        if edge == "TOP" then
            t:SetPoint("TOPLEFT", 1, -1)
            t:SetPoint("TOPRIGHT", -1, -1)
            t:SetHeight(1)
        elseif edge == "BOTTOM" then
            t:SetPoint("BOTTOMLEFT", 1, 1)
            t:SetPoint("BOTTOMRIGHT", -1, 1)
            t:SetHeight(1)
        elseif edge == "LEFT" then
            t:SetPoint("TOPLEFT", 1, -1)
            t:SetPoint("BOTTOMLEFT", 1, 1)
            t:SetWidth(1)
        elseif edge == "RIGHT" then
            t:SetPoint("TOPRIGHT", -1, -1)
            t:SetPoint("BOTTOMRIGHT", -1, 1)
            t:SetWidth(1)
        end
        table.insert(inner, t)
    end
    ov._innerBorder = inner

    ov:EnableMouse(true)
    ov:SetMovable(true)
    ov:RegisterForDrag("LeftButton")
    ov:SetScript("OnDragStart", function(f)
        if InCombatLockdown and InCombatLockdown() then return end
        f._dragging = true
        parent:StartMoving()
    end)
    ov:SetScript("OnDragStop", function(f)
        parent:StopMovingOrSizing(); f._dragging = nil
        if ReplayFrame.SaveFramePosition then ReplayFrame:SaveFramePosition() end
        self:PersistCurrentToLayout()
    end)

    -- Hover feedback for polish (do not interfere with drag state)
    ov:SetScript("OnEnter", function(f)
        if f._hoverFill then f._hoverFill:Show() end
    end)
    ov:SetScript("OnLeave", function(f)
        if f._hoverFill and not f._dragging and not f._resizing then f._hoverFill:Hide() end
    end)

    local grip = CreateFrame("Frame", nil, ov)
    grip:SetPoint("BOTTOMRIGHT")
    grip:SetSize(18,18)
    grip:EnableMouse(true)
    local tex = grip:CreateTexture(nil,"OVERLAY")
    tex:SetAllPoints(); tex:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function(g,btn)
        if btn~="LeftButton" or (InCombatLockdown and InCombatLockdown()) then return end
        parent:StartSizing("BOTTOMRIGHT"); g._resizing=true
    end)
    grip:SetScript("OnMouseUp", function(g)
        parent:StopMovingOrSizing(); g._resizing=nil
        if ReplayFrame.SaveFramePosition then ReplayFrame:SaveFramePosition() end
        self:PersistCurrentToLayout()
        if ReplayFrame.Relayout then ReplayFrame:Relayout() end
    if ov._hoverFill then ov._hoverFill:Hide() end
    end)
    -- Lock awareness: disable drag/resize if frame locked
    function ov:RefreshLockState()
        local locked = ReplayFrame.IsFrameLocked and ReplayFrame:IsFrameLocked()
        if locked then
            ov:EnableMouse(true) -- allow hover/tooltip
            ov:SetScript("OnDragStart", nil)
            if grip then grip:EnableMouse(false) end
        else
            grip:EnableMouse(true)
            ov:SetScript("OnDragStart", function(f)
                if InCombatLockdown and InCombatLockdown() then return end
                f._dragging = true; parent:StartMoving()
            end)
        end
    end
    ov:RefreshLockState()

    ov:SetScript("OnEnter", function(f)
        if f._hoverFill then f._hoverFill:Show() end
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(f, "ANCHOR_TOPLEFT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Chatty Little NPC", 1,1,1)
            local locked = ReplayFrame.IsFrameLocked and ReplayFrame:IsFrameLocked()
            if locked then
                GameTooltip:AddLine("Locked: unlock to drag/resize.", 0.85,0.85,0.85,true)
            else
                GameTooltip:AddLine("Drag to move (Shift=1px, Ctrl=20px arrow nudge).", 0.85,0.85,0.85,true)
            end
            GameTooltip:AddLine("Click frame to open settings.", 0.75,0.75,0.75,true)
            GameTooltip:Show()
        end
    end)
    ov:SetScript("OnLeave", function(f)
        if f._hoverFill and not f._dragging and not f._resizing then f._hoverFill:Hide() end
        if GameTooltip_Hide then GameTooltip_Hide() end
    end)
    -- Simple click (no drag) opens settings; overlay eats clicks so provide here
    ov:SetScript("OnMouseDown", function(f, btn)
        if btn ~= "LeftButton" then return end
        f._clickStartTime = GetTime and GetTime() or 0
        local x,y = GetCursorPosition(); f._clickStartX, f._clickStartY = x,y
    end)
    ov:SetScript("OnMouseUp", function(f, btn)
        if btn ~= "LeftButton" then return end
        if f._dragging or f._resizing then return end
        local x,y = GetCursorPosition(); local dx=(x or 0)-(f._clickStartX or 0); local dy=(y or 0)-(f._clickStartY or 0)
        local dist2 = dx*dx + dy*dy
        local elapsed = (GetTime and GetTime() or 0) - (f._clickStartTime or 0)
        if dist2 < 25*25 and elapsed < 0.75 then
            if ReplayFrame and ReplayFrame.ShowEditPanel then ReplayFrame:ShowEditPanel() end
        end
    end)
    self.overlay = ov
    -- Layout badge (updates dynamically)
    local badgeHolder = CreateFrame("Frame", nil, ov, "BackdropTemplate")
    badgeHolder:SetPoint("TOPLEFT", 4, -4)
    badgeHolder:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 8, insets = {left=2,right=2,top=2,bottom=2} })
    badgeHolder:SetBackdropColor(0,0,0,0.40)
    badgeHolder:SetBackdropBorderColor(0.663, 0.859, 0.929, 0.6)
    badgeHolder:SetSize(10, 20) -- minimal until we know text
    local badge = badgeHolder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    badge:SetPoint("LEFT", 4, 0)
    badge:SetText("") -- no placeholder text; hide until resolved
    badgeHolder:Hide()
    ov._badgeHolder = badgeHolder
    ov._badge = badge

    -- Arrow key usage hint (only show once unless user resets debug)
    local hint = ov:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPRIGHT", -6, -6)
    hint:SetText("Arrows: move (Shift=1,Ctrl=20)")
    hint:Hide()
    ov._hint = hint
    if CLN.db and CLN.db.profile and CLN.db.profile.debugMode and not CLN.db.profile._editModeArrowHintShown then
        hint:Show()
        C_Timer.After(6, function()
            if hint and hint:IsShown() then hint:Hide() end
            if CLN.db and CLN.db.profile then CLN.db.profile._editModeArrowHintShown = true end
        end)
    end

    -- Debug glows for key buttons (re-uses action button border look): only if debugMode
    local function addGlow(target)
        if not (target and target.CreateTexture) then return end
        if target._clnGlow then return end
        local g = target:CreateTexture(nil, "OVERLAY")
        g:SetTexture("Interface/Buttons/UI-ActionButton-Border")
        g:SetBlendMode("ADD")
        g:SetAllPoints(target)
        g:SetAlpha(0.0)
        target._clnGlow = g
    end
    if CLN.db and CLN.db.profile and CLN.db.profile.debugMode then
        addGlow(ReplayFrame.OptionsButton)
        addGlow(ReplayFrame.ClearButton)
        addGlow(ReplayFrame.CollapseButton)
        addGlow(ReplayFrame.EditModeButton)
        if ReplayFrame.ResizeGrip then addGlow(ReplayFrame.ResizeGrip) end
        ov._debugGlowActive = true
    end
    function ov:RefreshDebugGlows(show)
        if not ov._debugGlowActive then return end
        local a = show and 0.9 or 0.0
        local btns = { ReplayFrame.OptionsButton, ReplayFrame.ClearButton, ReplayFrame.CollapseButton, ReplayFrame.EditModeButton, ReplayFrame.ResizeGrip }
        for _, b in ipairs(btns) do if b and b._clnGlow then b._clnGlow:SetAlpha(a) end end
    end

    ov:EnableKeyboard(true)
    ov:SetPropagateKeyboardInput(true)
    ov:SetScript("OnKeyDown", function(frame, key)
        -- Keyboard nudging (only when not dragging/resizing)
        if frame._dragging or frame._resizing then return end
        local locked = ReplayFrame.IsFrameLocked and ReplayFrame:IsFrameLocked()
        if locked then return end
        local moveKeys = { LEFT = true, RIGHT = true, UP = true, DOWN = true }
        if not moveKeys[key] then return end
        local px = 5
        if IsShiftKeyDown and IsShiftKeyDown() then px = 1 end
        if IsControlKeyDown and IsControlKeyDown() then px = 20 end
        local dx, dy = 0,0
        if key == "LEFT" then dx = -px elseif key == "RIGHT" then dx = px elseif key == "UP" then dy = px elseif key == "DOWN" then dy = -px end
        if ReplayFrame.DisplayFrame then
            local p, _, r, x, y = ReplayFrame.DisplayFrame:GetPoint(1)
            ReplayFrame.DisplayFrame:ClearAllPoints()
            ReplayFrame.DisplayFrame:SetPoint(p or "CENTER", UIParent, r or "CENTER", (x or 0)+dx, (y or 0)+dy)
            if ReplayFrame.SaveFramePosition then ReplayFrame:SaveFramePosition() end
            Integration:PersistCurrentToLayout()
        end
    end)
end

function Integration:ShowOverlay()
    if not hasAPI then return end
    self:EnsureOverlay()
    if self.overlay then
        -- Enable resizing during edit mode
        if ReplayFrame.DisplayFrame and ReplayFrame.DisplayFrame.SetResizable then
            ReplayFrame.DisplayFrame:SetResizable(true)
        end
        self.overlay:Show()
        -- Auto focus overlay for arrow key nudging
        self.overlay:SetPropagateKeyboardInput(false)
        -- Some Frame types (non-EditBox) lack SetFocus; safeguard to avoid Lua error
        if self.overlay.SetFocus then
            self.overlay:SetFocus()
        else
            -- Ensure it still receives key presses
            if self.overlay.EnableKeyboard then self.overlay:EnableKeyboard(true) end
            if CLN and CLN.Logger then
                CLN.Logger:debug("Overlay has no SetFocus; enabled keyboard input instead", false, CLN.Utils.LogCategories.ui)
            end
        end
        -- Only flash badge holder briefly when first showing in session
        if not self._badgeFlashDone then
            self._badgeFlashDone = true
            if self.overlay._badgeHolder then
                self.overlay._badgeHolder.fade = self.overlay._badgeHolder:CreateAnimationGroup()
                local a1 = self.overlay._badgeHolder.fade:CreateAnimation("Alpha")
                a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.25)
                self.overlay._badgeHolder.fade:Play()
            end
        end
        if CLN.db and CLN.db.profile and CLN.db.profile.debugMode then
            if self.overlay.RefreshDebugGlows then self.overlay:RefreshDebugGlows(true) end
        end
        -- Provide sample queue contents if nothing active for easier styling
        self:InjectSampleDataIfNeeded()
    end
end
function Integration:HideOverlay()
    if self.overlay then
        -- Disable resizing outside edit mode
        if ReplayFrame.DisplayFrame and ReplayFrame.DisplayFrame.SetResizable then
            ReplayFrame.DisplayFrame:SetResizable(false)
        end
        if self.overlay.RefreshDebugGlows then self.overlay:RefreshDebugGlows(false) end
        self.overlay:Hide()
        -- If we injected sample entries, restore the real queue now
        if ReplayFrame and ReplayFrame._editModeSamples then
            ReplayFrame._editModeSamples = nil
            if ReplayFrame.SetQueueData and ReplayFrame.BuildQueueEntries then
                ReplayFrame:SetQueueData(ReplayFrame:BuildQueueEntries())
            end
            if ReplayFrame.ApplyQueueTextScale then ReplayFrame:ApplyQueueTextScale() end
            if CLN and CLN.Logger then CLN.Logger:debug("Cleared sample queue entries after hiding overlay", false, CLN.Utils.LogCategories.ui) end
        end
    end
end

-- Inject sample rows for styling when queue empty & nothing playing
function Integration:InjectSampleDataIfNeeded()
    if not ReplayFrame or not ReplayFrame.SetQueueData then return end
    local realCount = (CLN.questsQueue and #CLN.questsQueue or 0)
    local playing = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
    if realCount > 0 or playing then return end
    if ReplayFrame._editModeSamples then return end
    local samples = {
        { isPlaying = true, label = "[Now Playing] Sample: The Fallen Watcher", tooltip = "Sample active narration" },
        { label = "Camp Torchlighting", tooltip = "Sample queued quest #1" },
        { label = "A Delicate Delivery", tooltip = "Sample queued quest #2" },
        { label = "Secrets in the Dust", tooltip = "Sample queued quest #3" },
        { label = "Tide of Shadows", tooltip = "Sample queued quest #4" },
    }
    ReplayFrame._editModeSamples = samples
    ReplayFrame:SetQueueData(samples)
    if ReplayFrame.ApplyQueueTextScale then ReplayFrame:ApplyQueueTextScale() end
end

-- Event wiring
function Integration:Init()
    if self._init or not hasAPI then return end
    migratePositions()
    ensureExcludeConfig()
    -- EDIT_MODE_LAYOUTS_UPDATED -> apply active layout bucket
    local f = CreateFrame("Frame")
    f:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_,evt)
        if evt == "EDIT_MODE_LAYOUTS_UPDATED" then
            -- Defer slightly to let Blizzard finalize internal state
            C_Timer.After(0.05, function()
                local name = self:GetActiveLayoutName()
                if name then self:ApplyLayout(name) end
                self:UpdateLayoutBadge()
                -- Also refresh badge inside settings panel if it's open
                if ReplayFrame and ReplayFrame._editPanel and ReplayFrame._editPanel:IsShown() and ReplayFrame._editPanel.RefreshLayoutBadge then
                    ReplayFrame._editPanel:RefreshLayoutBadge()
                end
            end)
        elseif evt == "PLAYER_REGEN_ENABLED" then
            if self._pendingApplyLayout then
                local n = self._pendingApplyLayout; self._pendingApplyLayout=nil; self:ApplyLayout(n)
            end
            if self._pendingPersist then self._pendingPersist=false; self:PersistCurrentToLayout() end
        end
    end)
    self.eventFrame = f

    -- Hook Edit Mode exit to hide overlay + clean samples + auto-hide frame if empty
    if C_EditMode and C_EditMode.OnEditModeExit then
        hooksecurefunc(C_EditMode, "OnEditModeExit", function()
            self:HideOverlay()
            if ReplayFrame and ReplayFrame._editModeSamples then
                ReplayFrame._editModeSamples = nil
                if ReplayFrame.SetQueueData then
                    ReplayFrame:SetQueueData(ReplayFrame:BuildQueueEntries())
                end
                if ReplayFrame.ApplyQueueTextScale then ReplayFrame:ApplyQueueTextScale() end
            end
            if ReplayFrame and ReplayFrame.DisplayFrame then
                local playing = ReplayFrame.IsVoiceoverCurrenltyPlaying and ReplayFrame:IsVoiceoverCurrenltyPlaying()
                local empty = ReplayFrame.IsQuestQueueEmpty and ReplayFrame:IsQuestQueueEmpty()
                if not playing and empty and not ReplayFrame._manualEdit then
                    ReplayFrame.DisplayFrame:Hide()
                end
            end
        end)
    end

    -- Inject button into Edit Mode UI when available
    local elapsed = 0
    self._ticker = C_Timer.NewTicker(0.5, function(t)
        elapsed = elapsed + 0.5
        if EditModeManagerFrame then
            if not self._buttonInjected then
                local b = CreateFrame("Button", nil, EditModeManagerFrame, "UIPanelButtonTemplate")
                b:SetSize(120,20)
                b:SetText("Chatty NPC")
                if EditModeManagerFrame.RevertAllChangesButton then
                    b:SetPoint("TOPLEFT", EditModeManagerFrame.RevertAllChangesButton, "BOTTOMLEFT", 0, -6)
                else
                    b:SetPoint("BOTTOMLEFT", EditModeManagerFrame, "BOTTOMLEFT", 16, 16)
                end
                b:SetScript("OnClick", function()
                    if ReplayFrame.ShowEditPanel then ReplayFrame:ShowEditPanel() end
                    self:ShowOverlay()
                end)
                self._buttonInjected = true
                logDebug("Injected Chatty NPC button into Edit Mode UI")
            end
            t:Cancel()
        elseif elapsed >= 5 then
            t:Cancel()
        end
    end)

    self._init = true
    logInfo("Edit Mode integration initialized")

    -- Hook EnterEditMode to force-show frame + overlay
    if EditModeManagerFrame and hooksecurefunc and not self._enterHooked then
        hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
            if InCombatLockdown and InCombatLockdown() then return end
            if not ReplayFrame.DisplayFrame and ReplayFrame.GetDisplayFrame then ReplayFrame:GetDisplayFrame() end
            if ReplayFrame.DisplayFrame then ReplayFrame.DisplayFrame:Show() end
            self:ShowOverlay()
            self:HookFrameClickToOpen()
            self:UpdateLayoutBadge()
        end)
        self._enterHooked = true
    end
end

-- External entry from addon startup
function ReplayFrame:InitEditModeIntegration()
    if not hasAPI then return end
    if self.EditModeIntegration then self.EditModeIntegration:Init() end
end

-- When our edit panel Accept is clicked
function ReplayFrame:PersistToActiveLayout()
    if self.EditModeIntegration then
        if InCombatLockdown and InCombatLockdown() then
            self.EditModeIntegration._pendingPersist = true
            if CLN.Logger then CLN.Logger:debug("Persist deferred (combat)", false, CLN.Utils.LogCategories.ui) end
        else
            self.EditModeIntegration:PersistCurrentToLayout()
        end
    end
end

-- Auto-start overlay if Edit Mode already open when addon loads
C_Timer.After(2, function()
    if hasAPI and EditModeManagerFrame and EditModeManagerFrame:IsShown() and ReplayFrame.EditModeIntegration then
        ReplayFrame.EditModeIntegration:ShowOverlay()
    end
end)

-- ============================================================================
-- Export / Import Bundle (Blizzard layout string + Chatty Edit Mode settings)
-- Only includes frameScale, queueTextScale, frameSize, npcModelFrameHeight, position.
-- Format: <BlizzardLayoutString>#CLN1#<Base64(metaString)>
-- metaString: key=value; pairs; numeric values; safe ASCII.
-- ============================================================================

local function buildMetaString()
    local p = CLN.db.profile
    local pos = p.framePos or {}
    local size = p.frameSize or { width = 475, height = 165 }
    local keys = {
        fs = tonumber(p.frameScale) or 1,
        ts = tonumber(p.queueTextScale) or 1,
        w = tonumber(size.width) or 475,
        h = tonumber(size.height) or 165,
        mh = tonumber(p.npcModelFrameHeight) or 140,
        pt = pos.point or "CENTER",
        rp = pos.relativePoint or "CENTER",
        px = tonumber(pos.xOfs) or 0,
        py = tonumber(pos.yOfs) or 0,
    }
    local order = { "fs","ts","w","h","mh","pt","rp","px","py" }
    local parts = {}
    for _, k in ipairs(order) do table.insert(parts, k .. "=" .. tostring(keys[k])) end
    return table.concat(parts, ";") .. ";"
end

local function parseMetaString(str)
    local out = {}
    for pair in string.gmatch(str or "", "([%w]+=[^;]*);") do
        local k, v = pair:match("^(%w+)=([^;]*)$")
        if k then out[k] = v end
    end
    return out
end

function ReplayFrame:ExportEditModeBundle()
    if not hasAPI then return nil, "Edit Mode API unavailable" end
    local layouts = C_EditMode.GetLayouts()
    if not layouts or not layouts.layouts then return nil, "No layouts" end
    local activeName = self.EditModeIntegration and self.EditModeIntegration:GetActiveLayoutName() or nil
    local li
    if activeName then
        for _, l in ipairs(layouts.layouts) do
            if l.layoutName == activeName then li = l break end
        end
    end
    if not li then
        local idx = layouts.activeLayout
        li = idx and layouts.layouts[idx]
    end
    if not li then return nil, "Active layout not found" end
    local base = C_EditMode.ConvertLayoutInfoToString(li)
    if not base then return nil, "Conversion failed" end
    local meta = buildMetaString()
    local encoded = CLN.Base64:Encode(meta)
    local bundle = base .. BUNDLE_MARK .. encoded
    logInfo("Exported Chatty Edit Mode bundle (len="..#bundle..")")
    return bundle
end

-- Applies Chatty settings portion only; optionally saves imported layout as new
-- opts: { saveLayout=true, layoutNameOverride="Name" }
function ReplayFrame:ImportEditModeBundle(bundle, opts)
    if type(bundle) ~= "string" or bundle == "" then return false, "Empty" end
    if not hasAPI then return false, "Edit Mode API unavailable" end
    opts = opts or {}
    local base, encoded = bundle:match("^(.-)"..BUNDLE_MARK.."([A-Za-z0-9%+/=]+)$")
    local metaTbl = nil
    if encoded then
        local ok, decoded = pcall(function() return CLN.Base64:Decode(encoded) end)
        if ok and decoded then metaTbl = parseMetaString(decoded) else return false, "Meta decode failed" end
    else
        base = bundle -- treat entire string as base layout; no Chatty meta
    end
    local okLayout, layoutInfo = pcall(C_EditMode.ConvertStringToLayoutInfo, base)
    if not okLayout or not layoutInfo then return false, "Layout parse failed" end
    -- Optionally save layout (add to layouts list)
    if opts.saveLayout then
        local all = C_EditMode.GetLayouts()
        if all and all.layouts then
            layoutInfo.layoutName = opts.layoutNameOverride or (layoutInfo.layoutName .. " (CLN)")
            -- Validate name
            if C_EditMode.IsValidLayoutName and not C_EditMode.IsValidLayoutName(layoutInfo.layoutName) then
                layoutInfo.layoutName = layoutInfo.layoutName:sub(1, 20)
            end
            table.insert(all.layouts, layoutInfo)
            C_EditMode.SaveLayouts(all)
            -- Set active to the new one
            C_EditMode.SetActiveLayout(#all.layouts)
        end
    end
    -- Apply Chatty meta settings
    if metaTbl then
        local p = CLN.db.profile
        local function num(k) local v = tonumber(metaTbl[k]); return v end
        if num("fs") then p.frameScale = math.max(0.5, math.min(2.0, num("fs"))) end
        if num("ts") then p.queueTextScale = math.max(0.75, math.min(1.5, num("ts"))) end
        if num("w") and num("h") then p.frameSize = { width = math.max(200, math.min(1000, num("w"))), height = math.max(100, math.min(600, num("h"))) } end
        if num("mh") then p.npcModelFrameHeight = math.max(50, math.min(300, num("mh"))) end
        p.framePos = {
            point = metaTbl.pt or "CENTER",
            relativePoint = metaTbl.rp or "CENTER",
            xOfs = num("px") or 0,
            yOfs = num("py") or 0,
        }
        -- Re-apply visuals
        if self.ApplyFrameScale then self:ApplyFrameScale() end
        if self.ApplyQueueTextScale then self:ApplyQueueTextScale() end
        if self.DisplayFrame and p.frameSize then self.DisplayFrame:SetSize(p.frameSize.width, p.frameSize.height) end
        if self.NpcModelFrame then self.NpcModelFrame:SetHeight(p.npcModelFrameHeight or 140) end
        if self.Relayout then self:Relayout() end
        -- Persist to active layout bucket
        if self.PersistToActiveLayout then self:PersistToActiveLayout() end
        logInfo("Imported Chatty settings from bundle")
    else
        logDebug("No Chatty settings segment found in bundle; applied layout only")
    end
    return true
end

-- Simple slash helpers (optional power users)
SLASH_CLNEXPORTLAYOUT1 = "/clnexp"
SlashCmdList["CLNEXPORTLAYOUT"] = function()
    local s, err = ReplayFrame:ExportEditModeBundle()
    if not s then
        if CLN.Logger then CLN.Logger:error("Export failed: "..tostring(err), false, CLN.Utils.LogCategories.ui) end
        return
    end
    if CLN.Logger then CLN.Logger:info("Export string (copy from chat):", true, CLN.Utils.LogCategories.ui) end
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd200Chatty Layout Bundle:|r "..s)
end

SLASH_CLNIMPORTLAYOUT1 = "/clnimp"
SlashCmdList["CLNIMPORTLAYOUT"] = function(msg)
    local str = msg and msg:match("^%s*(.-)%s*$")
    if not str or str == "" then
        DEFAULT_CHAT_FRAME:AddMessage("Usage: /clnimp <bundleString>")
        return
    end
    local ok, err = ReplayFrame:ImportEditModeBundle(str, { saveLayout = true })
    if not ok then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020Import failed:|r "..tostring(err))
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cff20ff20Chatty bundle imported.|r")
    end
end

-- Layout debug slash command: prints indices and active detection info
SLASH_CLNLAYOUTDEBUG1 = "/clnlayoutdebug"
SlashCmdList["CLNLAYOUTDEBUG"] = function()
    if not hasAPI then return end
    local layouts = C_EditMode.GetLayouts()
    if not layouts or not layouts.layouts then
        if CLN.Logger then CLN.Logger:warn("No layouts available", false, CLN.Utils.LogCategories.ui) end
        return
    end
    local activeName = ReplayFrame.EditModeIntegration:GetActiveLayoutName()
    if CLN.Logger then
        CLN.Logger:info("Layout Debug (active="..tostring(activeName)..")", false, CLN.Utils.LogCategories.ui)
    end
    for i,l in ipairs(layouts.layouts) do
        local flags = (l.isActive and " isActive" or "")..(l.active and " active" or "")..(l.isLayoutActive and " isLayoutActive" or "")
        local bucket = CLN.db.profile.editModeLayouts and CLN.db.profile.editModeLayouts[l.layoutName] and "*" or "-"
        local displayedIndex = i + HIDDEN_BASE_LAYOUTS -- reflect real underlying index used by API
        if CLN.Logger then
            CLN.Logger:debug(string.format("[%d|raw=%d] %s%s bucket=%s", displayedIndex, i, l.layoutName or "?", flags, bucket), false, CLN.Utils.LogCategories.ui)
        end
    end
end

-- Click-to-open logic (short click detection) added here
function Integration:HookFrameClickToOpen()
    if not ReplayFrame.DisplayFrame then return end
    if self._clickHooked then return end
    local f = ReplayFrame.DisplayFrame
    f:HookScript("OnMouseDown", function(frame, btn)
        if btn ~= "LeftButton" then return end
        self._clickStartTime = GetTime and GetTime() or 0
        local x,y = GetCursorPosition(); self._clickStartX, self._clickStartY = x,y
    end)
    f:HookScript("OnMouseUp", function(frame, btn)
        if btn ~= "LeftButton" then return end
        local x,y = GetCursorPosition();
        local dx = (x or 0) - (self._clickStartX or 0)
        local dy = (y or 0) - (self._clickStartY or 0)
        local dist2 = dx*dx + dy*dy
        local elapsed = (GetTime and GetTime() or 0) - (self._clickStartTime or 0)
        if dist2 < 25*25 and elapsed < 0.75 then
            if ReplayFrame.ShowEditPanel then ReplayFrame:ShowEditPanel() end
        end
    end)
    self._clickHooked = true
end

-- Simple Import/Export dialog + layout manager UI
function Integration:EnsureBundleDialog()
    if self.bundleDialog then return self.bundleDialog end
    local f = CreateFrame("Frame", "ChattyNpcBundleDialog", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(500, 400)
    f:SetPoint("CENTER")
    f:Hide()
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.title:SetPoint("TOP", 0, -12)
    f.title:SetText("Import / Export")
    local eb = CreateFrame("EditBox", nil, f, "InputBoxMultiLine")
    eb:SetPoint("TOPLEFT", 16, -40)
    eb:SetPoint("BOTTOMRIGHT", -16, 60)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
    eb:SetMultiLine(true)
    eb:SetText("")
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    local scrollbg = f:CreateTexture(nil, "BACKGROUND")
    scrollbg:SetAllPoints(eb)
    scrollbg:SetColorTexture(0,0,0,0.25)
    f.editBox = eb
    local exportBtn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    exportBtn:SetSize(100,24)
    exportBtn:SetPoint("BOTTOMLEFT", 16, 24)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        local s, err = ReplayFrame:ExportEditModeBundle()
    if s then eb:SetText(s); if eb.HighlightText then eb:HighlightText() end; if eb.SetFocus then eb:SetFocus() end else
            if CLN.Logger then CLN.Logger:error("Export failed: "..tostring(err), true, CLN.Utils.LogCategories.ui) end
        end
    end)
    local importBtn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    importBtn:SetSize(100,24)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        local txt = eb:GetText() or ""
        local ok, err = ReplayFrame:ImportEditModeBundle(txt, { saveLayout = true })
        if ok then
            if CLN.Logger then CLN.Logger:info("Bundle imported", true, CLN.Utils.LogCategories.ui) end
        else
            if CLN.Logger then CLN.Logger:error("Import failed: "..tostring(err), true, CLN.Utils.LogCategories.ui) end
        end
    end)
    local closeBtn = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    closeBtn:SetSize(100,24)
    closeBtn:SetPoint("BOTTOMRIGHT", -16, 24)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    self.bundleDialog = f
    return f
end

function Integration:ShowBundleDialog()
    local f = self:EnsureBundleDialog(); f:Show(); f:Raise()
end

function Integration:EnsureLayoutManager()
    if self.layoutManager then return self.layoutManager end
    local f = CreateFrame("Frame", "ChattyNpcLayoutManager", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(300, 380)
    f:SetPoint("CENTER", 80, 40)
    f:Hide()
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.title:SetPoint("TOP", 0, -12)
    f.title:SetText("Layouts")
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -40)
    scroll:SetPoint("BOTTOMRIGHT", -30, 50)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1,1)
    scroll:SetScrollChild(content)
    f.content = content
    local function rebuild()
        for _, child in ipairs({content:GetChildren()}) do child:Hide(); child:SetParent(nil) end
        local store = CLN.db.profile.editModeLayouts or {}
        local y = -4
        local activeName = self:GetActiveLayoutName()
        local names = {}
        for layoutName, _ in pairs(store) do table.insert(names, layoutName) end
        table.sort(names, function(a,b) return a:lower() < b:lower() end)
        for i, layoutName in ipairs(names) do
            local row = CreateFrame("Frame", nil, content)
            row:SetPoint("TOPLEFT", 0, y)
            row:SetSize(240, 24)
            y = y - 26
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("LEFT")
            local idxShown = i + HIDDEN_BASE_LAYOUTS
            fs:SetText(string.format("[%d] %s%s", idxShown, (layoutName==activeName and "|cff00ff00*|r " or ""), layoutName))
            local del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            del:SetSize(40,20); del:SetPoint("RIGHT")
            del:SetText("Del")
            del:SetScript("OnClick", function()
                CLN.db.profile.editModeLayouts[layoutName] = nil
                if CLN.Logger then CLN.Logger:warn("Deleted layout bucket '"..layoutName.."'", false, CLN.Utils.LogCategories.ui) end
                rebuild()
            end)
            local apply = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            apply:SetSize(50,20); apply:SetPoint("RIGHT", del, "LEFT", -4, 0)
            apply:SetText("Apply")
            apply:SetScript("OnClick", function() Integration:ApplyLayout(layoutName) end)
        end
        content:SetHeight(-y + 4)
    end
    f.rebuild = rebuild
    -- Per-setting opt-out toggles
    local exclude = ensureExcludeConfig()
    local toggleNames = {
        { key="frameScale", label="Frame Scale" },
        { key="queueTextScale", label="Text Scale" },
        { key="frameSize", label="Size" },
        { key="npcModelFrameHeight", label="Model Height" },
        { key="framePos", label="Position" },
    }
    local bx = 12; local by = - (scroll:GetBottom() and 0 or 0)
    local col = 0; local startY = -300
    local rowY = - (content:GetHeight() or 0)
    local ckY = -340
    local prev
    local anchorFrame = f
    local yBase = - (f:GetHeight() - 110)
    local x = 14; local yoff = - (f:GetHeight() - 120)
    for i, info in ipairs(toggleNames) do
        local cb = CreateFrame("CheckButton", nil, f, "InterfaceOptionsCheckButtonTemplate")
        cb:SetPoint("BOTTOMLEFT", x + ((i-1)%2)*140, 60 + math.floor((i-1)/2)*24)
        cb.Text:SetText(info.label)
        cb:SetChecked(exclude[info.key])
        cb:SetScript("OnClick", function(btn)
            exclude[info.key] = btn:GetChecked() and true or false
            if CLN.Logger then CLN.Logger:debug("Exclude toggle '.."..info.key.."'="..tostring(exclude[info.key]), false, CLN.Utils.LogCategories.ui) end
            local name = Integration:GetActiveLayoutName(); if name then Integration:ApplyLayout(name) end
        end)
        cb.tooltipText = "Exclude "..info.label.." from per-layout overrides" -- basic tooltip
    end
    local close = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    close:SetSize(80,24); close:SetPoint("BOTTOMRIGHT", -14, 16); close:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)
    local reset = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    reset:SetSize(120,24); reset:SetPoint("LEFT", close, "LEFT", -130, 0); reset:SetText("Reset All")
    reset:SetScript("OnClick", function()
        CLN.db.profile.editModeLayouts = {}
        if CLN.Logger then CLN.Logger:warn("Cleared all per-layout settings", true, CLN.Utils.LogCategories.ui) end
        rebuild()
    end)
    f:SetScript("OnShow", rebuild)
    self.layoutManager = f
    return f
end

function Integration:ShowLayoutManager()
    local f = self:EnsureLayoutManager(); f:Show(); f:Raise()
end

-- Layout badge updater
function Integration:UpdateLayoutBadge()
    if not self.overlay or not self.overlay._badge or not self.overlay._badgeHolder then return end
    local n = self:GetActiveLayoutName()
    if not n or n == "?" then
        self.overlay._badgeHolder:Hide()
        return
    end
    self.overlay._badge:SetText(n)
    -- Resize holder to fit text snugly
    local textWidth = self.overlay._badge:GetStringWidth() + 12
    self.overlay._badgeHolder:SetWidth(math.max(40, textWidth))
    self.overlay._badgeHolder:Show()
end

