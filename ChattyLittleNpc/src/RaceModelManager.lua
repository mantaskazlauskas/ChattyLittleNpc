-- RaceModelManager.lua - Developer window for labeling unknown NPC race models
-- Pages through model file IDs that NpcRaceLookup could not resolve, renders
-- the NPC so it can be identified visually, and saves a hand-entered race.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class RaceModelManager
local RaceModelManager = {}
CLN.RaceModelManager = RaceModelManager

RaceModelManager.list = {}
RaceModelManager.index = 1

local function createFrame()
    local f = CreateFrame("Frame", "CLN_RaceModelManager", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(380, 560)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true) -- opens from the settings window, which shares this strata
    f:Hide()
    tinsert(UISpecialFrames, "CLN_RaceModelManager") -- close with Escape

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -5)
    f.title:SetText("Unknown Race Models")

    -- Header: model file ID
    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.header:SetPoint("TOP", 0, -36)

    f.counter = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.counter:SetPoint("TOPRIGHT", -14, -32)

    f.details = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.details:SetPoint("TOP", f.header, "BOTTOM", 0, -6)
    f.details:SetWidth(350)

    -- Model view (drag to rotate, mouse wheel to zoom)
    -- Container sits above the template's inset so its background stays visible
    local modelBg = CreateFrame("Frame", nil, f)
    modelBg:SetPoint("TOPLEFT", 14, -84)
    modelBg:SetPoint("TOPRIGHT", -14, -84)
    modelBg:SetHeight(330)
    modelBg:SetFrameLevel(f:GetFrameLevel() + 5)
    local bgTex = modelBg:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    bgTex:SetColorTexture(0, 0, 0, 0.5)

    local model = CreateFrame("PlayerModel", nil, modelBg)
    model:SetAllPoints(modelBg)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model.facing = 0
    model.zoom = 0
    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self.dragX = GetCursorPosition() end
    end)
    model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    model:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x = GetCursorPosition()
        self.facing = self.facing + (x - self.dragX) * 0.02
        self.dragX = x
        self:SetFacing(self.facing)
    end)
    model:SetScript("OnMouseWheel", function(self, delta)
        self.zoom = math.max(0, math.min(0.9, self.zoom + delta * 0.1))
        self:SetPortraitZoom(self.zoom)
    end)
    f.model = model

    f.noModel = modelBg:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    f.noModel:SetPoint("CENTER", modelBg)
    f.noModel:SetText("No model to display")

    -- Race input
    f.raceLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.raceLabel:SetPoint("TOPLEFT", modelBg, "BOTTOMLEFT", 2, -14)
    f.raceLabel:SetText("Race:")

    f.raceInput = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.raceInput:SetSize(270, 22)
    f.raceInput:SetPoint("LEFT", f.raceLabel, "RIGHT", 12, 0)
    f.raceInput:SetAutoFocus(false)
    f.raceInput:SetScript("OnEnterPressed", function() RaceModelManager:SaveCurrent(true) end)
    f.raceInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Buttons
    local function button(text, width, onClick)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(width, 24)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end

    f.prevButton = button("< Prev", 74, function() RaceModelManager:Step(-1) end)
    f.prevButton:SetPoint("TOPLEFT", f.raceLabel, "BOTTOMLEFT", -2, -16)

    f.saveButton = button("Save", 80, function() RaceModelManager:SaveCurrent(true) end)
    f.saveButton:SetPoint("LEFT", f.prevButton, "RIGHT", 8, 0)

    f.ignoreButton = button("Not a race", 100, function() RaceModelManager:ToggleIgnored() end)
    f.ignoreButton:SetPoint("LEFT", f.saveButton, "RIGHT", 8, 0)

    f.nextButton = button("Next >", 74, function() RaceModelManager:Step(1) end)
    f.nextButton:SetPoint("LEFT", f.ignoreButton, "RIGHT", 8, 0)

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOM", 0, 12)
    f.hint:SetText("Drag model to rotate, scroll to zoom. Enter saves and moves on.")

    return f
end

function RaceModelManager:Refresh()
    local f = self.frame
    local item = self.list[self.index]

    f.prevButton:SetEnabled(self.index > 1)
    f.nextButton:SetEnabled(self.index < #self.list)

    if not item then
        f.header:SetText("No unknown models")
        f.details:SetText("Talk to NPCs with NPC text logging enabled to collect some.")
        f.counter:SetText("")
        f.raceInput:SetText("")
        f.raceInput:Disable()
        f.saveButton:Disable()
        f.ignoreButton:Disable()
        f.model:ClearModel()
        f.noModel:Show()
        return
    end

    local e = item.entry
    local labeled = 0
    for _, it in ipairs(self.list) do
        if (it.entry.race and it.entry.race ~= "") or it.entry.ignored then labeled = labeled + 1 end
    end

    f.header:SetText("Model ID: " .. item.fileId)
    f.counter:SetText(self.index .. " / " .. #self.list .. "  (" .. labeled .. " done)")
    f.details:SetText(string.format("%s (NPC %s)  ·  Display %s  ·  %s  ·  seen %dx%s",
        e.name or "?", tostring(e.npcId or "?"), tostring(e.displayId or "?"),
        e.creatureType or "?", e.count or 0,
        e.ignored and "  ·  |cffff8080not a race|r" or ""))

    f.raceInput:Enable()
    f.saveButton:Enable()
    f.ignoreButton:Enable()
    f.raceInput:SetText(e.race or "")
    f.ignoreButton:SetText(e.ignored and "Restore" or "Not a race")

    local model = f.model
    model:ClearModel()
    model.facing, model.zoom = 0, 0
    local renderPath
    if e.displayId then
        model:SetDisplayInfo(e.displayId)
        renderPath = "SetDisplayInfo(" .. e.displayId .. ")"
    elseif e.npcId and model.SetCreature and pcall(model.SetCreature, model, e.npcId) then
        -- No display ID captured: render by creature ID, textured if the client has it cached
        renderPath = "SetCreature(" .. e.npcId .. ")"
    else
        model:SetModel(item.fileId) -- last resort: bare model file, untextured
        renderPath = "SetModel(" .. item.fileId .. ") - untextured"
    end
    if CLN.Logger then
        CLN.Logger:debug("RaceModelManager render: " .. renderPath, false, CLN.Utils.LogCategories.ui)
    end
    model:SetPortraitZoom(0)
    model:SetFacing(0)
    f.noModel:Hide()
end

function RaceModelManager:Step(delta)
    self.index = math.max(1, math.min(#self.list, self.index + delta))
    self:Refresh()
end

--- Save the typed race for the current model. An empty box clears the label.
---@param advance boolean Move to the next entry after saving
function RaceModelManager:SaveCurrent(advance)
    local item = self.list[self.index]
    if not item then return end
    local race = strtrim(self.frame.raceInput:GetText() or "")
    item.entry.race = race
    if race ~= "" then item.entry.ignored = nil end
    self.frame.raceInput:ClearFocus()
    if CLN.Logger then
        CLN.Logger:info("Race model " .. item.fileId .. " = " .. (race ~= "" and race or "(cleared)"), true, CLN.Utils.LogCategories.ui)
    end
    if advance and self.index < #self.list then
        self:Step(1)
    else
        self:Refresh()
    end
end

function RaceModelManager:ToggleIgnored()
    local item = self.list[self.index]
    if not item then return end
    item.entry.ignored = (not item.entry.ignored) or nil
    if item.entry.ignored then item.entry.race = "" end
    if item.entry.ignored and self.index < #self.list then
        self:Step(1)
    else
        self:Refresh()
    end
end

function RaceModelManager:Show()
    self.frame = self.frame or createFrame()
    self.list = CLN.NpcRaceLookup and CLN.NpcRaceLookup:GetUnknownList() or {}

    -- Start at the first entry that still needs a label
    self.index = 1
    for i, item in ipairs(self.list) do
        if (not item.entry.race or item.entry.race == "") and not item.entry.ignored then
            self.index = i
            break
        end
    end

    self.frame:Show()
    self.frame:Raise()
    self:Refresh()
end

function RaceModelManager:Hide()
    if self.frame then self.frame:Hide() end
end

function RaceModelManager:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end
