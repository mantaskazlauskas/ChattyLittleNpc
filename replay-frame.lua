---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local ReplayFrame = {}
ChattyLittleNpc.ReplayFrame = ReplayFrame

function ReplayFrame:SaveFramePosition()
    local point, relativeTo, relativePoint, xOfs, yOfs = ReplayFrame.displayFrame:GetPoint()
    ChattyLittleNpc.db.profile.framePos = {
        point = point,
        relativeTo = relativeTo and relativeTo:GetName() or nil,
        relativePoint = relativePoint,
        xOfs = xOfs,
        yOfs = yOfs
    }
end

function ReplayFrame:LoadFramePosition()
    local pos = ChattyLittleNpc.db.profile.framePos
    ReplayFrame.displayFrame:ClearAllPoints()
    ReplayFrame.displayFrame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.xOfs, pos.yOfs)
end

function ReplayFrame:ResetFramePosition()
    ChattyLittleNpc.db.profile.framePos = {
        point = "CENTER",
        relativeTo = nil,
        relativePoint = "CENTER",
        xOfs = 500,
        yOfs = 0
    }
    if ReplayFrame.displayFrame then
        ReplayFrame:LoadFramePosition()
    end
end

function ReplayFrame:ShowDisplayFrame()
    if not ReplayFrame.displayFrame then
        ReplayFrame.displayFrame = CreateFrame("Frame", "ChattyLittleNpcDisplayFrame", UIParent)
        ReplayFrame.displayFrame:SetSize(300, 50)
        ReplayFrame:LoadFramePosition()

        -- Enable dragging
        ReplayFrame.displayFrame:SetMovable(true)
        ReplayFrame.displayFrame:EnableMouse(true)
        ReplayFrame.displayFrame:RegisterForDrag("LeftButton")
        ReplayFrame.displayFrame:SetScript("OnDragStart", function(frame) frame:StartMoving() end)
        ReplayFrame.displayFrame:SetScript("OnDragStop", function(frame)
            frame:StopMovingOrSizing()
            ReplayFrame:SaveFramePosition()
        end)

        ReplayFrame.stopButton = CreateFrame("Button", nil, ReplayFrame.displayFrame)
        ReplayFrame.stopButton:SetSize(12, 12)
        ReplayFrame.stopButton:SetPoint("LEFT", 5, 0)
        ReplayFrame.stopButton:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        ReplayFrame.stopButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        ReplayFrame.stopButton:SetScript("OnClick", function()
            ChattyLittleNpc:StopCurrentSound()
            ReplayFrame.displayFrame:Hide()
        end)

        ReplayFrame.replayButton = CreateFrame("Button", nil, ReplayFrame.displayFrame)
        ReplayFrame.replayButton:SetSize(12, 12)
        ReplayFrame.replayButton:SetPoint("LEFT", ReplayFrame.stopButton, "RIGHT", 5, 0)
        ReplayFrame.replayButton:SetNormalTexture("Interface\\AddOns\\ChattyLittleNpc\\Textures\\Play.tga")
        ReplayFrame.replayButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        ReplayFrame.replayButton:SetScript("OnClick", function()
            if ChattyLittleNpc.currentQuestId and ChattyLittleNpc.currentPhase then
                ChattyLittleNpc:PlayQuestSound(ChattyLittleNpc.currentQuestId, ChattyLittleNpc.currentPhase)
            end
        end)

        ReplayFrame.displayText = ReplayFrame.displayFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ReplayFrame.displayText:SetPoint("LEFT", ReplayFrame.replayButton, "RIGHT", 10, 0)
        ReplayFrame.displayText:SetJustifyH("LEFT")
        
        local font, height, flags = ReplayFrame.displayText:GetFont()
        ReplayFrame.displayText:SetFont(font, height + 2, flags)
    else
        ReplayFrame:LoadFramePosition()
    end

    ReplayFrame.displayText:SetText(ChattyLittleNpc.currentQuestTitle)
    ReplayFrame.displayFrame:Show()
end
