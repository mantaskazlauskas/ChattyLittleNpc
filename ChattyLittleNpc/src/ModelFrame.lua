---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- Creates a full-width container for the NPC model and a fixed-size PlayerModel inside it.
-- Keeps the model from resizing with the frame; only the container spans the width.
function ReplayFrame:CreateModelUI()
    -- Prevent duplicate creation
    if self.ModelContainer or self.NpcModelFrame then return end
    -- Defaults if not already set
    self.npcModelFrameWidth = self.npcModelFrameWidth or 220
    -- Avoid compounding height increases across multiple calls
    self.npcModelFrameHeight = self.npcModelFrameHeight or math.floor(140 * 1.15)

    -- Container spans the width; used as a row above the queue
    local modelContainer = CreateFrame("Frame", "ChattyLittleNpcModelContainer", self.DisplayFrame)
    modelContainer:SetPoint("TOPLEFT", self.DisplayFrame, "TOPLEFT", 5, -8)
    modelContainer:SetPoint("TOPRIGHT", self.DisplayFrame, "TOPRIGHT", -5, -8)
    modelContainer:SetHeight(self.npcModelFrameHeight)
    modelContainer:Hide()
    self.ModelContainer = modelContainer

    -- Fixed-size model anchored left within the container
    local modelFrame = CreateFrame("PlayerModel", "ChattyLittleNpcModelFrame", modelContainer)
    modelFrame:SetSize(self.npcModelFrameWidth, self.npcModelFrameHeight)
    modelFrame:SetPoint("TOPLEFT", modelContainer, "TOPLEFT", 0, 0)
    modelFrame:Hide()
    self.NpcModelFrame = modelFrame
end

-- Position the full-width model container and fixed-size model; show/hide based on state
function ReplayFrame:LayoutModelArea(frame)
    local compact = CLN.db and CLN.db.profile and CLN.db.profile.compactMode
    local hasModel = self._hasValidModel and not compact

    if self.ModelContainer then
        self.ModelContainer:ClearAllPoints()
        self.ModelContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -8)
        self.ModelContainer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -8)
        self.ModelContainer:SetHeight(self.npcModelFrameHeight or 140)
        if hasModel then self.ModelContainer:Show() else self.ModelContainer:Hide() end
    end

    if self.NpcModelFrame then
        self.NpcModelFrame:ClearAllPoints()
        self.NpcModelFrame:SetSize(self.npcModelFrameWidth or 220, self.npcModelFrameHeight or 140)
        self.NpcModelFrame:SetPoint("TOPLEFT", (self.ModelContainer or frame), "TOPLEFT", 0, 0)
        if hasModel then self.NpcModelFrame:Show() else self.NpcModelFrame:Hide() end
    end
end

-- Build/update the model with npcId and handle container visibility
function ReplayFrame:UpdateNpcModelDisplay(npcId)
    if (not self.NpcModelFrame) then return end
    -- Defensive: ensure we only have one PlayerModel child
    if self.ModelContainer and self.ModelContainer.GetChildren then
        local count = 0
        local children = { self.ModelContainer:GetChildren() }
        for _, child in ipairs(children) do
            if child and child.GetObjectType and child:GetObjectType() == "PlayerModel" then
                count = count + 1
            end
        end
        if count > 1 then
            -- hide any extras just in case
            for _, child in ipairs(children) do
                if child ~= self.NpcModelFrame and child and child.GetObjectType and child:GetObjectType() == "PlayerModel" then
                    child:Hide()
                end
            end
        end
    end
    if self:IsCompactModeEnabled() then
        if self.ModelContainer then self.ModelContainer:Hide() end
        self.NpcModelFrame:Hide()
        self:ContractForNpcModel()
        return
    end

    local currentlyPlaying = CLN.VoiceoverPlayer.currentlyPlaying
    if (not (self:IsVoiceoverCurrenltyPlaying() and currentlyPlaying.npcId == npcId)) then
        if self.ModelContainer then self.ModelContainer:Hide() end
        self.NpcModelFrame:Hide()
        self:ContractForNpcModel()
        return
    end

    local displayID = NpcDisplayIdDB[npcId]
    if (displayID) then
        self.NpcModelFrame:ClearModel()
        self.NpcModelFrame:SetDisplayInfo(displayID)
        self.NpcModelFrame:SetPortraitZoom(0.75)
        self.NpcModelFrame:SetRotation(0.3)
        self._hasValidModel = true
        if self.ModelContainer then self.ModelContainer:Show() end
        self.NpcModelFrame:Show()
    else
        self.NpcModelFrame:ClearModel()
        self.NpcModelFrame:Hide()
        if self.ModelContainer then self.ModelContainer:Hide() end
        self._hasValidModel = false
    end
    if self.Relayout then self:Relayout() end
end

function ReplayFrame:CheckAndShowModel()
    local currentlyPlaying = CLN.VoiceoverPlayer.currentlyPlaying
    if (not self:IsCompactModeEnabled() and self:IsVoiceoverCurrenltyPlaying() and currentlyPlaying.npcId) then
        self:UpdateNpcModelDisplay(currentlyPlaying.npcId)
    else
        if (self.NpcModelFrame) then self.NpcModelFrame:Hide() end
        if (self.ModelContainer) then self.ModelContainer:Hide() end
    end
end

function ReplayFrame:ExpandForNpcModel() end
function ReplayFrame:ContractForNpcModel() end
