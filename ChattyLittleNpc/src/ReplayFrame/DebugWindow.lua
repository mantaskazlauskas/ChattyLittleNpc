---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- DebugWindow: an in-game tool to inspect and tweak the current ReplayFrame model.
-- Features:
-- - Opens with /clnmodel or /clndebug
-- - Embeds a ModelHost using the same backend preference (ModelScene preferred)
-- - Manual controls: yaw, zoom, Z pan, face camera, flip, axis dir
-- - Show important runtime parameters (bounds, camera snapshot, zoom, etc.)
-- - Capture logs for only the active model session; copy to clipboard
-- - Trigger common animations (Idle, Talk, Wave, Nod, Yes/No, One-shot emotes)

ReplayFrame.DebugWindow = ReplayFrame.DebugWindow or {}
local DW = ReplayFrame.DebugWindow

-- Global-scope helpers for DebugWindow
function DW:_ActiveHost()
    return (self._useMirror and self.mirrorHost)
        or (self._controlMain and ReplayFrame and ReplayFrame.NpcModelFrame)
        or self.embedHost
end

function DW:_GetReplayDisplayID()
    local rf = ReplayFrame
    if not rf then return nil end
    if rf._lastDisplayID then return rf._lastDisplayID end
    if rf._GetCurrentDisplayID then
        local ok, id = pcall(rf._GetCurrentDisplayID, rf)
        if ok and id then return id end
    end
    if rf.NpcModelFrame then
        if rf.NpcModelFrame._currentDisplayID then return rf.NpcModelFrame._currentDisplayID end
        if rf.NpcModelFrame._displayID then return rf.NpcModelFrame._displayID end
    end
    return nil
end

function DW:PreviewTarget()
    local h = self:_ActiveHost(); if not h then return end
    -- Prefer expanded preview when actively previewing a target
    if DW._previewExpanded == nil then DW._previewExpanded = true end
    if DW._UpdatePreviewSize then DW._UpdatePreviewSize() end
    local hasTarget = UnitExists and UnitExists("target")
    local isPlayer = hasTarget and UnitIsPlayer and UnitIsPlayer("target") or false
    local applied = false
    
    -- Debug logging for model loading issues
    if CLN and CLN.Logger then CLN.Logger:debug("[DW] PreviewTarget hasTarget=" .. tostring(hasTarget) .. " isPlayer=" .. tostring(isPlayer), false, CLN.Utils.LogCategories.ui) end
    
    -- Players: SetUnit is appropriate
    if isPlayer and h.SetUnit then
    if CLN and CLN.Logger then CLN.Logger:debug("[DW] Attempting SetUnit for player", false, CLN.Utils.LogCategories.ui) end
        applied = pcall(h.SetUnit, h, "target") and true or false
    if CLN and CLN.Logger then CLN.Logger:debug("[DW] SetUnit applied=" .. tostring(applied), false, CLN.Utils.LogCategories.ui) end
    end
    -- NPCs: prefer displayID path to avoid composite/texture issues in ModelScene
    if (not isPlayer) and hasTarget and UnitCreatureDisplayID and h.SetDisplayInfo then
        local ok, id = pcall(UnitCreatureDisplayID, "target")
    if CLN and CLN.Logger then CLN.Logger:debug("[DW] UnitCreatureDisplayID ok=" .. tostring(ok) .. " id=" .. tostring(id), false, CLN.Utils.LogCategories.ui) end
        if ok and type(id) == "number" then
            if h.ClearModel then pcall(h.ClearModel, h) end
            if CLN and CLN.Logger then CLN.Logger:debug("[DW] Calling SetDisplayInfo id=" .. tostring(id), false, CLN.Utils.LogCategories.ui) end
            local setOk = pcall(h.SetDisplayInfo, h, id)
            if CLN and CLN.Logger then CLN.Logger:debug("[DW] SetDisplayInfo success=" .. tostring(setOk), false, CLN.Utils.LogCategories.ui) end
            applied = true
        end
    end
    -- Last resort: try SetUnit even for NPCs if displayID failed
    if (not applied) and hasTarget and h.SetUnit then
    if CLN and CLN.Logger then CLN.Logger:debug("[DW] Fallback to SetUnit for NPC", false, CLN.Utils.LogCategories.ui) end
        applied = pcall(h.SetUnit, h, "target") and true or false
    if CLN and CLN.Logger then CLN.Logger:debug("[DW] Fallback SetUnit applied=" .. tostring(applied), false, CLN.Utils.LogCategories.ui) end
    end
    if DW._autoRefit ~= false then
        local function refit()
            if h.FrameFullBodyFront then h:FrameFullBodyFront(0.12) end
            if h.FaceCamera then h:FaceCamera() end
        end
        if C_Timer and C_Timer.After then C_Timer.After(0.10, refit) else refit() end
    end
    -- Ensure a post-load refit when model finishes loading
    if h.OnModelLoadedOnce then
        h:OnModelLoadedOnce(function(host)
            if DW._autoRefit ~= false then
                if host and host.FrameFullBodyFront then host:FrameFullBodyFront(0.12) end
                if host and host.FaceCamera then host:FaceCamera() end
            end
        -- Resync the controls once content is loaded
        if DW._SyncControlsToHost then DW:_SyncControlsToHost(host) end
        end)
    end
    -- Initial sync (pre-load) to seed sliders to current snapshot
    if DW._SyncControlsToHost then DW:_SyncControlsToHost(h) end
end

local function safeCall(obj, method, ...)
    if not (obj and method and obj[method]) then return nil end
    local ok, res = pcall(obj[method], obj, ...)
    if ok then return res end
    return nil
end

local function now()
    return (type(GetTime) == "function") and GetTime() or (C_Timer and C_Timer.GetTime and C_Timer.GetTime()) or 0
end

-- Lightweight per-window logger with category filter passthru
local function shouldLog(category)
    local U = CLN and CLN.Utils
    return U and U.ShouldLogAnimDebug and U:ShouldLogAnimDebug(category)
end

local function fmtNum(x)
    if type(x) ~= "number" then return tostring(x) end
    return string.format("%.3f", x)
end

local function clamp(v, lo, hi)
    if v == nil then return nil end
    if lo ~= nil and v < lo then return lo end
    if hi ~= nil and v > hi then return hi end
    return v
end

-- Create frame once
function DW:Create()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "CLN_DebugModelWindow", UIParent, "BackdropTemplate")
    f:SetClampedToScreen(true)
    -- Load persisted placement and settings
    local prof = CLN and CLN.db and CLN.db.profile or nil
    local cfg = prof and (prof.debugWindow or {}) or {}
    local ww, hh = tonumber(cfg.width) or 960, tonumber(cfg.height) or 480
    f:SetSize(ww, hh)
    if cfg.point and cfg.relPoint and cfg.x and cfg.y then
        pcall(f.ClearAllPoints, f)
        pcall(f.SetPoint, f, cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
    else
        f:SetPoint("CENTER")
    end
    -- Movable unless locked in settings
    local locked = (cfg.lockWindow == true)
    f:SetMovable(not locked)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        -- Persist position and size
        local p, rel, rp, x, y = f:GetPoint(1)
        if CLN and CLN.db and CLN.db.profile then
            CLN.db.profile.debugWindow = CLN.db.profile.debugWindow or {}
            local dw = CLN.db.profile.debugWindow
            dw.point, dw.relPoint, dw.x, dw.y = p, rp, x, y
            local w2, h2 = f:GetSize()
            dw.width, dw.height = w2, h2
        end
    end)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:Hide()

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
    title:SetText("Chatty Little NPC — Model Debugger")
    -- Allow dragging by the title area
    local dragBar = CreateFrame("Frame", nil, f)
    dragBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    dragBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    dragBar:SetHeight(28)
    dragBar:EnableMouse(true)
    dragBar:RegisterForDrag("LeftButton")
    dragBar:SetScript("OnDragStart", function() if not DW._lockWindow then f:StartMoving() end end)
    dragBar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        -- Persist position/size after title-drag
        local p, rel, rp, x, y = f:GetPoint(1)
        if CLN and CLN.db and CLN.db.profile then
            CLN.db.profile.debugWindow = CLN.db.profile.debugWindow or {}
            local dw = CLN.db.profile.debugWindow
            dw.point, dw.relPoint, dw.x, dw.y = p, rp, x, y
            local w2, h2 = f:GetSize()
            dw.width, dw.height = w2, h2
        end
    end)

    -- Close button
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT")
    -- Ensure debug render window (mirror) also closes
    close:SetScript("OnClick", function()
        DW:Hide()
    end)

    -- Columns: left (controls), middle (outputs), right (preview)
    local leftCol = CreateFrame("Frame", nil, f)
    leftCol:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
    leftCol:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
    leftCol:SetWidth(260)
    leftCol:SetFrameLevel(f:GetFrameLevel() + 1)

    -- Rightmost preview column
    local previewCol = CreateFrame("Frame", nil, f)
    previewCol:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -30)
    previewCol:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    previewCol:SetWidth(320)
    previewCol:SetFrameLevel(f:GetFrameLevel() + 1)

    -- Middle column for info/logs
    local rightCol = CreateFrame("Frame", nil, f)
    rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", 10, 0)
    rightCol:SetPoint("BOTTOMLEFT", leftCol, "BOTTOMRIGHT", 10, 0)
    rightCol:SetPoint("TOPRIGHT", previewCol, "TOPLEFT", -10, 0)
    rightCol:SetPoint("BOTTOMRIGHT", previewCol, "BOTTOMLEFT", -10, 0)
    rightCol:SetFrameLevel(f:GetFrameLevel() + 1)

    -- Preview container dedicated to the preview column; the mirror will be parented here
    local preview = CreateFrame("Frame", nil, previewCol, "BackdropTemplate")
    preview:SetPoint("TOPLEFT", previewCol, "TOPLEFT", 0, 0)
    preview:SetPoint("TOPRIGHT", previewCol, "TOPRIGHT", 0, 0)
    preview:SetHeight(180)
    preview:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = {left=2,right=2,top=2,bottom=2} })
    preview:SetBackdropColor(0, 0, 0, 0.8)
    DW._previewContainer = preview
    -- Use expanded view by default unless explicitly turned off earlier; load persisted pref
    if DW._previewExpanded == nil then
        if cfg and cfg.expanded ~= nil then DW._previewExpanded = cfg.expanded and true or false else DW._previewExpanded = true end
    end
    -- Small help overlay in preview
    local helpFS = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helpFS:SetPoint("TOPLEFT", preview, "TOPLEFT", 6, -6)
    helpFS:SetText("L-drag: Pan, R-drag: Orbit, Wheel: Zoom")
    helpFS:SetAlpha(0.75)
    DW._previewHelp = helpFS

    -- Anchor for the middle column content (no longer under preview)
    local contentAnchor = CreateFrame("Frame", nil, rightCol)
    contentAnchor:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
    contentAnchor:SetPoint("RIGHT", rightCol, "RIGHT", 0, 0)

    -- Model area (was at top of left column). We hide it so controls can take full height.
    local modelArea = CreateFrame("Frame", nil, leftCol)
    modelArea:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, 0)
    modelArea:SetPoint("TOPRIGHT", leftCol, "TOPRIGHT", 0, 0)
    modelArea:SetHeight(0)

    -- Embedded host for convenience; the primary target can be a separate "mirror" frame
    local embedHost = ReplayFrame.CreateModelHost and ReplayFrame:CreateModelHost(modelArea) or CreateFrame("Frame", nil, modelArea)
    embedHost:ClearAllPoints()
    embedHost:SetAllPoints(modelArea)
    embedHost:Hide()

    -- Mirror frame: a top-level model host matching ReplayFrame's model size/position
    DW._useMirror = true
    DW._mirrorFollowPos = true
    DW._mirrorLockSize = true
    local function ensureMirror()
        if DW.mirrorFrame and DW.mirrorHost then
            -- Ensure correct parenting
            if DW._previewContainer and DW.mirrorFrame:GetParent() ~= DW._previewContainer then
                DW.mirrorFrame:SetParent(DW._previewContainer)
                DW.mirrorFrame:ClearAllPoints()
                DW.mirrorFrame:SetAllPoints(DW._previewContainer)
                DW.mirrorFrame:Show()
            end
            return DW.mirrorFrame, DW.mirrorHost
        end
        local parent = DW._previewContainer or UIParent
    local mf = CreateFrame("Frame", "CLN_DebugModelMirror", parent, "BackdropTemplate")
        mf:SetSize(300, 180)
        if parent == UIParent then
            mf:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
        else
            mf:ClearAllPoints(); mf:SetAllPoints(parent)
        end
        mf:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12, insets = {left=2,right=2,top=2,bottom=2} })
        mf:SetBackdropColor(0, 0, 0, 0.8)
        mf:EnableMouse(true)
    -- Don't trap keyboard while this overlay is shown
    if mf.SetPropagateKeyboardInput then mf:SetPropagateKeyboardInput(true) end
    if mf.EnableKeyboard then mf:EnableKeyboard(false) end
        mf:EnableMouseWheel(true)
    -- Always keep the mirror static to allow Left-button drag for panning
    mf:SetMovable(false)
        mf:Show()
    -- Ensure mirror frame draws above preview backdrop
    mf:SetFrameLevel((parent:GetFrameLevel() or 1) + 2)
    local mh = ReplayFrame.CreateModelHost and ReplayFrame:CreateModelHost(mf) or CreateFrame("Frame", nil, mf)
        mh:ClearAllPoints(); mh:SetAllPoints(mf); mh:Show()
    mh:SetFrameLevel(mf:GetFrameLevel() + 1)
        DW.mirrorFrame, DW.mirrorHost = mf, mh

    -- Enable direct interaction with the model in the mirror:
    --   - LeftButton drag: Pan
    --   - RightButton drag: Orbit yaw (hold Shift for Pan)
    --   - Mouse wheel: Zoom
        local mdrag = { active = false }
        local function m_clamp(v, lo, hi)
            if v == nil then return nil end
            if lo ~= nil and v < lo then return lo end
            if hi ~= nil and v > hi then return hi end
            return v
        end
        local function m_clampZoomForHost(h, z)
            if not h then return m_clamp(z, -2.25, 2.0) end
            local kind = h._backend and h._backend.kind or "scene"
            if kind == "player" then
                return m_clamp(z, 0.0, 1.0)
            else
                return m_clamp(z, -2.25, 2.0)
            end
        end
        mf:SetScript("OnMouseWheel", function(_, delta)
            local tgt = DW.mirrorHost
            if tgt and tgt.GetPortraitZoom and tgt.SetPortraitZoom then
                local cur = tgt:GetPortraitZoom() or 0.65
                local raw = cur + (delta > 0 and 0.03 or -0.03)
                local z = m_clampZoomForHost(tgt, raw)
                tgt._userControlledCamera = true
                tgt:SetPortraitZoom(z)
                if DW._sliders and DW._sliders.zoom and DW._sliders.zoom.SetValue then DW._sliders.zoom:SetValue(z) end
            end
        end)
        mf:SetScript("OnMouseDown", function(_, btn)
            local tgt = DW.mirrorHost
            mdrag.active = true
            mdrag.button = btn
            mdrag.startX, mdrag.startY = GetCursorPosition()
            mdrag.startYaw = (tgt and tgt.GetActorYaw and tgt:GetActorYaw()) or 0
            local s = (tgt and tgt._lastCamSnapshot) or {}
            mdrag.startTX, mdrag.startTY, mdrag.startTZ = s.tx or 0, s.ty or 0, s.tz or 0
            mdrag.startFrameW, mdrag.startFrameH = mf:GetSize()
            -- Decide interaction mode
            if btn == "LeftButton" then
                mdrag.mode = "pan"
            elseif btn == "RightButton" then
                mdrag.mode = (IsShiftKeyDown() and "pan") or "orbit"
            else
                mdrag.mode = nil
            end
        end)
        mf:SetScript("OnMouseUp", function(_, btn)
            if btn == mdrag.button then mdrag.active = false end
        end)
        mf:SetScript("OnHide", function() mdrag.active = false end)
        mf:SetScript("OnUpdate", function()
            if not mdrag.active then return end
            local tgt = DW.mirrorHost
            if not tgt then return end
            local curX, curY = GetCursorPosition()
            local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
            local dx, dy = (curX - (mdrag.startX or curX)) / scale, (curY - (mdrag.startY or curY)) / scale
            local w, h = mdrag.startFrameW or 1, mdrag.startFrameH or 1
            local s = (tgt and tgt._lastCamSnapshot) or {}
            local d = s.dist or (tgt and tgt._camDist) or 2.5
            local vfov = s.vfov or (tgt and tgt.GetFovV and tgt:GetFovV()) or 0.8
            local asp = s.aspect or (tgt and tgt.GetAspect and tgt:GetAspect()) or (w/h)
            local hfov = s.hfov or (2 * math.atan(math.tan(vfov * 0.5) * math.max(asp, 1e-3)))
            if mdrag.mode == "orbit" then
                -- Orbit: adjust yaw with horizontal pixels (Right drag)
                local yaw = (mdrag.startYaw or 0) + (dx * 0.01)
                if tgt and tgt.SetActorYaw then 
                    tgt._userControlledCamera = true
                    tgt:SetActorYaw(yaw) 
                end
                if DW._sliders and DW._sliders.yaw and DW._sliders.yaw.SetValue then DW._sliders.yaw:SetValue(yaw) end
            elseif mdrag.mode == "pan" then
                -- Pan: map pixels to world units using current FOV and distance (Left drag or Shift+Right)
                local worldPerPxX = (2 * d * math.tan(hfov * 0.5)) / math.max(1, w)
                local worldPerPxY = (2 * d * math.tan(vfov * 0.5)) / math.max(1, h)
                local axis = tostring((tgt and tgt._camAxis) or s.axis or "Y+")
                local tx, ty, tz = mdrag.startTX, mdrag.startTY, mdrag.startTZ
                if axis:match("^Y") then
                    tx = (mdrag.startTX or 0) + dx * worldPerPxX
                else
                    ty = (mdrag.startTY or 0) + dx * worldPerPxX
                end
                tz = (mdrag.startTZ or 0) + (-dy) * worldPerPxY
                if tgt and tgt.SetTarget then 
                    tgt._userControlledCamera = true
                    tgt:SetTarget({ x = tx, y = ty, z = tz }) 
                end
                if DW._sliders then
                    if DW._sliders.x and DW._sliders.x.SetValue then DW._sliders.x:SetValue(tx) end
                    if DW._sliders.y and DW._sliders.y.SetValue then DW._sliders.y:SetValue(-ty) end
                    if DW._sliders.z and DW._sliders.z.SetValue then DW._sliders.z:SetValue(tz) end
                end
            end
        end)
        return mf, mh
    end
    -- Expose as method so callers outside this scope can use it
    function DW:EnsureMirror()
        return ensureMirror()
    end
    local function activeHost()
        local tgt = (DW._useMirror and DW.mirrorHost) or (DW._controlMain and ReplayFrame and ReplayFrame.NpcModelFrame) or embedHost
        return tgt or embedHost
    end
    -- Update preview size according to mode: match ReplayFrame or Expanded
    local function updatePreviewSize()
        if not preview then return end
        local rf = ReplayFrame
        local src = rf and (rf.ModelContainer or rf.NpcModelFrame) or nil
        local colW = previewCol:GetWidth() or preview:GetWidth() or 300
        local colH = previewCol:GetHeight() or 300
        if DW._previewExpanded then
            -- Expanded: fill the preview column height
            preview:ClearAllPoints()
            preview:SetPoint("TOPLEFT", previewCol, "TOPLEFT", 0, 0)
            preview:SetPoint("TOPRIGHT", previewCol, "TOPRIGHT", 0, 0)
            preview:SetHeight(colH)
        else
            -- Standard: match ReplayFrame model container width/height exactly (flat/letterbox look)
            local srcW = src and src.GetWidth and src:GetWidth() or nil
            local srcH = src and src.GetHeight and src:GetHeight() or nil
            local w = (srcW and math.floor(srcW)) or math.floor(colW)
            local h = (srcH and math.floor(srcH)) or 160
            preview:ClearAllPoints()
            preview:SetPoint("TOPLEFT", previewCol, "TOPLEFT", 0, 0)
            preview:SetWidth(w)
            preview:SetHeight(h)
        end
        -- Ensure mirror fills the preview container
        if DW.mirrorFrame and DW.mirrorFrame.GetParent and DW.mirrorFrame:GetParent() == preview then
            DW.mirrorFrame:ClearAllPoints()
            DW.mirrorFrame:SetAllPoints(preview)
        end
    end
    DW._UpdatePreviewSize = function() updatePreviewSize() end
    -- React to size changes on the preview column and preview container
    previewCol:SetScript("OnSizeChanged", function()
        updatePreviewSize()
    end)
    preview:SetScript("OnSizeChanged", function()
        updatePreviewSize()
    end)

    local function syncMirrorFromReplay()
        if not (DW._useMirror and DW.mirrorFrame) then return end
        -- If embedded in the debug UI, size is controlled by the preview, not world position
        if DW._previewContainer then
            updatePreviewSize()
            return
        end
        local rf = ReplayFrame
        local src = rf and rf.ModelContainer or rf and rf.NpcModelFrame or nil
        if not src then return end
        if DW._mirrorLockSize then
            local w = src.GetWidth and src:GetWidth() or 300
            local h = src.GetHeight and src:GetHeight() or 180
            DW.mirrorFrame:SetSize(w, h)
        end
        if DW._mirrorFollowPos and src.GetLeft and src:GetLeft() then
            local l, b = src:GetLeft(), src:GetBottom()
            if l and b then
                local uiL, uiB = UIParent:GetLeft() or 0, UIParent:GetBottom() or 0
                local x = l - uiL
                local y = b - uiB
                DW.mirrorFrame:ClearAllPoints()
                DW.mirrorFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
            end
        end
    end

    -- Target host routing: prefer mirror frame; optionally control main ReplayFrame model
    DW._controlMain = false
    local function getTargetHost()
        if DW._useMirror and DW.mirrorHost then
            return DW.mirrorHost
        end
        if DW._controlMain and ReplayFrame and ReplayFrame.NpcModelFrame then
            return ReplayFrame.NpcModelFrame
        end
        return embedHost
    end

    -- Drag overlay for orbit/pan/zoom
    local overlay = CreateFrame("Frame", nil, modelArea)
    overlay:SetAllPoints(modelArea)
    overlay:EnableMouse(true)
    overlay:EnableMouseWheel(true)
    overlay:SetFrameLevel(modelArea:GetFrameLevel() + 10)
    if overlay.SetPropagateKeyboardInput then overlay:SetPropagateKeyboardInput(true) end
    if overlay.EnableKeyboard then overlay:EnableKeyboard(false) end
    local drag = { active=false }
    overlay:SetScript("OnMouseDown", function(_, btn)
        local tgt = getTargetHost()
        drag.active = true
        drag.button = btn
        drag.startX, drag.startY = GetCursorPosition()
        drag.startYaw = (tgt and tgt.GetActorYaw and tgt:GetActorYaw()) or 0
        local s = (tgt and tgt._lastCamSnapshot) or {}
        drag.startTX, drag.startTY, drag.startTZ = s.tx or 0, s.ty or 0, s.tz or 0
        drag.startSnapshot = s
        drag.startFrameW, drag.startFrameH = modelArea:GetSize()
        drag.startTime = now()
    end)
    overlay:SetScript("OnMouseUp", function()
        drag.active = false
    end)
    overlay:SetScript("OnHide", function() drag.active = false end)
    -- Fixed ranges for controls (will be refined dynamically)
    local yawMin, yawMax = -math.pi, math.pi
    -- 50% more min zoom (farther out)
    -- Extend min zoom by another 50% to allow zooming farther out
    local zoomMin, zoomMax = -2.25, 2.0
    -- Dynamic zoom range based on model size (computed each frame); nil means unused
    local dynZoomMin, dynZoomMax = nil, nil
    -- Wider initial pans; dynamic recalculation will refine
    local xMin, xMax = -3.0, 3.0
    local yMin, yMax = -3.0, 3.0
    local zMin, zMax = -3.0, 4.5

    local function clampZoomForHost(h, z)
        if not h then return clamp(z, zoomMin, zoomMax) end
        local kind = h._backend and h._backend.kind or "scene"
        if kind == "player" then
            local base = clamp(z, 0.0, 1.0)
            if dynZoomMin and dynZoomMax then base = clamp(base, dynZoomMin, dynZoomMax) end
            return base
        else
            local base = clamp(z, zoomMin, zoomMax)
            if dynZoomMin and dynZoomMax then base = clamp(base, dynZoomMin, dynZoomMax) end
            return base
        end
    end

    overlay:SetScript("OnMouseWheel", function(_, delta)
        local tgt = getTargetHost()
        if tgt and tgt.GetPortraitZoom then
            local cur = tgt:GetPortraitZoom() or 0.65
            local raw = cur + (delta > 0 and 0.03 or -0.03)
            local z = clampZoomForHost(tgt, raw)
            tgt._userControlledCamera = true
            tgt:SetPortraitZoom(z)
            if zoomSlider and zoomSlider.SetValue then zoomSlider:SetValue(z) end
        end
    end)
    overlay:SetScript("OnUpdate", function()
        if not drag.active then return end
        local tgt = getTargetHost()
        local curX, curY = GetCursorPosition()
        local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
        local dx, dy = (curX - (drag.startX or curX)) / scale, (curY - (drag.startY or curY)) / scale
        local w, h = drag.startFrameW or 1, drag.startFrameH or 1
        local s = (tgt and tgt._lastCamSnapshot) or {}
        local d = s.dist or (tgt and tgt._camDist) or 2.5
        local vfov = s.vfov or (tgt and tgt.GetFovV and tgt:GetFovV()) or 0.8
        local hfov = s.hfov or (function()
            local asp = (tgt and tgt.GetAspect and tgt:GetAspect()) or (w/h)
            local t = math.tan(vfov * 0.5) * math.max(1e-3, asp)
            return 2 * math.atan(t)
        end)()
        if drag.button == "LeftButton" and (not IsShiftKeyDown()) then
            -- Orbit: adjust yaw with horizontal pixels
            local yaw = clamp((drag.startYaw or 0) + (dx * 0.01), yawMin, yawMax)
            if tgt then tgt._userControlledCamera = true end
            if tgt and tgt.SetActorYaw then tgt:SetActorYaw(yaw) end
            if yawSlider and yawSlider.SetValue then yawSlider:SetValue(yaw) end
    else
            -- Pan: map pixels to world units using current FOV and distance
            local worldPerPxX = (2 * d * math.tan(hfov * 0.5)) / math.max(1, w)
            local worldPerPxY = (2 * d * math.tan(vfov * 0.5)) / math.max(1, h)
            local axis = tostring((tgt and tgt._camAxis) or s.axis or "Y+")
            local tx, ty, tz = drag.startTX, drag.startTY, drag.startTZ
            -- Screen X (dx) moves world X if Y-axis camera, or world Y if X-axis camera
            if axis:match("^Y") then
                tx = (drag.startTX or 0) + dx * worldPerPxX
            else
                ty = (drag.startTY or 0) + dx * worldPerPxX
            end
            -- Screen Y increases upward in GetCursorPosition; map to world Z with sign
            tz = (drag.startTZ or 0) + (-dy) * worldPerPxY
            -- Clamp to dynamic slider bounds (fallback to initial ranges)
            local sxMin, sxMax = xMin, xMax
            local syMin, syMax = yMin, yMax
            local szMin, szMax = zMin, zMax
            if xSlider and xSlider.GetMinMaxValues then sxMin, sxMax = xSlider:GetMinMaxValues() end
            if ySlider and ySlider.GetMinMaxValues then syMin, syMax = ySlider:GetMinMaxValues() end
            if zSlider and zSlider.GetMinMaxValues then szMin, szMax = zSlider:GetMinMaxValues() end
            tx = clamp(tx, sxMin, sxMax)
            ty = clamp(ty, syMin, syMax)
            tz = clamp(tz, szMin, szMax)
            if tgt and tgt.SetTarget then 
                tgt._userControlledCamera = true
                tgt:SetTarget({ x = tx, y = ty, z = tz }) 
            end
            if xSlider and xSlider.SetValue then xSlider:SetValue(tx) end
            if ySlider and ySlider.SetValue then ySlider:SetValue(-ty) end
            if zSlider and zSlider.SetValue then zSlider:SetValue(tz) end
            -- Track last pan delta for UI
            DW._lastDragDelta = { x = (tx - (drag.startTX or 0)), y = (ty - (drag.startTY or 0)), z = (tz - (drag.startTZ or 0)) }
        end
    end)

    -- Left: controls (scrollable) — fill the entire left column height
    local ctrlScroll = CreateFrame("ScrollFrame", nil, leftCol, "UIPanelScrollFrameTemplate")
    ctrlScroll:SetPoint("TOPLEFT", leftCol, "TOPLEFT", 0, 0)
    ctrlScroll:SetPoint("BOTTOMLEFT", leftCol, "BOTTOMLEFT", 0, 0)
    ctrlScroll:SetPoint("BOTTOMRIGHT", leftCol, "BOTTOMRIGHT", -20, 0)
    local ctrlPanel = CreateFrame("Frame", nil, ctrlScroll)
    ctrlPanel:SetPoint("TOPLEFT", ctrlScroll, "TOPLEFT", 0, 0)
    ctrlPanel:SetPoint("TOPRIGHT", ctrlScroll, "TOPRIGHT", -20, 0)
    ctrlPanel:SetHeight(400)
    ctrlScroll:SetScrollChild(ctrlPanel)
    -- Ensure controls render above container backdrop
    ctrlPanel:SetFrameLevel(leftCol:GetFrameLevel() + 2)

    local y = -4
    -- Absolute target state sourced from sliders to avoid drift
    local slX, slY, slZ
    local function applyTargetFromState()
        local h = getTargetHost(); if not (h and h.SetTarget) then return end
        local s = (h._lastCamSnapshot) or { tx = 0, ty = 0, tz = 0 }
        local nx = (slX ~= nil) and slX or (s.tx or 0)
        local ny = (slY ~= nil) and slY or (s.ty or 0)
        local nz = (slZ ~= nil) and slZ or (s.tz or 0)
        -- Mark host as user-controlled to prevent auto-refits
        h._userControlledCamera = true
        h:SetTarget({ x = nx, y = ny, z = nz })
    end
    -- Dynamic pan ranges from bounds and FOV so we can move model barely out of sight
    local function updatePanRanges()
        local h = getTargetHost(); if not h then return end
        local s = h._lastCamSnapshot or {}
        local d = s.dist or h._camDist or 2.5
        local vfov = s.vfov or (h.GetFovV and h:GetFovV()) or 0.8
        local asp = s.aspect or (h.GetAspect and h:GetAspect()) or 1.0
        local hfov = s.hfov or (2 * math.atan(math.tan(vfov * 0.5) * math.max(asp, 1e-3)))
        local halfW = math.tan(hfov * 0.5) * d
        local halfH = math.tan(vfov * 0.5) * d
        local bx1, by1, bz1, bx2, by2, bz2
        if h.GetBounds then
            local ok, a,b,c,d1,e,f = pcall(h.GetBounds, h)
            if ok then
                local function num(v) return type(v) == "number" and v or 0 end
                if type(a) == "table" and (a.min or a.max or a.center) and b == nil then
                    -- Single bounds object with min/max or center/size
                    if a.min and a.max then
                        local mn, mx = a.min, a.max
                        bx1, by1, bz1 = num(mn.x or mn[1]), num(mn.y or mn[2]), num(mn.z or mn[3])
                        bx2, by2, bz2 = num(mx.x or mx[1]), num(mx.y or mx[2]), num(mx.z or mx[3])
                    elseif a.center and a.size then
                        local ctr, sz = a.center, a.size
                        local cx, cy, cz = num(ctr.x or ctr[1]), num(ctr.y or ctr[2]), num(ctr.z or ctr[3])
                        local sx, sy, szv = num(sz.x or sz[1]), num(sz.y or sz[2]), num(sz.z or sz[3])
                        bx1, by1, bz1 = cx - sx*0.5, cy - sy*0.5, cz - szv*0.5
                        bx2, by2, bz2 = cx + sx*0.5, cy + sy*0.5, cz + szv*0.5
                    elseif a.x or a[1] then
                        -- Single point; mirror as symmetric box around origin
                        local ax, ay, az = num(a.x or a[1]), num(a.y or a[2]), num(a.z or a[3])
                        bx1, by1, bz1 = -math.abs(ax), -math.abs(ay), -math.abs(az)
                        bx2, by2, bz2 =  math.abs(ax),  math.abs(ay),  math.abs(az)
                    end
                elseif type(a) == "table" and type(b) == "table" then
                    bx1, by1, bz1 = num(a.x or a[1]), num(a.y or a[2]), num(a.z or a[3])
                    bx2, by2, bz2 = num(b.x or b[1]), num(b.y or b[2]), num(b.z or b[3])
                elseif type(a) == "number" then
                    bx1, by1, bz1, bx2, by2, bz2 = num(a), num(b), num(c), num(d1), num(e), num(f)
                end
            end
        end
        -- Sanitizer: if any bound is still a table, try to reduce it
        local function sanitizeBounds()
            local function num(v) return type(v) == "number" and v or 0 end
            if type(bx1) == "table" then
                local t = bx1
                if t.min and t.max then
                    local mn, mx = t.min, t.max
                    bx1, by1, bz1 = num(mn.x or mn[1]), num(mn.y or mn[2]), num(mn.z or mn[3])
                    bx2, by2, bz2 = num(mx.x or mx[1]), num(mx.y or mx[2]), num(mx.z or mx[3])
                elseif t.center and t.size then
                    local ctr, sz = t.center, t.size
                    local cx, cy, cz = num(ctr.x or ctr[1]), num(ctr.y or ctr[2]), num(ctr.z or ctr[3])
                    local sx, sy, szv = num(sz.x or sz[1]), num(sz.y or sz[2]), num(sz.z or sz[3])
                    bx1, by1, bz1 = cx - sx*0.5, cy - sy*0.5, cz - szv*0.5
                    bx2, by2, bz2 = cx + sx*0.5, cy + sy*0.5, cz + szv*0.5
                elseif t.x or t[1] then
                    local ax, ay, az = num(t.x or t[1]), num(t.y or t[2]), num(t.z or t[3])
                    bx1, by1, bz1 = -math.abs(ax), -math.abs(ay), -math.abs(az)
                    bx2, by2, bz2 =  math.abs(ax),  math.abs(ay),  math.abs(az)
                end
            end
        end
        sanitizeBounds()
        bx1,by1,bz1 = bx1 or -0.5, by1 or -0.5, bz1 or -0.5
        bx2,by2,bz2 = bx2 or 0.5,  by2 or 0.5,  bz2 or 0.5
        local halfModelX = math.max(math.abs(bx1), math.abs(bx2))
        local halfModelY = math.max(math.abs(by1), math.abs(by2))
        local halfModelZ = math.max(math.abs(bz1), math.abs(bz2))
        local margin = 0.02 * (halfModelZ + halfModelX + d)
        local newXMin, newXMax = - (halfW + halfModelX + margin), (halfW + halfModelX + margin)
        local newZMin, newZMax = - (halfH + halfModelZ + margin), (halfH + halfModelZ + margin)
        local newYMin, newYMax = - (halfW + halfModelY + margin), (halfW + halfModelY + margin)
        if xSlider then xSlider:SetMinMaxValues(newXMin, newXMax) end
        if ySlider then ySlider:SetMinMaxValues(newYMin, newYMax) end
        if zSlider then zSlider:SetMinMaxValues(newZMin, newZMax) end

        -- Smart zoom range: map model size to camera distances and then to portrait zoom
        do
            local tanH = math.max(1e-6, math.tan(hfov * 0.5))
            local tanV = math.max(1e-6, math.tan(vfov * 0.5))
            -- Far bound: character is about half the screen size
            local dFarW = (2.0 * halfModelX) / tanH
            local dFarH = (2.0 * halfModelZ) / tanV
            local dFar = math.max(dFarW, dFarH)
            -- Close bound: character just out of sight (~5% overflow)
            local rClose = 1.05
            local dCloseW = (halfModelX / rClose) / tanH
            local dCloseH = (halfModelZ / rClose) / tanV
            local dClose = math.min(dCloseW, dCloseH)
            -- Respect renderer floor distance used by scene backend
            if h._backend and h._backend.kind == "scene" then
                dClose = math.max(1.2, dClose)
                dFar = math.max(dClose + 0.01, dFar) -- ensure ordering
                -- Invert distance back to portrait zoom using the scene mapping: d ≈ 3.2 - 2.6*z
                local function distToZoom(dist)
                    local z = (3.2 - dist) / 2.6
                    return clamp(z, zoomMin, zoomMax)
                end
                dynZoomMin, dynZoomMax = distToZoom(dFar), distToZoom(dClose)
            else
                -- Fallback: use normalized 0..1 range for players/other backends
                dynZoomMin, dynZoomMax = 0.0, 1.0
            end
            if zoomSlider and dynZoomMin and dynZoomMax then
                local zmin = math.min(dynZoomMin, dynZoomMax)
                local zmax = math.max(dynZoomMin, dynZoomMax)
                zoomSlider:SetMinMaxValues(zmin, zmax)
                local cur = zoomSlider:GetValue() or 0
                local adj = clamp(cur, zmin, zmax)
                if adj ~= cur then zoomSlider:SetValue(adj) end
                if zoomSlider._valueText then zoomSlider._valueText:SetText(string.format("%.3f", adj)) end
            end
        end
        -- Clamp current slider values into new ranges and reapply
        local changed = false
        if xSlider and xSlider.GetValue then
            local vx = xSlider:GetValue()
            local nx = clamp(vx, newXMin, newXMax)
            if nx ~= vx then xSlider:SetValue(nx); slX = nx; changed = true; if xSlider._valueText then xSlider._valueText:SetText(string.format("%.3f", nx)) end end
        end
        if ySlider and ySlider.GetValue then
            local vy = ySlider:GetValue()
            local ny = clamp(vy, newYMin, newYMax)
            if ny ~= vy then ySlider:SetValue(ny); changed = true end
            -- Inverted mapping: slider value = -worldY
            local wy = clamp(-(ySlider:GetValue()), newYMin, newYMax)
            if slY ~= wy then slY = wy; changed = true end
            if ySlider._valueText then ySlider._valueText:SetText(string.format("%.3f", slY)) end
        end
        if zSlider and zSlider.GetValue then
            local vz = zSlider:GetValue()
            local nz = clamp(vz, newZMin, newZMax)
            if nz ~= vz then zSlider:SetValue(nz); slZ = nz; changed = true; if zSlider._valueText then zSlider._valueText:SetText(string.format("%.3f", nz)) end end
        end
    if changed then applyTargetFromState() end
    end
    local function addLabel(text)
        local fs = ctrlPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", ctrlPanel, "TOPLEFT", 0, y)
        fs:SetText(text)
        y = y - 18
        return fs
    end
    local function addSlider(label, minV, maxV, step, onChanged, tooltip)
        local l = addLabel(label)
        local s = CreateFrame("Slider", nil, ctrlPanel, "OptionsSliderTemplate")
        s:SetPoint("TOPLEFT", ctrlPanel, "TOPLEFT", 0, y)
        s:SetWidth(200)
        s:SetMinMaxValues(minV, maxV)
        s:SetValueStep(step)
        s:SetObeyStepOnDrag(true)
    -- Hide template's default Low/High/Text labels; we render our own value text
    if s.Text then s.Text:Hide() end
    if s.Low then s.Low:Hide() end
    if s.High then s.High:Hide() end
        -- When unnamed, OptionsSliderTemplate won't auto-create Low/High/Text globals; we don't need them here.
        s:SetScript("OnValueChanged", function(_, val)
            if onChanged then onChanged(s, val) end
        end)
        if tooltip then
            s:EnableMouse(true)
            s:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tooltip, 1,1,1,1, true)
            end)
            s:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        local vt = ctrlPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        vt:SetPoint("LEFT", s, "RIGHT", 6, 0)
        vt:SetText("0.000")
        s._valueText = vt
        y = y - 36
        return s
    end
    local function addButton(text, onClick, width, tooltip)
        local b = CreateFrame("Button", nil, ctrlPanel, "UIPanelButtonTemplate")
        b:SetSize(width or 90, 22)
        b:SetPoint("TOPLEFT", ctrlPanel, "TOPLEFT", 0, y)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        if tooltip then
            b:SetMotionScriptsWhileDisabled(true)
            b:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tooltip, 1,1,1,1, true)
            end)
            b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        y = y - 26
        return b
    end
    local function addCheck(text, getter, setter, tooltip)
        local cb = CreateFrame("CheckButton", nil, ctrlPanel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", ctrlPanel, "TOPLEFT", 0, y)
        cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cb.text:SetText(text)
        cb:SetScript("OnShow", function(self)
            if getter then self:SetChecked(getter()) end
        end)
        cb:SetScript("OnClick", function(self)
            if setter then setter(self:GetChecked()) end
        end)
        if tooltip then
            cb:SetMotionScriptsWhileDisabled(true)
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tooltip, 1,1,1,1, true)
            end)
            cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        y = y - 22
        return cb
    end

    -- Controls: yaw/zoom/z and XY pan
    addLabel("Yaw / Zoom / Pan")
    local yawSlider = addSlider("Yaw", yawMin, yawMax, 0.01, function(sldr, v)
        local h = getTargetHost()
        local vv = clamp(v, yawMin, yawMax)
        if h then
            h._userControlledCamera = true
            if h.SetActorYaw then h:SetActorYaw(vv) elseif h.SetRotation then h:SetRotation(vv) end
        end
        if sldr and sldr._valueText then sldr._valueText:SetText(string.format("%.3f", vv)) end
    end, "Right-drag to orbit as well. Yaw rotates around vertical axis.")
    local zoomSlider = addSlider("Zoom", zoomMin, zoomMax, 0.01, function(sldr, v)
        local h = getTargetHost(); 
        if h and h.SetPortraitZoom then 
            h._userControlledCamera = true
            local zv=clampZoomForHost(h, v); 
            h:SetPortraitZoom(zv); 
            if sldr and sldr._valueText then sldr._valueText:SetText(string.format("%.3f", zv)) end 
        end 
    end, "Mouse wheel also changes zoom.")
    local zSlider = addSlider("Z Pan", zMin, zMax, 0.005, function(sldr, v)
        local mn,mx = zMin,zMax; if sldr and sldr.GetMinMaxValues then mn,mx = sldr:GetMinMaxValues() end
        slZ = clamp(v, mn, mx)
        applyTargetFromState()
        if sldr and sldr._valueText then sldr._valueText:SetText(string.format("%.3f", slZ)) end
    end, "Move the model up/down in screen space.")
    local xSlider = addSlider("X Pan", xMin, xMax, 0.01, function(sldr, v)
        local mn,mx = xMin,xMax; if sldr and sldr.GetMinMaxValues then mn,mx = sldr:GetMinMaxValues() end
        slX = clamp(v, mn, mx)
        applyTargetFromState()
        if sldr and sldr._valueText then sldr._valueText:SetText(string.format("%.3f", slX)) end
    end, "Pan horizontally depending on camera axis.")
    local ySlider = addSlider("Y Pan", yMin, yMax, 0.01, function(sldr, v)
        local mn,mx = yMin,yMax; if sldr and sldr.GetMinMaxValues then mn,mx = sldr:GetMinMaxValues() end
        -- Invert mapping so increasing slider value moves model the intuitive direction
        slY = clamp(-v, mn, mx)
        applyTargetFromState()
        if sldr and sldr._valueText then sldr._valueText:SetText(string.format("%.3f", slY)) end
    end, "Pan horizontally depending on camera axis.")

    -- Store slider references for mirror interaction updates
    DW._sliders = { yaw = yawSlider, zoom = zoomSlider, z = zSlider, x = xSlider, y = ySlider }

    -- Forward declaration for refreshInfo function
    local refreshInfo

    -- Sync sliders and ranges to the current host state (zoom/yaw/target and pan limits)
    local function syncControlsToHost(h)
        h = h or getTargetHost(); if not h then return end
        -- Update slider values from host
        local vy = (h.GetActorYaw and (h:GetActorYaw() or 0)) or 0
        local vz = (h.GetPortraitZoom and (h:GetPortraitZoom() or 0.65)) or 0.65
        local s = h._lastCamSnapshot or {}
        local nx, ny, nz = s.tx or 0, s.ty or 0, s.tz or 0
        if yawSlider and yawSlider.SetValue then yawSlider:SetValue(vy); if yawSlider._valueText then yawSlider._valueText:SetText(string.format("%.3f", vy)) end end
        if zoomSlider and zoomSlider.SetValue then zoomSlider:SetValue(vz); if zoomSlider._valueText then zoomSlider._valueText:SetText(string.format("%.3f", vz)) end end
        if xSlider and xSlider.SetValue then xSlider:SetValue(nx); if xSlider._valueText then xSlider._valueText:SetText(string.format("%.3f", nx)) end end
        if ySlider and ySlider.SetValue then ySlider:SetValue(-ny); if ySlider._valueText then ySlider._valueText:SetText(string.format("%.3f", ny)) end end
        if zSlider and zSlider.SetValue then zSlider:SetValue(nz); if zSlider._valueText then zSlider._valueText:SetText(string.format("%.3f", nz)) end end
        -- Recompute pan/zoom ranges based on new model bounds/FOV
        updatePanRanges()
        -- Refresh info panel snapshot
        refreshInfo()
    end

    -- Attach a one-time-per-host loader hook to resync controls after model finishes loading
    local function attachLoadSync(h)
        h = h or getTargetHost(); if not (h and h.OnModelLoadedOnce) then return end
        if h._dwLoadSyncAttached then return end
        h._dwLoadSyncAttached = true
        h:OnModelLoadedOnce(function()
            syncControlsToHost(h)
        end)
    end
    -- Expose helpers for use outside Create()
    DW._SyncControlsToHost = function(_, host) syncControlsToHost(host) end
    DW._AttachLoadSync = function(_, host) attachLoadSync(host) end

    -- Reset button: restore origin/default camera
    addButton("Reset", function()
        local h = getTargetHost()
        local oyaw = DW._originYaw
        local ozoom = DW._originZoom
        local ot = DW._originTarget
        if oyaw ~= nil then
            local vy = clamp(oyaw, yawMin, yawMax)
            if h then h._userControlledCamera = true end
            if h and h.SetActorYaw then h:SetActorYaw(vy) elseif h and h.SetRotation then h:SetRotation(vy) end
            if yawSlider and yawSlider.SetValue then yawSlider:SetValue(vy); if yawSlider._valueText then yawSlider._valueText:SetText(string.format("%.3f", vy)) end end
        end
        if ozoom ~= nil and h and h.SetPortraitZoom then
            if h then h._userControlledCamera = true end
            local vz = clampZoomForHost(h, ozoom)
            h:SetPortraitZoom(vz)
            if zoomSlider and zoomSlider.SetValue then zoomSlider:SetValue(vz); if zoomSlider._valueText then zoomSlider._valueText:SetText(string.format("%.3f", vz)) end end
        end
        if ot and h and h.SetTarget then
            local sxMin, sxMax = xMin, xMax
            local syMin, syMax = yMin, yMax
            local szMin, szMax = zMin, zMax
            if xSlider and xSlider.GetMinMaxValues then sxMin, sxMax = xSlider:GetMinMaxValues() end
            if ySlider and ySlider.GetMinMaxValues then syMin, syMax = ySlider:GetMinMaxValues() end
            if zSlider and zSlider.GetMinMaxValues then szMin, szMax = zSlider:GetMinMaxValues() end
            local nx = clamp(ot.x or 0, sxMin, sxMax)
            local ny = clamp(ot.y or 0, syMin, syMax)
            local nz = clamp(ot.z or 0, szMin, szMax)
            h._userControlledCamera = true
            h:SetTarget({ x = nx, y = ny, z = nz })
            slX, slY, slZ = nx, ny, nz
            if xSlider and xSlider.SetValue then xSlider:SetValue(nx); if xSlider._valueText then xSlider._valueText:SetText(string.format("%.3f", nx)) end end
            if ySlider and ySlider.SetValue then ySlider:SetValue(-ny); if ySlider._valueText then ySlider._valueText:SetText(string.format("%.3f", ny)) end end
            if zSlider and zSlider.SetValue then zSlider:SetValue(nz); if zSlider._valueText then zSlider._valueText:SetText(string.format("%.3f", nz)) end end
        else
            if h and h.FrameFullBodyFront then h:FrameFullBodyFront(0.12) end
            if h and h.FaceCamera then h:FaceCamera() end
            local s = h and h._lastCamSnapshot or {}
            if yawSlider and yawSlider.SetValue then local vy=(h and h.GetActorYaw and (h:GetActorYaw() or 0)) or 0; yawSlider:SetValue(vy); if yawSlider._valueText then yawSlider._valueText:SetText(string.format("%.3f", vy)) end end
            if zoomSlider and zoomSlider.SetValue then local vz=(h and h.GetPortraitZoom and (h:GetPortraitZoom() or 0.65)) or 0.65; zoomSlider:SetValue(vz); if zoomSlider._valueText then zoomSlider._valueText:SetText(string.format("%.3f", vz)) end end
            local nx, ny, nz = s.tx or 0, s.ty or 0, s.tz or 0
            slX, slY, slZ = nx, ny, nz
            if xSlider and xSlider.SetValue then xSlider:SetValue(nx); if xSlider._valueText then xSlider._valueText:SetText(string.format("%.3f", nx)) end end
            if ySlider and ySlider.SetValue then ySlider:SetValue(-ny); if ySlider._valueText then ySlider._valueText:SetText(string.format("%.3f", ny)) end end
            if zSlider and zSlider.SetValue then zSlider:SetValue(nz); if zSlider._valueText then zSlider._valueText:SetText(string.format("%.3f", nz)) end end
        end
        DW._lastDragDelta = nil
    end, 90, "Restore camera/origin to the snapshot when the model loaded.")

    addButton("Face Camera", function()
        local h = getTargetHost(); if h and h.FaceCamera then h:FaceCamera() end
    end, nil, "Rotate to face the camera")
    addButton("Flip Facing", function()
        local h = getTargetHost(); if h and h.FlipFacing then h:FlipFacing() end
    end, nil, "Rotate 180°")

    -- Auto-face toggle
    addCheck("Auto-face camera", function() local h = getTargetHost(); return h._autoFaceCamera ~= false end, function(val)
        local h = getTargetHost(); h._autoFaceCamera = val and true or false
    end, "Keep model roughly facing camera when framing/refitting")
    -- Auto-refit on load toggle (persisted)
    DW._autoRefit = (cfg.autoRefit ~= false)
    addCheck("Auto-refit on load", function() return DW._autoRefit end, function(v)
        DW._autoRefit = v and true or false
        if CLN and CLN.db and CLN.db.profile then
            CLN.db.profile.debugWindow = CLN.db.profile.debugWindow or {}
            CLN.db.profile.debugWindow.autoRefit = DW._autoRefit
        end
    end, "Automatically frame model and face camera once it loads")

    -- Manual DisplayID loader
    addLabel("Model Loading")
    local displayRow = CreateFrame("Frame", nil, ctrlPanel)
    displayRow:SetPoint("TOPLEFT", ctrlPanel, "TOPLEFT", 0, y)
    displayRow:SetSize(220, 24)
    local displayBox = CreateFrame("EditBox", nil, displayRow, "InputBoxTemplate")
    displayBox:SetPoint("LEFT", displayRow, "LEFT", 0, 0)
    displayBox:SetSize(80, 22)
    displayBox:SetNumeric(true)
    if displayBox and displayBox.SetPropagateKeyboardInput then displayBox:SetPropagateKeyboardInput(true) end
    if displayBox and displayBox.EnableKeyboard then displayBox:EnableKeyboard(false) end
    local loadBtn = CreateFrame("Button", nil, displayRow, "UIPanelButtonTemplate")
    loadBtn:SetPoint("LEFT", displayBox, "RIGHT", 6, 0)
    loadBtn:SetSize(70, 22)
    loadBtn:SetText("Load")
    loadBtn:SetScript("OnClick", function()
        local id = tonumber(displayBox:GetText() or "")
        if id then
            local h = getTargetHost()
            if h and h.SetDisplayInfo then
                if CLN and CLN.Logger then CLN.Logger:debug("[DW] Manual load SetDisplayInfo id=" .. tostring(id), false, CLN.Utils.LogCategories.ui) end
                local ok = pcall(h.SetDisplayInfo, h, id)
                if CLN and CLN.Logger then CLN.Logger:debug("[DW] Manual load SetDisplayInfo success=" .. tostring(ok), false, CLN.Utils.LogCategories.ui) end
                if ok and DW._autoRefit ~= false then
                    -- Refit after loading
                    local function refit()
                        if h.FrameFullBodyFront then h:FrameFullBodyFront(0.12) end
                        if h.FaceCamera then h:FaceCamera() end
                    end
                    if C_Timer and C_Timer.After then C_Timer.After(0.10, refit) else refit() end
                end
            else
                if CLN and CLN.Logger then CLN.Logger:warn("[DW] Manual load: Host missing SetDisplayInfo method", false, CLN.Utils.LogCategories.ui) end
            end
        end
    end)
    y = y - 28

    -- Anim triggers
    addLabel("Animations")
    -- Force-animate toggle: when on, call the actor directly to bypass global no-anim debug
    DW._forceAnim = (DW._forceAnim ~= false)
    local function playAnim(id)
        local h = getTargetHost(); if not h then return end
        if DW._forceAnim and h._backend and h._backend.actor and h._backend.actor.SetAnimation then
            local a = h._backend.actor
            local okLoaded = true
            if a.IsLoaded then
                local ok, l = pcall(a.IsLoaded, a)
                okLoaded = ok and l or false
            end
            if okLoaded then pcall(a.SetAnimation, a, id) end
        elseif h.SetAnimation then
            h:SetAnimation(id)
        end
    end
    addButton("Idle (0)", function() playAnim(0) end, 90)
    addButton("Talk (60)", function() playAnim(60) end, 90)
    addButton("Talk! (64)", function() playAnim(64) end, 90)
    addButton("Talk? (65)", function() playAnim(65) end, 90)
    addButton("Wave (67)", function() playAnim(67) end, 90)
    -- Freeform anim id
    local animRow = CreateFrame("Frame", nil, ctrlPanel)
    animRow:SetPoint("TOPLEFT", ctrlPanel, "TOPLEFT", 0, y)
    animRow:SetSize(220, 24)
    local animBox = CreateFrame("EditBox", nil, animRow, "InputBoxTemplate")
    animBox:SetPoint("LEFT", animRow, "LEFT", 0, 0)
    animBox:SetSize(60, 22)
    animBox:SetNumeric(true)
    if animBox and animBox.SetPropagateKeyboardInput then animBox:SetPropagateKeyboardInput(true) end
    if animBox and animBox.EnableKeyboard then animBox:EnableKeyboard(false) end
    local animBtn = CreateFrame("Button", nil, animRow, "UIPanelButtonTemplate")
    animBtn:SetPoint("LEFT", animBox, "RIGHT", 6, 0)
    animBtn:SetSize(70, 22)
    animBtn:SetText("Play")
    animBtn:SetScript("OnClick", function()
        local id = tonumber(animBox:GetText() or "")
        if id then playAnim(id) end
    end)
    y = y - 28

    -- Presets and refit
    addLabel("Framing")
    addButton("Refit (FullBody)", function()
        local h = getTargetHost()
        if h and h.ApplyPreset then
            h:ApplyPreset("FullBody")
        elseif h and h.FrameFullBodyFront then
            h:FrameFullBodyFront(0.10)
        end
        if h and h.FaceCamera then h:FaceCamera() end
    end, 120, "Solve a full-body view and face camera")
    addButton("Preset: FullBody", function()
        local h = getTargetHost(); if h and h.ApplyPreset then h:ApplyPreset("FullBody") end
    end, 120, "Apply FullBody preset only")
    addButton("Preset: UpperBody", function()
        local h = getTargetHost(); if h and h.ApplyPreset then h:ApplyPreset("UpperBody") end
    end, 120, "Upper body framing preset")
    addButton("Preset: Wave", function()
        local h = getTargetHost(); if h and h.ApplyPreset then h:ApplyPreset("Wave") end
    end, 120, "Wave preset framing")

    -- Right column: structured outputs
    local oy = -4
    local function outLabel(text)
        local parent = contentAnchor or rightCol
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, oy)
        fs:SetText(text)
        oy = oy - 18
        return fs
    end
    local function outBox(height)
        local parent = contentAnchor or rightCol
        local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, oy)
        sf:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
        sf:SetHeight(height)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(GameFontHighlightSmall)
        eb:SetAutoFocus(false)
        eb:SetWidth(260)
    sf:SetScrollChild(eb)
    -- Do not consume any keyboard events
    if eb and eb.SetPropagateKeyboardInput then eb:SetPropagateKeyboardInput(true) end
    if eb and eb.EnableKeyboard then eb:EnableKeyboard(false) end
        oy = oy - (height + 10)
        return sf, eb
    end

    outLabel("Realtime Info")
    local infoScroll, infoEdit = outBox(140)
    -- Allow temporary focus for copy, then auto-disable keyboard again
    if infoEdit then
        infoEdit:SetScript("OnEscapePressed", function(self)
            if self.ClearFocus then self:ClearFocus() end
        end)
        infoEdit:SetScript("OnEditFocusLost", function(self)
            if self.EnableKeyboard then self:EnableKeyboard(false) end
        end)
    end

    local function snapshotText()
        local host = activeHost()
        local lines = {}
        -- Zoom / Pan / Yaw
        local zoom = host and host.GetPortraitZoom and host:GetPortraitZoom() or (host and host._zoom) or 0
        local yaw = host and (host.GetActorYaw and host:GetActorYaw()) or 0
        table.insert(lines, string.format("zoom=%s yaw=%s", fmtNum(zoom), fmtNum(yaw)))
        -- Session
        if host and host._lastCamSnapshot and host._lastCamSnapshot.sessionId then
            table.insert(lines, string.format("sessionId=%s", tostring(host._lastCamSnapshot.sessionId)))
        elseif host and host._sessionId then
            table.insert(lines, string.format("sessionId=%s", tostring(host._sessionId)))
        end
        -- Loader metrics (ModelScene)
        if host and host._lastLoadSession then
            local sL = host._lastLoadSession
            local ms = 0
            local gt = (type(GetTime) == "function") and GetTime() or 0
            if sL.start then ms = math.max(0, (gt - (sL.start or 0)) * 1000) end
            table.insert(lines, string.format("load[%s]=%s state=%s attempts=%s t=%.0fms", tostring(sL.kind or "?"), tostring(sL.arg or "?"), tostring(sL.state or "?"), tostring(sL.attempts or 0), ms))
        end
        -- Target Z if we can infer
        if host and host._currentZOffset then table.insert(lines, string.format("zOffset=%s", fmtNum(host._currentZOffset))) end
        -- Target X/Y if snapshot exists
        local s = host and host._lastCamSnapshot
        if s then
            table.insert(lines, string.format("target=(%.2f,%.2f,%.2f)", s.tx or 0, s.ty or 0, s.tz or 0))
        end
        -- Delta from origin
        if DW._originTarget and s then
            local dx = (s.tx or 0) - (DW._originTarget.x or 0)
            local dy = (s.ty or 0) - (DW._originTarget.y or 0)
            local dz = (s.tz or 0) - (DW._originTarget.z or 0)
            table.insert(lines, string.format("originΔ=(%.3f,%.3f,%.3f)", dx, dy, dz))
        end
        -- Last drag delta (since mouse down)
        if DW._lastDragDelta then
            table.insert(lines, string.format("dragΔ=(%.3f,%.3f,%.3f)", DW._lastDragDelta.x or 0, DW._lastDragDelta.y or 0, DW._lastDragDelta.z or 0))
        end
        -- Bounds (scene only)
    if host and host._backend and host._backend.kind == "scene" then
            local a = host._backend.actor
            if a and a.GetActiveBoundingBox then
                local ok,x1,y1,z1,x2,y2,z2 = pcall(a.GetActiveBoundingBox, a)
                if ok then
                    table.insert(lines, string.format("bbox: (%.2f,%.2f,%.2f)-(%.2f,%.2f,%.2f)", x1 or 0,y1 or 0,z1 or 0,x2 or 0,y2 or 0,z2 or 0))
                end
            end
        end
        -- Camera snapshot if exposed by the renderer
        if s then
            table.insert(lines, string.format("cam pos=(%.2f,%.2f,%.2f)", s.px or 0, s.py or 0, s.pz or 0))
            table.insert(lines, string.format("cam tgt=(%.2f,%.2f,%.2f)", s.tx or 0, s.ty or 0, s.tz or 0))
            table.insert(lines, string.format("fov v=%.3f h=%.3f axis=%s d=%.2f", s.vfov or 0, s.hfov or 0, tostring(s.axis), s.dist or 0))
        end
        return table.concat(lines, "\n")
    end

    refreshInfo = function()
        infoEdit:SetText(snapshotText())
    end

    -- Copy info button (right column)
    local copyInfoBtn = CreateFrame("Button", nil, contentAnchor or rightCol, "UIPanelButtonTemplate")
    copyInfoBtn:SetPoint("TOPLEFT", contentAnchor or rightCol, "TOPLEFT", 0, oy)
    copyInfoBtn:SetSize(100, 22)
    copyInfoBtn:SetText("Copy Info")
    copyInfoBtn:SetScript("OnClick", function()
        if not infoEdit then return end
        if infoEdit.EnableKeyboard then infoEdit:EnableKeyboard(true) end
        if infoEdit.SetPropagateKeyboardInput then infoEdit:SetPropagateKeyboardInput(true) end
        if infoEdit.SetFocus then infoEdit:SetFocus() end
        if infoEdit.HighlightText then infoEdit:HighlightText(0, -1) end
    end)
    -- Quick help button next to Copy Info
    local helpBtn = CreateFrame("Button", nil, contentAnchor or rightCol, "UIPanelButtonTemplate")
    helpBtn:SetPoint("LEFT", copyInfoBtn, "RIGHT", 6, 0)
    helpBtn:SetSize(80, 22)
    helpBtn:SetText("Help")
    helpBtn:SetScript("OnClick", function()
        if not DW._helpDialog then
            local dlg = CreateFrame("Frame", "CLN_DebugHelpDialog", UIParent, "BackdropTemplate")
            dlg:SetSize(520, 260)
            dlg:SetPoint("CENTER")
            dlg:SetFrameStrata("DIALOG")
            dlg:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            dlg:SetBackdropColor(0, 0, 0, 0.95)
            local close = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
            close:SetPoint("TOPRIGHT", dlg, "TOPRIGHT")
            close:SetScript("OnClick", function() dlg:Hide() end)
            local fs = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            fs:SetPoint("TOPLEFT", dlg, "TOPLEFT", 10, -10)
            fs:SetJustifyH("LEFT")
            fs:SetJustifyV("TOP")
            fs:SetText("Mouse: Left-drag Pan, Right-drag Orbit, Wheel Zoom\nButtons: Reset, Face Camera, Flip Facing, Refit presets\nTips: Auto-face camera keeps facing toward camera. Auto-refit frames on load.\nLogs: Use Open Logs Window or /clnlogs.")
            fs:SetWidth(500)
            DW._helpDialog = dlg
        end
        DW._helpDialog:Show()
    end)
    oy = oy - 26

    -- Logs shortcut (right column)
    outLabel("Logs")
    local row = CreateFrame("Frame", nil, contentAnchor or rightCol)
    row:SetPoint("TOPLEFT", contentAnchor or rightCol, "TOPLEFT", 0, oy)
    row:SetSize(260, 24)
    local openLogsBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    openLogsBtn:SetPoint("LEFT", row, "LEFT", 0, 0)
    openLogsBtn:SetSize(140, 22)
    openLogsBtn:SetText("Open Logs Window")
    openLogsBtn:SetScript("OnClick", function()
        if ReplayFrame and ReplayFrame.LogsWindow and ReplayFrame.LogsWindow.Show then
            ReplayFrame.LogsWindow:Show()
        end
    end)
    oy = oy - 28
    local function json_encode(val)
        local t = type(val)
        if t == "nil" then return "null" end
        if t == "number" then return tostring(val)
        elseif t == "boolean" then return val and "true" or "false"
        elseif t == "string" then return string.format('%q', val)
        elseif t == "table" then
            local isArray = true
            local idx = 1
            for k,_ in pairs(val) do if k ~= idx then isArray = false break else idx = idx + 1 end end
            if isArray then
                local parts = {}
                for i=1,#val do table.insert(parts, json_encode(val[i])) end
                return "[" .. table.concat(parts, ",") .. "]"
            else
                local parts = {}
                for k,v in pairs(val) do table.insert(parts, string.format('%q:%s', tostring(k), json_encode(v))) end
                return "{" .. table.concat(parts, ",") .. "}"
            end
        else
            return string.format('%q', tostring(val))
        end
    end
    -- Export JSON button (right column top-right)
    local exportBtn = CreateFrame("Button", nil, contentAnchor or rightCol, "UIPanelButtonTemplate")
    exportBtn:SetPoint("TOPRIGHT", contentAnchor or rightCol, "TOPRIGHT", 0, 0)
    exportBtn:SetSize(100, 22)
    exportBtn:SetText("Export JSON")
    exportBtn:SetScript("OnClick", function()
        local h = activeHost()
        local s = (h and h._lastCamSnapshot) or {}
        local bounds = h and h.GetBounds and h:GetBounds() or nil
        local payload = {
            displayID = h and h._displayID,
            sessionId = s.sessionId or (h and h._sessionId),
            snapshot = s,
            bounds = bounds,
            options = {
                zoom = h and h.GetPortraitZoom and h:GetPortraitZoom() or (h and h._zoom),
                yaw = h and h.GetActorYaw and h:GetActorYaw() or (h and h._frontYaw),
                autoFace = h and (h._autoFaceCamera ~= false),
                compBias = h and h._compBias,
                axis = h and h._camAxis,
                dist = h and h._camDist,
                dir = h and h._camDir,
            }
        }
    local txt = json_encode(payload)
    -- Show a simple modal to copy the JSON
    local dlg = DW._exportDialog
    if not dlg then
        dlg = CreateFrame("Frame", "CLN_DebugExportDialog", UIParent, "BackdropTemplate")
        dlg:SetSize(780, 360)
        dlg:SetPoint("CENTER")
        dlg:SetFrameStrata("DIALOG")
        dlg:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        dlg:SetBackdropColor(0, 0, 0, 0.95)
        local close = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", dlg, "TOPRIGHT")
        close:SetScript("OnClick", function() dlg:Hide() end)
        local sf = CreateFrame("ScrollFrame", nil, dlg, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", dlg, "TOPLEFT", 10, -8)
        sf:SetPoint("BOTTOMRIGHT", dlg, "BOTTOMRIGHT", -24, 10)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        eb:SetAutoFocus(false)
        eb:SetWidth(720)
        sf:SetScrollChild(eb)
        dlg._edit = eb
        DW._exportDialog = dlg
    end
    if dlg._edit and dlg._edit.SetText then dlg._edit:SetText(txt) end
    dlg:Show()
    if dlg._edit and dlg._edit.HighlightText then dlg._edit:HighlightText(0, -1) end
    if dlg._edit and dlg._edit.SetFocus then dlg._edit:SetFocus() end
    end)

    -- Control/main toggles (left column)
    local useMirrorChk = addCheck("Use Mirror Frame", function() return DW._useMirror end, function(val)
        DW._useMirror = val and true or false
        if DW._useMirror then ensureMirror() if DW.mirrorFrame then DW.mirrorFrame:Show() end else if DW.mirrorFrame then DW.mirrorFrame:Hide() end end
    end)
    local controlChk = addCheck("Control ReplayFrame model", function() return false end, function(val) DW._controlMain = val and true or false end)
    DW._useTargetNPC = (DW._useTargetNPC ~= false) -- default ON
    local useTargetChk = addCheck("Use Target NPC (preview)", function() return DW._useTargetNPC end, function(v)
        DW._useTargetNPC = v and true or false
        if DW._useTargetNPC then DW:PreviewTarget() end
    end)
    local lockSizeChk = addCheck("Lock mirror size to ReplayFrame", function() return DW._mirrorLockSize end, function(v) DW._mirrorLockSize = v and true or false end)
    local followPosChk = addCheck("Follow mirror position", function() return DW._mirrorFollowPos end, function(v) DW._mirrorFollowPos = v and true or false end)
    -- Expanded vs match sizing for the embedded preview
    local expandChk = addCheck("Expanded preview", function() return DW._previewExpanded end, function(v)
        DW._previewExpanded = v and true or false
        if DW._UpdatePreviewSize then DW._UpdatePreviewSize() end
        if CLN and CLN.db and CLN.db.profile then
            CLN.db.profile.debugWindow = CLN.db.profile.debugWindow or {}
            CLN.db.profile.debugWindow.expanded = DW._previewExpanded
        end
    end, "Fill the preview column (on); otherwise match ReplayFrame size")
    -- Lock window toggle (persisted)
    DW._lockWindow = (cfg.lockWindow == true)
    addCheck("Lock window", function() return DW._lockWindow end, function(v)
        DW._lockWindow = v and true or false
        f:SetMovable(not DW._lockWindow)
        if CLN and CLN.db and CLN.db.profile then
            CLN.db.profile.debugWindow = CLN.db.profile.debugWindow or {}
            CLN.db.profile.debugWindow.lockWindow = DW._lockWindow
        end
    end, "Prevent dragging this window")
    -- Force animations toggle for preview host (bypass ReplayFrame no-anim debug)
    local forceAnimChk = addCheck("Force animations (preview)", function() return DW._forceAnim end, function(v)
        DW._forceAnim = v and true or false
    end)

    f:SetScript("OnShow", function()
        -- Seed UI with current values
        if DW._useMirror then ensureMirror() end
        -- Keep embedded model area hidden so the controls can use full height
        if modelArea then modelArea:Hide() end
        if overlay then overlay:Hide() end
        if embedHost then embedHost:Hide() end
        -- Default to expanded preview on first open
        if DW._previewExpanded == nil then DW._previewExpanded = true end
        if DW._UpdatePreviewSize then DW._UpdatePreviewSize() end
    -- Release any lingering focus from text fields on show
    if infoEdit and infoEdit.ClearFocus then infoEdit:ClearFocus() end
    local th = getTargetHost()
    if DW._AttachLoadSync then DW:_AttachLoadSync(th) end
    if DW._SyncControlsToHost then DW:_SyncControlsToHost(th) end
    local vy = th and th.GetActorYaw and (th:GetActorYaw() or 0) or 0
    local vz = th and th.GetPortraitZoom and (th:GetPortraitZoom() or 0.65) or 0.65
    if yawSlider and yawSlider.SetValue then yawSlider:SetValue(vy); if yawSlider._valueText then yawSlider._valueText:SetText(string.format("%.3f", vy)) end end
    if zoomSlider and zoomSlider.SetValue then zoomSlider:SetValue(vz); if zoomSlider._valueText then zoomSlider._valueText:SetText(string.format("%.3f", vz)) end end
        local s = th and th._lastCamSnapshot or (embedHost and embedHost._lastCamSnapshot)
        slZ = (s and s.tz) or 0; slX = (s and s.tx) or 0; slY = (s and s.ty) or 0
    if zSlider and zSlider.SetValue then zSlider:SetValue(slZ); if zSlider._valueText then zSlider._valueText:SetText(string.format("%.3f", slZ)) end end
    if xSlider and xSlider.SetValue then xSlider:SetValue(slX); if xSlider._valueText then xSlider._valueText:SetText(string.format("%.3f", slX)) end end
    if ySlider and ySlider.SetValue then ySlider:SetValue(-slY); if ySlider._valueText then ySlider._valueText:SetText(string.format("%.3f", slY)) end end
    updatePanRanges()
    refreshInfo()
    -- Adjust control scroll height/width
    local totalH = math.max(300, -y + 20)
    ctrlPanel:SetHeight(totalH)
    local w = ctrlScroll:GetWidth() or 220
    ctrlPanel:SetWidth(math.max(200, w - 22))
    -- Show mirror if enabled (it may have been hidden on last close)
    if DW._useMirror then ensureMirror(); if DW.mirrorFrame then DW.mirrorFrame:Show() end end
    -- If using target NPC, prefer displayID-based preview
    if DW._useTargetNPC then
            DW:PreviewTarget()
        end
    end)

    -- Make left panel fill height by reacting to size changes
    ctrlScroll:SetScript("OnSizeChanged", function(_, w2, h2)
        if not w2 or not h2 then return end
        ctrlPanel:SetWidth(math.max(200, (w2 or 220) - 22))
        ctrlPanel:SetHeight(math.max(300, -y + 20, h2))
    end)

    -- Update preview when player target changes (only if using target preview)
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:SetScript("OnEvent", function(_, evt)
        if evt == "PLAYER_TARGET_CHANGED" then
            if not f:IsShown() then return end
            if not DW._useTargetNPC then return end
            DW:PreviewTarget()
        end
    end)
    -- Also hide the mirror debug window when DebugWindow is hidden via any means
    f:SetScript("OnHide", function()
        if DW and DW.mirrorFrame then DW.mirrorFrame:Hide() end
    -- Make sure no edit box keeps focus once hidden
    if infoEdit and infoEdit.ClearFocus then infoEdit:ClearFocus() end
    end)

    -- Logs UI moved to standalone LogsWindow; no local hooks here

    -- Keep info live
    f:SetScript("OnUpdate", function(_, _)
        if not f:IsShown() then return end
        updatePanRanges()
        refreshInfo()
        syncMirrorFromReplay()
        -- Initialize origin when session changes
        local s = (activeHost() and activeHost()._lastCamSnapshot) or nil
        if s and s.sessionId and DW._lastSessionSeen ~= s.sessionId then
            DW._lastSessionSeen = s.sessionId
            DW._originTarget = { x = s.tx or 0, y = s.ty or 0, z = s.tz or 0 }
            local h = activeHost()
            DW._originYaw = (h and h.GetActorYaw and h:GetActorYaw()) or 0
            DW._originZoom = (h and h.GetPortraitZoom and h:GetPortraitZoom()) or 0.65
            DW._lastDragDelta = nil
        end
    end)

    -- Let keyboard input propagate while this window is open and disable keyboard handling
    if f and f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(true) end
    if f and f.EnableKeyboard then f:EnableKeyboard(false) end
    -- Clicks anywhere in the window should release edit box focus so game keybinds work immediately
    f:EnableMouse(true)
    f:SetScript("OnMouseDown", function()
    if infoEdit and infoEdit:HasFocus() then infoEdit:ClearFocus() end
    end)
    -- Expose handles
    self.frame = f
    self.embedHost = embedHost
    self.infoEdit = infoEdit
    self.overlay = overlay

    return f
end

function DW:Show()
    local f = self:Create()
    f:Show()
    -- Create mirror if enabled
    if self._useMirror then self:EnsureMirror(); if self.mirrorFrame then self.mirrorFrame:Show() end end
    -- If a model is visible in the main ReplayFrame, try to mirror it
    local rf = ReplayFrame
    do
        local id = self:_GetReplayDisplayID()
        local h = self:_ActiveHost()
        if id and h and h.SetDisplayInfo then
            h:ClearModel(); h:SetDisplayInfo(id)
            if self._autoRefit ~= false then
                if h.FrameFullBodyFront then h:FrameFullBodyFront(0.12) end
                if h.FaceCamera then h:FaceCamera() end
            end
            if DW._AttachLoadSync then DW:_AttachLoadSync(h) end
            if DW._SyncControlsToHost then DW:_SyncControlsToHost(h) end
        elseif self._useTargetNPC and h then
            self:PreviewTarget()
        elseif h and h.SetUnit then
            -- As a last resort, try showing current target NPC unit if available
            if h.ClearModel then pcall(h.ClearModel, h) end
            pcall(h.SetUnit, h, "target")
            if self._autoRefit ~= false and h.FrameFullBodyFront then h:FrameFullBodyFront(0.12) end
            if DW._AttachLoadSync then DW:_AttachLoadSync(h) end
            if DW._SyncControlsToHost then DW:_SyncControlsToHost(h) end
        end
    end
end

function DW:Hide()
    if self.frame then self.frame:Hide() end
    -- Hide mirror if present
    if self.mirrorFrame then self.mirrorFrame:Hide() end
end

-- Slash commands
SLASH_CLNDEBUG1 = "/clndebug"
SLASH_CLNDEBUG2 = "/clnmodel"
SlashCmdList["CLNDEBUG"] = function()
    if not DW.frame or not DW.frame:IsShown() then DW:Show() else DW:Hide() end
end
