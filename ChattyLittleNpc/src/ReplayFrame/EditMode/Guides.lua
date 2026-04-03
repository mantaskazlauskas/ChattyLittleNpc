---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame
local EditMode = ReplayFrame.EditMode
local Window = EditMode.Window

local Guides = {}
EditMode.Guides = Guides

local SNAP_COLOR = { 0.3, 0.7, 1.0, 0.6 }
local DOCK_COLOR = { 0.82, 0.69, 0.35, 0.7 }
local SCREEN_CENTER_COLOR = { 0.5, 0.5, 0.5, 0.4 }

local GuidesFrame = CreateFrame("Frame", nil, UIParent)
GuidesFrame:SetFrameStrata("DIALOG")
GuidesFrame:SetFrameLevel(500)
GuidesFrame:SetAllPoints(UIParent)
GuidesFrame:EnableMouse(false)
GuidesFrame:Hide()

local linePool = {}
local activeList = {}
local activeLines = 0

local function SetLineWidth(line, width)
    if PixelUtil and PixelUtil.SetWidth then
        PixelUtil.SetWidth(line, width)
    else
        line:SetWidth(width)
    end
end

local function SetLineHeight(line, height)
    if PixelUtil and PixelUtil.SetHeight then
        PixelUtil.SetHeight(line, height)
    else
        line:SetHeight(height)
    end
end

function Guides:GetLine()
    local line = table.remove(linePool)
    if not line then
        line = GuidesFrame:CreateTexture(nil, "ARTWORK")
        line:SetTexture("Interface\\Buttons\\WHITE8X8")
        line:Hide()
    end

    activeLines = activeLines + 1
    activeList[activeLines] = line
    line:Show()
    return line
end

function Guides:ReleaseLine(line)
    if not line then
        return
    end

    line:ClearAllPoints()
    line:Hide()
    linePool[#linePool + 1] = line
end

function Guides:ReleaseAll()
    for index = activeLines, 1, -1 do
        self:ReleaseLine(activeList[index])
        activeList[index] = nil
    end
    activeLines = 0
end

function Guides:Show()
    GuidesFrame:Show()
end

function Guides:Hide()
    self:ReleaseAll()
    GuidesFrame:Hide()
end

local function ApplyColor(line, color)
    local tint = color or SNAP_COLOR
    line:SetColorTexture(tint[1], tint[2], tint[3], tint[4])
end

local function DrawHorizontal(line, y, color)
    line:ClearAllPoints()
    SetLineWidth(line, UIParent:GetWidth() or 0)
    SetLineHeight(line, 1)
    line:SetPoint("BOTTOMLEFT", GuidesFrame, "BOTTOMLEFT", 0, y)
    ApplyColor(line, color)
end

local function DrawVertical(line, x, color)
    line:ClearAllPoints()
    SetLineWidth(line, 1)
    SetLineHeight(line, UIParent:GetHeight() or 0)
    line:SetPoint("BOTTOMLEFT", GuidesFrame, "BOTTOMLEFT", x, 0)
    ApplyColor(line, color)
end

local function DrawDockStrip(line, guide)
    local left = guide.left or 0
    local right = guide.right or left
    local width = right - left
    if width < 0 then
        width = 0
    end

    line:ClearAllPoints()
    SetLineWidth(line, width)
    SetLineHeight(line, 4)
    line:SetPoint("BOTTOMLEFT", GuidesFrame, "BOTTOMLEFT", left, (guide.pos or 0) - 2)
    ApplyColor(line, guide.color or DOCK_COLOR)
end

function Guides:UpdateFromSnapResult(snapResult)
    self:ReleaseAll()

    if not (snapResult and snapResult.guides and #snapResult.guides > 0) then
        GuidesFrame:Hide()
        return
    end

    GuidesFrame:Show()

    for _, guide in ipairs(snapResult.guides) do
        local line = self:GetLine()
        if guide.type == "h" then
            DrawHorizontal(line, guide.pos or 0, guide.color or SNAP_COLOR)
        elseif guide.type == "v" then
            DrawVertical(line, guide.pos or 0, guide.color or SNAP_COLOR)
        elseif guide.type == "dock" then
            DrawDockStrip(line, guide)
        else
            self:ReleaseLine(line)
            activeList[activeLines] = nil
            activeLines = activeLines - 1
        end
    end
end

Guides.SNAP_COLOR = SNAP_COLOR
Guides.DOCK_COLOR = DOCK_COLOR
Guides.SCREEN_CENTER_COLOR = SCREEN_CENTER_COLOR
Guides.Frame = GuidesFrame

return Guides
