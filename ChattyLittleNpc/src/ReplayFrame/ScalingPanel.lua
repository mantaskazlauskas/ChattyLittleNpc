---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- ============================================================================
-- BLIZZARD-STYLE SCALING PANEL FOR EDIT MODE
-- ============================================================================

function ReplayFrame:CreateScalingPanel()
    if self._scalingPanel then return self._scalingPanel end
    
    local panel = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(280, 200)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetFrameStrata("DIALOG")
    panel:Hide()
    
    -- Title
    panel.title = panel:CreateFontString(nil, "OVERLAY")
    panel.title:SetFontObject("GameFontHighlightLarge")
    panel.title:SetPoint("TOP", 0, -8)
    panel.title:SetText("Frame Settings")
    
    -- Description text
    panel.desc = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    panel.desc:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", -60, -8)
    panel.desc:SetPoint("TOPRIGHT", panel.title, "BOTTOMRIGHT", 60, -8)
    panel.desc:SetJustifyH("CENTER")
    panel.desc:SetText("Adjust frame scale, text size, and dimensions. Changes apply immediately.")
    panel.desc:SetTextColor(0.8, 0.8, 0.8)
    
    local yOffset = -60
    local spacing = 25
    
    -- Frame Scale
    panel.scaleLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.scaleLabel:SetPoint("TOPLEFT", 15, yOffset)
    panel.scaleLabel:SetText("Frame Scale:")
    
    panel.scaleSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    panel.scaleSlider:SetPoint("LEFT", panel.scaleLabel, "RIGHT", 10, 0)
    panel.scaleSlider:SetSize(120, 15)
    panel.scaleSlider:SetMinMaxValues(0.5, 2.0)
    panel.scaleSlider:SetValueStep(0.05)
    panel.scaleSlider:SetObeyStepOnDrag(true)
    
    panel.scaleValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.scaleValue:SetPoint("LEFT", panel.scaleSlider, "RIGHT", 5, 0)
    
    -- Width
    yOffset = yOffset - spacing
    panel.widthLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.widthLabel:SetPoint("TOPLEFT", 15, yOffset)
    panel.widthLabel:SetText("Width:")
    
    panel.widthEditBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.widthEditBox:SetPoint("LEFT", panel.widthLabel, "RIGHT", 10, 0)
    panel.widthEditBox:SetSize(60, 20)
    panel.widthEditBox:SetAutoFocus(false)
    panel.widthEditBox:SetNumeric(true)
    
    -- Height
    yOffset = yOffset - spacing
    panel.heightLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.heightLabel:SetPoint("TOPLEFT", 15, yOffset)
    panel.heightLabel:SetText("Height:")
    
    panel.heightEditBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.heightEditBox:SetPoint("LEFT", panel.heightLabel, "RIGHT", 10, 0)
    panel.heightEditBox:SetSize(60, 20)
    panel.heightEditBox:SetAutoFocus(false)
    panel.heightEditBox:SetNumeric(true)
    
    -- Model Frame Height
    yOffset = yOffset - spacing
    panel.modelHeightLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.modelHeightLabel:SetPoint("TOPLEFT", 15, yOffset)
    panel.modelHeightLabel:SetText("Model Height:")
    
    panel.modelHeightEditBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    panel.modelHeightEditBox:SetPoint("LEFT", panel.modelHeightLabel, "RIGHT", 10, 0)
    panel.modelHeightEditBox:SetSize(60, 20)
    panel.modelHeightEditBox:SetAutoFocus(false)
    panel.modelHeightEditBox:SetNumeric(true)
    
    -- Text Scale (separate from frame scale for fine control)
    yOffset = yOffset - spacing
    panel.textScaleLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    panel.textScaleLabel:SetPoint("TOPLEFT", 15, yOffset)
    panel.textScaleLabel:SetText("Text Scale:")
    
    panel.textScaleSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    panel.textScaleSlider:SetPoint("LEFT", panel.textScaleLabel, "RIGHT", 10, 0)
    panel.textScaleSlider:SetSize(120, 15)
    panel.textScaleSlider:SetMinMaxValues(0.75, 1.5)
    panel.textScaleSlider:SetValueStep(0.05)
    panel.textScaleSlider:SetObeyStepOnDrag(true)
    
    panel.textScaleValue = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.textScaleValue:SetPoint("LEFT", panel.textScaleSlider, "RIGHT", 5, 0)
    
    -- Buttons (Blizzard-style row)
    panel.acceptButton = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    panel.acceptButton:SetSize(90, 24)
    panel.acceptButton:SetPoint("BOTTOMRIGHT", -15, 12)
    panel.acceptButton:SetText("Accept")

    panel.cancelButton = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    panel.cancelButton:SetSize(90, 24)
    panel.cancelButton:SetPoint("RIGHT", panel.acceptButton, "LEFT", -8, 0)
    panel.cancelButton:SetText("Cancel")

    panel.revertButton = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    panel.revertButton:SetSize(110, 24)
    panel.revertButton:SetPoint("BOTTOMLEFT", 15, 12)
    panel.revertButton:SetText("Revert Changes")
    panel.revertButton:Disable()

    panel.resetButton = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    panel.resetButton:SetSize(140, 24)
    panel.resetButton:SetPoint("LEFT", panel.revertButton, "RIGHT", 8, 0)
    panel.resetButton:SetText("Defaults")
    
    -- Event handlers
    panel.scaleSlider:SetScript("OnValueChanged", function(self, value)
        panel.scaleValue:SetText(string.format("%.2f", value))
    end)
    
    panel.textScaleSlider:SetScript("OnValueChanged", function(self, value)
        panel.textScaleValue:SetText(string.format("%.2f", value))
    end)
    
    local function markDirty()
        if panel._suppressDirty then return end
        panel.revertButton:Enable()
    end
    panel.scaleSlider:HookScript("OnValueChanged", markDirty)
    panel.textScaleSlider:HookScript("OnValueChanged", markDirty)
    panel.widthEditBox:SetScript("OnTextChanged", markDirty)
    panel.heightEditBox:SetScript("OnTextChanged", markDirty)
    panel.modelHeightEditBox:SetScript("OnTextChanged", markDirty)

    panel.acceptButton:SetScript("OnClick", function()
        ReplayFrame:ApplyScalingSettings(panel)
        panel._orig = nil
        panel.revertButton:Disable()
        panel:Hide()
    end)

    panel.cancelButton:SetScript("OnClick", function()
        if panel._orig then
            panel.scaleSlider:SetValue(panel._orig.scale)
            panel.textScaleSlider:SetValue(panel._orig.textScale)
            panel.widthEditBox:SetText(tostring(panel._orig.width))
            panel.heightEditBox:SetText(tostring(panel._orig.height))
            panel.modelHeightEditBox:SetText(tostring(panel._orig.modelHeight))
            ReplayFrame:ApplyScalingSettings(panel) -- ensure visual revert
        end
        panel.revertButton:Disable()
        panel._orig = nil
        panel:Hide()
    end)

    panel.revertButton:SetScript("OnClick", function()
        if not panel._orig then return end
        panel._suppressDirty = true
        panel.scaleSlider:SetValue(panel._orig.scale)
        panel.textScaleSlider:SetValue(panel._orig.textScale)
        panel.widthEditBox:SetText(tostring(panel._orig.width))
        panel.heightEditBox:SetText(tostring(panel._orig.height))
        panel.modelHeightEditBox:SetText(tostring(panel._orig.modelHeight))
        panel._suppressDirty = nil
        ReplayFrame:ApplyScalingSettings(panel)
        panel.revertButton:Disable()
    end)

    panel.resetButton:SetScript("OnClick", function()
        panel._suppressDirty = true
        panel.scaleSlider:SetValue(1.0)
        panel.textScaleSlider:SetValue(1.0)
        panel.widthEditBox:SetText("475")
        panel.heightEditBox:SetText("165")
        panel.modelHeightEditBox:SetText("140")
        panel._suppressDirty = nil
        ReplayFrame:ApplyScalingSettings(panel)
        panel.revertButton:Enable()
    end)
    
    -- ESC to close
    panel:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:Hide()
        end
    end)
    panel:EnableKeyboard(true)
    
    self._scalingPanel = panel
    return panel
end

function ReplayFrame:ShowScalingPanel()
    local panel = self:CreateScalingPanel()
    
    -- Load current values
    local frameScale = (CLN.db.profile.frameScale or 1.0)
    local textScale = (CLN.db.profile.queueTextScale or 1.0)
    local frameSize = CLN.db.profile.frameSize or { width = 475, height = 165 }
    local modelHeight = (CLN.db.profile.npcModelFrameHeight or 140)
    
    panel.scaleSlider:SetValue(frameScale)
    panel.scaleValue:SetText(string.format("%.2f", frameScale))
    
    panel.textScaleSlider:SetValue(textScale)
    panel.textScaleValue:SetText(string.format("%.2f", textScale))
    
    panel.widthEditBox:SetText(tostring(frameSize.width or 475))
    panel.heightEditBox:SetText(tostring(frameSize.height or 165))
    panel.modelHeightEditBox:SetText(tostring(modelHeight))
    
    -- Position near the frame if possible
    if self.DisplayFrame and self.DisplayFrame:IsShown() then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", self.DisplayFrame, "TOPRIGHT", 10, 0)
    end
    
    -- Snapshot original (for Cancel/Revert) only if opening fresh or not already tracking
    if not panel._orig then
        panel._orig = {
            scale = frameScale,
            textScale = textScale,
            width = frameSize.width or 475,
            height = frameSize.height or 165,
            modelHeight = modelHeight,
        }
        panel.revertButton:Disable()
    end

    panel:Show(); panel:Raise()
    panel:Raise()
end

function ReplayFrame:ApplyScalingSettings(panel)
    if not panel then return end
    
    local frameScale = panel.scaleSlider:GetValue()
    local textScale = panel.textScaleSlider:GetValue()
    local width = tonumber(panel.widthEditBox:GetText()) or 475
    local height = tonumber(panel.heightEditBox:GetText()) or 165
    local modelHeight = tonumber(panel.modelHeightEditBox:GetText()) or 140
    
    -- Validate ranges
    frameScale = math.max(0.5, math.min(2.0, frameScale))
    textScale = math.max(0.75, math.min(1.5, textScale))
    width = math.max(200, math.min(1000, width))
    height = math.max(100, math.min(600, height))
    modelHeight = math.max(50, math.min(300, modelHeight))
    
    -- Apply settings
    CLN.db.profile.frameScale = frameScale
    CLN.db.profile.queueTextScale = textScale
    CLN.db.profile.frameSize = { width = width, height = height }
    CLN.db.profile.npcModelFrameHeight = modelHeight
    
    -- Apply immediately
    self:ApplyFrameScale()
    self:ApplyQueueTextScale()
    if self.DisplayFrame then
        self.DisplayFrame:SetSize(width, height)
    end
    
    -- Update model frame height
    if self.npcModelFrameHeight ~= modelHeight then
        self.npcModelFrameHeight = modelHeight
        if self.NpcModelFrame then
            self.NpcModelFrame:SetSize(self.npcModelFrameWidth or 150, modelHeight)
        end
        self:Relayout()
    end
    
    if CLN.Logger then
        CLN.Logger:info("Frame settings applied", false, CLN.Utils.LogCategories.ui)
    end
end

function ReplayFrame:ResetScalingSettings(panel)
    if not panel then return end
    
    -- Reset to defaults
    panel.scaleSlider:SetValue(1.0)
    panel.textScaleSlider:SetValue(1.0)
    panel.widthEditBox:SetText("475")
    panel.heightEditBox:SetText("165")
    panel.modelHeightEditBox:SetText("140")
    
    -- Apply the reset values
    self:ApplyScalingSettings(panel)
end

function ReplayFrame:ApplyFrameScale()
    local scale = CLN.db.profile.frameScale or 1.0
    if self.DisplayFrame then
        self.DisplayFrame:SetScale(scale)
    end
end
