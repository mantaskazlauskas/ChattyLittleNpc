local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

function ChattyLittleNpc:SaveFramePosition()
    local point, relativeTo, relativePoint, xOfs, yOfs = self.displayFrame:GetPoint()
    self.db.profile.framePos = {
        point = point,
        relativeTo = relativeTo and relativeTo:GetName() or nil,
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs
    }
end

function ChattyLittleNpc:LoadFramePosition()
    local pos = self.db.profile.framePos
    self.displayFrame:ClearAllPoints()
    self.displayFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
end

function ChattyLittleNpc:ResetFramePosition()
    self.db.profile.framePos = {
        point = "CENTER",
        relativeTo = nil,
        relativePoint = "CENTER",
        xOfs = 500,
        yOfs = 0
    }
    if self.displayFrame then
        self:LoadFramePosition()
    end
end

function ChattyLittleNpc:ShowDisplayFrame(questTitle)
    if not self.displayFrame then
        self.displayFrame = CreateFrame("Frame", "ChattyLittleNpcDisplayFrame", UIParent)
        self.displayFrame:SetSize(300, 50)
        self:LoadFramePosition()

        -- Enable dragging
        self.displayFrame:SetMovable(true)
        self.displayFrame:EnableMouse(true)
        self.displayFrame:RegisterForDrag("LeftButton")
        self.displayFrame:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
        self.displayFrame:SetScript("OnDragStop", function(frame)
            frame:StopMovingOrSizing()
            self:SaveFramePosition()
        end)
   
        self.stopButton = CreateFrame("Button", nil, self.displayFrame)
        self.stopButton:SetSize(12, 12)
        self.stopButton:SetPoint("LEFT", 5, 0)
        self.stopButton:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        self.stopButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        self.stopButton:SetScript("OnClick", function()
            self:StopCurrentSound()
            self.displayFrame:Hide()
        end)

        self.replayButton = CreateFrame("Button", nil, self.displayFrame)
        self.replayButton:SetSize(12, 12)
        self.replayButton:SetPoint("LEFT", self.stopButton, "RIGHT", 5, 0)
        self.replayButton:SetNormalTexture("Interface\\AddOns\\ChattyLittleNpc\\Textures\\replay_button_red.tga")
        self.replayButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        self.replayButton:SetScript("OnClick", function()
            if ChattyLittleNpc.currentQuestId and ChattyLittleNpc.currentPhase then
                ChattyLittleNpc:PlayQuestSound(ChattyLittleNpc.currentQuestId, ChattyLittleNpc.currentPhase)
            end
        end)

        self.displayText = self.displayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        self.displayText:SetPoint("LEFT", self.replayButton, "RIGHT", 10, 0)
        self.displayText:SetJustifyH("LEFT")
        
        local font, height, flags = self.displayText:GetFont()
        self.displayText:SetFont(font, height + 2, flags)
    else
        self:LoadFramePosition()
    end

    self.displayText:SetText(questTitle)
    self.displayFrame:Show()
end
