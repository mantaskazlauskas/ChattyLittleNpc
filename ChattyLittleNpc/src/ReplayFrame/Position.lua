---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- ============================================================================
-- POSITION AND STATE MANAGEMENT
-- ============================================================================

-- Save the current frame position and size to the database
function ReplayFrame:SaveFramePosition()
    local point, relativeTo, relativePoint, xOfs, yOfs = self.DisplayFrame:GetPoint()
    CLN.db.profile.framePos = {
        point = point,
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs
    }
    -- Persist current size as well
    if self.DisplayFrame and self.DisplayFrame.GetSize then
        local w, h = self.DisplayFrame:GetSize()
        CLN.db.profile.frameSize = { width = math.floor(w + 0.5), height = math.floor(h + 0.5) }
    end
end

-- Load saved frame position and size from the database
function ReplayFrame:LoadFramePosition()
    local pos = CLN.db.profile.framePos
    -- Apply saved size first (if any)
    local size = CLN.db.profile.frameSize
    if size and size.width and size.height and self.DisplayFrame and self.DisplayFrame.SetSize then
        self.DisplayFrame:SetSize(size.width, size.height)
    end
    if (pos) then
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
    -- Reset saved size and per-mode widths to defaults
    CLN.db.profile.frameSize = { width = 310 + 165, height = 165 }
    CLN.db.profile.compactWidth = nil
    CLN.db.profile.expandedWidth = nil
    if (ReplayFrame.DisplayFrame) then
        ReplayFrame:LoadFramePosition()
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
    if self._editMode or self._isDragging then return end
    local parent = UIParent
    if (self:IsDialogueUIFrameShow()) then
        parent = _G["DUIQuestFrame"]
    end
    self:ReparentPreservingScreenPosition(parent)
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
        self.ContentFrame:SetPoint("TOPLEFT", self.NpcModelFrame, "TOPRIGHT", 2.5, 0)
        self.ContentFrame:SetSize(frame:GetWidth() - height - 5, height - 5)
        self:CheckAndShowModel()
    end
    -- Persist updated size after mode change
    self:SaveFramePosition()
end

-- Save size for the current layout mode
function ReplayFrame:SaveSizeForActiveLayout()
    if not self.DisplayFrame then return end
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
