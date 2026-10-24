---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local DEFAULT_W, DEFAULT_H = CLN.DEFAULT_FRAME_WIDTH, CLN.DEFAULT_FRAME_HEIGHT

-- Horizontal gap between the docked window and the quest objectives tracker
local DOCK_GAP = 12

-- The quest objectives tracker: ObjectiveTrackerFrame (Retail, modern Classic
-- clients), WatchFrame (Wrath/Cata Classic) or QuestWatchFrame (Vanilla/TBC).
local function GetObjectiveTracker()
    return _G.ObjectiveTrackerFrame or _G.WatchFrame or _G.QuestWatchFrame
end

-- ============================================================================
-- DOCKING (window pinned to the left of the objectives tracker)
-- ============================================================================
-- profile.frameAnchor: "objectives" = docked, "free" = saved framePos.
-- Moving the window (drag, nudge, layout apply) switches it to "free".

function ReplayFrame:IsDockedToObjectives()
    return CLN.db.profile.frameAnchor == "objectives"
end

-- Stop docking. Re-anchors the window to UIParent at its current screen
-- position so it doesn't jump. Not for use mid-drag (see the StartMoving hook).
function ReplayFrame:UndockFrame()
    if not self:IsDockedToObjectives() then return end
    CLN.db.profile.frameAnchor = "free"
    local f = self.DisplayFrame
    if not f then return end
    local left, top = f:GetLeft(), f:GetTop()
    if left and top then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
end

-- Dock (or re-dock) the window next to the objectives tracker.
function ReplayFrame:DockToObjectives()
    CLN.db.profile.frameAnchor = "objectives"
    if self.DisplayFrame then self:LoadFramePosition() end
    if self.PersistToActiveLayout then self:PersistToActiveLayout() end
end

-- ============================================================================
-- POSITION AND STATE MANAGEMENT
-- ============================================================================

-- Save the current frame position and size to the database
function ReplayFrame:SaveFramePosition()
    -- Use GetPoint() to capture the exact anchor values WoW set via SetPoint.
    -- Avoids the GetCenter()+scale-math round-trip, which accumulated floating-
    -- point rounding error on each reload cycle (visible as slow position drift,
    -- especially on Classic/Anniversary where UIParent scale differs from Retail).
    -- UpdateParent() always ensures the frame is parented to UIParent before
    -- any save, so GetPoint() values are already UIParent-relative.
    local point, relativeTo, relativePoint, xOfs, yOfs = self.DisplayFrame:GetPoint()
    if not (point and xOfs and yOfs) then
        -- GetPoint failed (frame not yet anchored) — skip to avoid corrupting saved pos
        return
    end
    -- While docked the anchor is relative to the objectives tracker, not a
    -- screen position: keep the last free position and only persist the size.
    if relativeTo == nil or relativeTo == UIParent then
        CLN.db.profile.framePos = {
            point = point,
            relativePoint = relativePoint,
            xOfs = xOfs,
            yOfs = yOfs,
        }
    end
    -- Persist current size — but never save a collapsed height
    if self.DisplayFrame and self.DisplayFrame.GetSize then
        local w, h = self.DisplayFrame:GetSize()
        local isCollapsed = (self.CollapseButton and self.CollapseButton._collapsed)
            or self._combatAutoCollapsed
            or self._animatingCollapse
        if isCollapsed then
            -- Use the pre-collapse height (or profile default) instead of the tiny current height
            h = self._preCollapseHeight
                or (CLN.db.profile.frameSize and CLN.db.profile.frameSize.height)
                or DEFAULT_H
        end
        CLN.db.profile.frameSize = { width = math.floor(w + 0.5), height = math.floor(h + 0.5) }
    end
    -- Keep the active Edit Mode layout in step: it is re-applied on every
    -- login (Retail), so a move saved only here would be undone there.
    if self.PersistToActiveLayout then self:PersistToActiveLayout() end
end

-- Load saved frame position and size from the database
function ReplayFrame:LoadFramePosition()
    local pos = CLN.db.profile.framePos
    -- Apply saved size first (if any), clamping corrupted collapsed heights
    local size = CLN.db.profile.frameSize
    if size and size.width and size.height and self.DisplayFrame and self.DisplayFrame.SetSize then
        local h = size.height
        if h < 80 then h = DEFAULT_H end
        self.DisplayFrame:SetSize(size.width, h)
    end
    local tracker = self:IsDockedToObjectives() and GetObjectiveTracker()
    if tracker then
        self.DisplayFrame:ClearAllPoints()
        self.DisplayFrame:SetPoint("TOPRIGHT", tracker, "TOPLEFT", -DOCK_GAP, 0)
    elseif (pos) then
        self.DisplayFrame:ClearAllPoints()
        self.DisplayFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        self.DisplayFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -500, -200)
    end
end

-- Reset frame position and size to defaults
function ReplayFrame:ResetFramePosition()
    CLN.db.profile.framePos = {
        point = "CENTER",
        relativePoint = "CENTER",
        xOfs = 500,
        yOfs = 0
    }
    CLN.db.profile.frameAnchor = "objectives"
    -- Reset saved size and per-mode widths to defaults
    CLN.db.profile.frameSize = { width = DEFAULT_W, height = DEFAULT_H }
    CLN.db.profile.compactWidth = nil
    CLN.db.profile.expandedWidth = nil
    -- Reset model frame to docked mode
    CLN.db.profile.modelFramePos = nil
    if (ReplayFrame.DisplayFrame) then
        ReplayFrame:LoadFramePosition()
    end
    -- Re-dock model container above DisplayFrame
    if ReplayFrame.DisplayFrame and ReplayFrame.LayoutModelArea then
        ReplayFrame:LayoutModelArea(ReplayFrame.DisplayFrame)
    end
    if ReplayFrame.PersistToActiveLayout then ReplayFrame:PersistToActiveLayout() end
end

-- The model portrait is always docked to the conversation window, so it has
-- no position of its own to save (its height is saved as npcModelFrameHeight).
function ReplayFrame:SaveModelPosition()
    CLN.db.profile.modelFramePos = nil
end

-- Always docked: the model portrait never floats independently.
function ReplayFrame:IsModelUndocked()
    return false
end

-- Which side of the conversation window the portrait docks to.
---@return "above"|"below"|"left"|"right"
function ReplayFrame:GetPortraitPosition()
    local pos = CLN.db and CLN.db.profile and CLN.db.profile.portraitPosition
    if pos == "below" or pos == "left" or pos == "right" then return pos end
    return "above"
end

-- Edge the Edit Mode resize grip drags: the one facing away from the window.
-- nil for left/right, whose size follows the conversation window.
function ReplayFrame:GetPortraitResizeEdge()
    local pos = self:GetPortraitPosition()
    if pos == "above" then return "TOP" end
    if pos == "below" then return "BOTTOM" end
    return nil
end

-- Minimum portrait height for above/below: close-up styles need a squarer box
-- than a wide strip. A fraction of the window width (style.portraitMinAspect); 0 = none.
function ReplayFrame:GetPortraitMinHeight()
    local s = self.GetFrameStyle and self:GetFrameStyle()
    local ratio = s and s.portraitMinAspect
    local frame, container = self.DisplayFrame, self.ModelContainer
    if not (ratio and frame) then return 0 end
    -- The container lives under UIParent and doesn't share the window's
    -- SetScale, so convert the window width into the container's units.
    local width = frame:GetWidth() or 0
    if container then
        width = width * (frame:GetEffectiveScale() or 1) / (container:GetEffectiveScale() or 1)
    end
    -- Capped like Edit Mode's portrait resize bounds
    return math.min(500, math.floor(width * ratio + 0.5))
end

-- Apply a portrait height without re-docking (Edit Panel live previews, where
-- the profile isn't saved yet). Above/below respect the style's minimum;
-- left/right follow the window's height and are left alone.
function ReplayFrame:SetPortraitStripHeight(h)
    local container = self.ModelContainer
    if not (container and h) then return end
    if self:GetPortraitResizeEdge() then
        container:SetHeight(math.max(h, self:GetPortraitMinHeight()))
    end
end

-- Dock the portrait container to the conversation window on the chosen side.
-- Above/below span the window's width at the saved portrait height; left/right
-- match the window's height, with a width of 80% of it (re-run on resize).
function ReplayFrame:AnchorModelContainer(container, frame)
    container = container or self.ModelContainer
    frame = frame or self.DisplayFrame
    if not (container and frame) then return end
    -- The profile value is authoritative (Edit Mode resize saves only that); keep the cache in step
    local h = (CLN.db and CLN.db.profile and CLN.db.profile.npcModelFrameHeight) or self.npcModelFrameHeight or 140
    self.npcModelFrameHeight = h
    local pos = self:GetPortraitPosition()
    -- Above/below: the style may need a taller box than the saved height
    -- (not saved back, so other styles keep the user's Portrait Height)
    local stripH = math.max(h, self:GetPortraitMinHeight())
    container:ClearAllPoints()
    if pos == "below" then
        container:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2)
        container:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -2)
        container:SetHeight(stripH)
    elseif pos == "left" or pos == "right" then
        local fh = frame:GetHeight() or h
        if fh <= 0 then fh = h end
        local w = math.floor(math.max(90, math.min(280, fh * 0.8)) + 0.5)
        if pos == "left" then
            container:SetPoint("TOPRIGHT", frame, "TOPLEFT", -2, 0)
            container:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", -2, 0)
        else
            container:SetPoint("TOPLEFT", frame, "TOPRIGHT", 2, 0)
            container:SetPoint("BOTTOMLEFT", frame, "BOTTOMRIGHT", 2, 0)
        end
        container:SetWidth(w)
    else
        container:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
        container:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
        container:SetHeight(stripH)
    end
end

-- Reparent while preserving the on-screen position regardless of scale/parent
function ReplayFrame:ReparentPreservingScreenPosition(newParent)
    if not self.DisplayFrame then return end
    local f = self.DisplayFrame
    local cx, cy = f:GetCenter()
    if not cx or not cy then
        f:SetParent(newParent)
        return
    end
    local s = f:GetEffectiveScale() or 1
    local absX, absY = cx * s, cy * s
    f:SetParent(newParent)
    local s2 = f:GetEffectiveScale() or 1
    local relX, relY = absX / s2, absY / s2
    f:ClearAllPoints()
    
    -- Re-anchor to keep the same screen position after reparenting
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", relX, relY)
end

-- Save minimized button position to database
function ReplayFrame:SaveMinButtonPosition()
    if not self.MinButton then return end
    local point, relativeTo, relativePoint, xOfs, yOfs = self.MinButton:GetPoint()
    CLN.db.profile.minBtnPos = {
        point = point,
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs,
    }
end

-- Load minimized button position from database
function ReplayFrame:LoadMinButtonPosition()
    if not self.MinButton then return end
    local pos = CLN.db.profile.minBtnPos
    self.MinButton:ClearAllPoints()
    if pos then
        self.MinButton:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
    else
        self.MinButton:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -420, -200)
    end
end

-- Update parent frame based on current state
function ReplayFrame:UpdateParent()
    if not self.DisplayFrame then return end
    if self._editMode or self._blizzardEditMode or self._isDragging then return end
    -- Always parent to UIParent to avoid cascading hide when dialog frames close
    if self.DisplayFrame:GetParent() ~= UIParent then
        self:ReparentPreservingScreenPosition(UIParent)
    end
end

-- Check if compact mode is enabled
function ReplayFrame:IsCompactModeEnabled()
    return CLN and CLN.db and CLN.db.profile and CLN.db.profile.compactMode
end

-- Apply compact mode layout changes
function ReplayFrame:ApplyCompactMode()
    if not ReplayFrame.DisplayFrame or not ReplayFrame.ContentFrame then return end
    local frame = self.DisplayFrame
    local height = frame:GetHeight()
    if ReplayFrame:IsCompactModeEnabled() then
        -- Shrink to normal width and hide model
        -- If we have a remembered compact width, use it; else default normalWidth
        local w = (CLN.db and CLN.db.profile and CLN.db.profile.compactWidth) or self.normalWidth
        frame:SetWidth(w)
        if self.NpcModelFrame then
            self.NpcModelFrame:Hide()
        end
        self.ContentFrame:ClearAllPoints()
        self.ContentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
        self.ContentFrame:SetSize(frame:GetWidth() - 10, height - 5)
    else
        -- Allow model to expand the width as needed later
        local w = (CLN.db and CLN.db.profile and CLN.db.profile.expandedWidth) or self.expandedWidth
        frame:SetWidth(w)
        if self.NpcModelFrame then
            -- visibility controlled by current NPC state
        end
        self.ContentFrame:ClearAllPoints()
        self.ContentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
        self.ContentFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
        self.ContentFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 5, 5)
        self:CheckAndShowModel()
    end
    -- Persist updated size after mode change
    self:SaveFramePosition()
end

-- Save size for the current layout mode
function ReplayFrame:SaveSizeForActiveLayout()
    if not self.DisplayFrame then return end
    -- Skip saving during collapse to avoid persisting collapsed dimensions
    if self._combatAutoCollapsed or self._animatingCollapse then return end
    local w, h = self.DisplayFrame:GetSize()
    if self:IsCompactModeEnabled() then
        CLN.db.profile.compactWidth = w
    else
        CLN.db.profile.expandedWidth = w
    end
end

-- ============================================================================
-- STATE CHECKS
-- ============================================================================

function ReplayFrame:IsVoiceoverCurrenltyPlaying()
    if CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.IsEffectivelyPlaying then
        return CLN.VoiceoverPlayer:IsEffectivelyPlaying()
    end
    return CLN.VoiceoverPlayer.currentlyPlaying and CLN.VoiceoverPlayer.currentlyPlaying:isPlaying()
end

function ReplayFrame:IsShowReplayFrameToggleIsEnabled()
    return CLN.db.profile.showReplayFrame
end

function ReplayFrame:IsDisplayFrameCurrentlyShown()
    return self.DisplayFrame and self.DisplayFrame:IsShown()
end

function ReplayFrame:IsQuestQueueEmpty()
    return CLN.questsQueue and #CLN.questsQueue == 0
end

function ReplayFrame:IsDisplayFrameHideNeeded()
    return ((not self:IsShowReplayFrameToggleIsEnabled())
        or (not CLN.VoiceoverPlayer.currentlyPlaying)
        or ((not self:IsVoiceoverCurrenltyPlaying()) and self:IsQuestQueueEmpty() and self:IsDisplayFrameCurrentlyShown()))
end

function ReplayFrame:IsDialogueUIFrameShow()
    return CLN.isDUIAddonLoaded and _G["DUIQuestFrame"] and _G["DUIQuestFrame"]:IsShown()
end
