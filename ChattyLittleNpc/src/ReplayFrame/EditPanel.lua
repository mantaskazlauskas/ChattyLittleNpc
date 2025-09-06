---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- ============================================================================
-- BLIZZARD-STYLE EDIT PANEL FOR EDIT MODE
-- ============================================================================

function ReplayFrame:CreateEditPanel()
    if self._editPanel then return self._editPanel end

    local panel = CreateFrame("Frame", "ChattyLittleNpcEditPanel", UIParent, "BasicFrameTemplateWithInset")
    panel:SetSize(370, 360)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(f)
        f:StartMoving()
    end)
    panel:SetScript("OnDragStop", function(f)
        f:StopMovingOrSizing()
        f._userMoved = true
        if CLN and CLN.db and CLN.db.profile then
            local point, _, relativePoint, xOfs, yOfs = f:GetPoint(1)
            CLN.db.profile.editPanelPos = {
                point = point,
                relativePoint = relativePoint,
                x = xOfs,
                y = yOfs,
            }
            if CLN.Logger then
                CLN.Logger:debug("EditPanel position saved ("..tostring(point).." x="..tostring(xOfs).." y="..tostring(yOfs)..")", false, CLN.Utils.LogCategories.ui)
            end
        end
    end)
    panel:SetFrameStrata("DIALOG")
    panel:Hide()
    
    -- Title
    panel.title = panel:CreateFontString(nil, "OVERLAY")
    panel.title:SetFontObject("GameFontHighlightLarge")
    panel.title:ClearAllPoints()
    panel.title:SetPoint("TOP", 0, -14)
    panel.title:SetText("Frame Settings")
    -- Dirty asterisk (hidden until something changes)
    panel._dirtyAsterisk = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    panel._dirtyAsterisk:SetPoint("LEFT", panel.title, "RIGHT", 4, 0)
    panel._dirtyAsterisk:SetText("*")
    panel._dirtyAsterisk:SetTextColor(1.0,0.82,0.0)
    panel._dirtyAsterisk:Hide()

    -- Layout badge (shows active layout + override flag)
    panel.layoutBadge = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    panel.layoutBadge:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 8, insets = {left=2,right=2,top=2,bottom=2} })
    panel.layoutBadge:SetBackdropColor(0,0,0,0.45)
    panel.layoutBadge:SetBackdropBorderColor(0.66,0.86,0.93,0.7)
    panel.layoutBadge:SetPoint("TOP", 0, -62)
    panel.layoutBadge:SetHeight(18)
    panel.layoutBadge.text = panel.layoutBadge:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.layoutBadge.text:SetPoint("LEFT", 6, 0)
    panel.layoutBadge.text:SetPoint("RIGHT", -6, 0)
    panel.layoutBadge:Hide()
    function panel:RefreshLayoutBadge()
        if not self.layoutBadge or not ReplayFrame.EditModeIntegration then return end
        local name = ReplayFrame.EditModeIntegration:GetActiveLayoutName()
        if not name then self.layoutBadge:Hide() return end
        local bucket = CLN.db.profile.editModeLayouts and CLN.db.profile.editModeLayouts[name]
        local txt = name .. (bucket and " · overrides" or "")
        self.layoutBadge.text:SetText(txt)
        self.layoutBadge:SetWidth(self.layoutBadge.text:GetStringWidth() + 20)
        self.layoutBadge:Show()
    end
    if panel.title.SetWordWrap then panel.title:SetWordWrap(false) end

    -- Description (smaller font, constrained width to avoid overlap with close button)
    panel.desc = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    panel.desc:SetPoint("TOPLEFT", 20, -36)
    panel.desc:SetPoint("TOPRIGHT", -20, -36)
    panel.desc:SetJustifyH("CENTER")
    panel.desc:SetJustifyV("TOP")
    panel.desc:SetSpacing(1)
    -- Description text removed per request (was explanatory string about scale/text/model adjustments)
    panel.desc:SetTextColor(0.82, 0.82, 0.82)

    -- Thin divider under header/description for visual separation
    if not panel.headerDivider then
        local div = panel:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(1,1,1,0.08)
        div:SetPoint("TOPLEFT", 12, -58)
        div:SetPoint("TOPRIGHT", -12, -58)
        div:SetHeight(1)
        panel.headerDivider = div
    else
        panel.headerDivider:ClearAllPoints()
        panel.headerDivider:SetPoint("TOPLEFT", 12, -58)
        panel.headerDivider:SetPoint("TOPRIGHT", -12, -58)
    end

    local yOffset = -90  -- shifted down for layout badge
    local spacing = 32

    -- Helper: tooltip attachment
    local function attachTooltip(widget, title, text)
        if not widget then return end
        widget:HookScript("OnEnter", function()
            if not GameTooltip or not GameTooltip.SetOwner then return end
            GameTooltip:SetOwner(widget, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            if title then GameTooltip:AddLine(title, 1,1,1,true) end
            if text then GameTooltip:AddLine(text, 0.85,0.85,0.85, true) end
            GameTooltip:Show()
        end)
        widget:HookScript("OnLeave", function() if GameTooltip_Hide then GameTooltip_Hide() end end)
    end

    -- Dirty highlighting helpers
    function panel:_SetDirtyColor(fontString, dirty)
        if not fontString then return end
        if dirty then
            fontString:SetTextColor(1.0, 0.82, 0.0) -- Blizzard gold for changed values
        else
            fontString:SetTextColor(0.90, 0.90, 0.90)
        end
    end

    function panel:RefreshDirtyIndicators()
        if not self._orig then return end
        local o = self._orig
        local function diff(a,b) return a ~= nil and b ~= nil and math.abs(a-b) > 0.0001 end
        local anyDirty = false
        if self._formBuilder and self._formBuilder.rows then
            for _, row in ipairs(self._formBuilder.rows) do
                if row.type == "slider" and row.slider and row.label then
                    local cur = row.slider:GetValue()
                    local orig = o[row.origKey or row.key]
                    local isDirty = diff(cur, orig)
                    self:_SetDirtyColor(row.label, isDirty)
                    if isDirty then anyDirty = true end
                end
            end
        else
            -- Fallback (shouldn't be hit after migration)
            local curScale = self.scaleSlider and self.scaleSlider:GetValue()
            local curTextScale = self.textScaleSlider and self.textScaleSlider:GetValue()
            local curW = self.widthSlider and self.widthSlider:GetValue()
            local curH = self.heightSlider and self.heightSlider:GetValue()
            local curModel = self.modelHeightSlider and self.modelHeightSlider:GetValue()
            local function legacyDiff(a,b) return not (a and b) or math.abs(a-b) > 0.0001 end
            self:_SetDirtyColor(self.scaleLabel, legacyDiff(curScale, o.scale))
            self:_SetDirtyColor(self.textScaleLabel, legacyDiff(curTextScale, o.textScale))
            self:_SetDirtyColor(self.widthLabel, legacyDiff(curW, o.width))
            self:_SetDirtyColor(self.heightLabel, legacyDiff(curH, o.height))
            self:_SetDirtyColor(self.modelHeightLabel, legacyDiff(curModel, o.modelHeight))
            anyDirty = legacyDiff(curScale,o.scale) or legacyDiff(curTextScale,o.textScale) or legacyDiff(curW,o.width) or legacyDiff(curH,o.height) or legacyDiff(curModel,o.modelHeight)
        end
        if anyDirty then self.revertButton:Enable() else self.revertButton:Disable() end
        if panel._dirtyAsterisk then
            if anyDirty then panel._dirtyAsterisk:Show() else panel._dirtyAsterisk:Hide() end
        end
    end
    
    -- Section header helper
    local function addSectionHeader(label)
        yOffset = yOffset - 18
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", 14, yOffset)
        fs:SetText(label)
        fs:SetTextColor(0.95,0.95,0.95,0.9)
        local line = panel:CreateTexture(nil, "ARTWORK")
        line:SetColorTexture(1,1,1,0.10)
        line:SetPoint("LEFT", fs, "RIGHT", 6, -1)
        line:SetPoint("RIGHT", -14, -1)
        line:SetHeight(1)
        return fs
    end

    -- Comprehensive FormBuilder (all rows)
    addSectionHeader("Appearance")
    yOffset = yOffset - 10
    local FormBuilder = {}
    function FormBuilder.new(panelRef, opts)
        opts = opts or {}
        local self = {
            panel = panelRef,
            y = yOffset,
            rowSpacing = opts.rowSpacing or spacing,
            rows = {},
            sliderWidth = 150,
            layout = { labelX = 34, sliderGap = 15, valueGap = 6, excludeX = 14, inputGap = 4, resetRightPad = 20 },
        }
        -- Bulk tooltip applier
        function self:ApplyTooltips(map)
            if not map then return end
            for _, row in ipairs(self.rows) do
                local cfg = map[row.key]
                if cfg and row.slider and attachTooltip then
                    attachTooltip(row.slider, cfg.title, cfg.text)
                    if row.input then attachTooltip(row.input, cfg.title, cfg.text) end
                end
            end
        end
        local function makeExclude(row, key)
            if not key then return end
            local exclude = CLN.db and CLN.db.profile and CLN.db.profile.editModeExclude
            if not exclude then return end
            local cb = CreateFrame("CheckButton", nil, panelRef, "ChatConfigCheckButtonTemplate")
            cb:SetSize(14,14)
            -- Anchor relative to the label so vertical alignment matches each row
            if row.label then
                cb:SetPoint("RIGHT", row.label, "LEFT", -6, 0)
            else
                cb:SetPoint("LEFT", panelRef, "LEFT", self.layout.excludeX, 0)
            end
            if cb.Text then cb.Text:Hide() end
            cb:SetChecked(exclude[key])
            cb:SetHitRectInsets(0,0,0,0)
            cb:SetScript("OnClick", function(b)
                exclude[key] = b:GetChecked() and true or false
                if CLN.Logger then CLN.Logger:debug("FormBuilder exclude '"..key.."'="..tostring(exclude[key]), false, CLN.Utils.LogCategories.ui) end
                if ReplayFrame.EditModeIntegration then
                    local name = ReplayFrame.EditModeIntegration:GetActiveLayoutName(); if name then ReplayFrame.EditModeIntegration:ApplyLayout(name) end
                end
            end)
            if attachTooltip then attachTooltip(cb, "Exclude", "Don't persist/apply this setting per layout.") end
            row.exclude = cb
        end
        local function makeReset(row)
            local btn = CreateFrame("Button", nil, panelRef)
            btn:SetSize(16,16)
            btn:SetPoint("RIGHT", panelRef, "RIGHT", -self.layout.resetRightPad, 0)
            local tex = btn:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints(); tex:SetTexture("Interface/Buttons/UI-RefreshButton")
            btn.tex = tex
            btn:SetScript("OnClick", function()
                if not panelRef._orig then return end
                local v = panelRef._orig[row.origKey or row.key]
                if v ~= nil then row.slider:SetValue(v) end
            end)
            if attachTooltip then attachTooltip(btn, "Reset", "Restore original value.") end
            row.reset = btn
        end
        local function makeInput(row, minV, maxV)
            local eb = CreateFrame("EditBox", nil, panelRef, "InputBoxTemplate")
            eb:SetSize(46,18); eb:SetAutoFocus(false)
            eb:SetPoint("LEFT", row.value, "RIGHT", self.layout.inputGap, 0)
            eb:SetNumeric(true); eb:SetMaxLetters(5)
            eb:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
            eb:SetScript("OnEnterPressed", function(s)
                local v = tonumber(s:GetText())
                if v then v = math.max(minV, math.min(maxV, v)); row.slider:SetValue(v); s:SetText(string.format("%d", v)) end
                s:ClearFocus()
            end)
            row.slider:HookScript("OnValueChanged", function(_, v) if eb:HasFocus() then return end eb:SetText(string.format("%d", v)) end)
            row.input = eb
        end
        function self:AddSlider(def)
            if self._started then
                self.y = self.y - self.rowSpacing
            else
                self._started = true
                -- small initial gap under a section header
                self.y = self.y - 8
            end
            local label = panelRef:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("TOPLEFT", self.layout.labelX, self.y)
            label:SetText(def.label or def.key)
            local slider = CreateFrame("Slider", nil, panelRef, "OptionsSliderTemplate")
            slider:SetPoint("LEFT", label, "RIGHT", self.layout.sliderGap, 0)
            slider:SetSize(self.sliderWidth, 14)
            slider:SetMinMaxValues(def.min, def.max)
            slider:SetValueStep(def.step or 1)
            slider:SetObeyStepOnDrag(true)
            if slider.Low then slider.Low:SetText(def.showLowHigh and (def.lowText or "Low") or "") end
            if slider.High then slider.High:SetText(def.showLowHigh and (def.highText or "High") or "") end
            local valueFS = panelRef:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            valueFS:SetPoint("LEFT", slider, "RIGHT", self.layout.valueGap, 0)
            valueFS:SetJustifyH("RIGHT")
            local row = { type="slider", key=def.key, origKey=def.origKey or def.key, slider=slider, value=valueFS, label=label, format=def.valueFormat or "%d" }
            panelRef[def.key .. "Label"] = label
            panelRef[def.key .. "Slider"] = slider
            panelRef[def.key .. "Value"] = valueFS
            if def.excludeKey then makeExclude(row, def.excludeKey) end
            if def.hasInput then makeInput(row, def.min, def.max) end
            if def.reset ~= false then makeReset(row) end
            table.insert(self.rows, row)
            return row
        end
        function self:GetCurrentY() return self.y end
        return self
    end
    panel._formBuilder = FormBuilder.new(panel, { rowSpacing = spacing })
    -- Scale row
    panel._formBuilder:AddSlider{ key="scale", label="Frame Scale:", min=0.5, max=2.0, step=0.05, showLowHigh=true, valueFormat="%.2f", excludeKey="frameScale" }
    -- Dimensions section
    addSectionHeader("Dimensions")
    panel._formBuilder.y = panel._formBuilder.y - 18 -- space under section header
    local widthRow = panel._formBuilder:AddSlider{ key="width", label="Width:", min=200, max=1000, step=5, hasInput=true, excludeKey="frameSize" }
    local heightRow = panel._formBuilder:AddSlider{ key="height", label="Height:", min=100, max=600, step=5, hasInput=true } -- inherits exclude visual via width
    panel._formBuilder:AddSlider{ key="modelHeight", label="Model Height:", min=50, max=300, step=5, hasInput=true, excludeKey="npcModelFrameHeight" }
    -- Text section
    addSectionHeader("Text")
    panel._formBuilder.y = panel._formBuilder.y - 18
    panel._formBuilder:AddSlider{ key="textScale", label="Text Scale:", min=0.75, max=1.5, step=0.05, showLowHigh=true, valueFormat="%.2f", excludeKey="queueTextScale" }
    yOffset = panel._formBuilder:GetCurrentY()
    
    -- Buttons (Blizzard-style row)
    panel.acceptButton = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    panel.acceptButton:SetSize(92, 24)
    panel.acceptButton:SetPoint("BOTTOMRIGHT", -18, 48)
    panel.acceptButton:SetText("Accept")

    panel.cancelButton = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    panel.cancelButton:SetSize(92, 24)
    panel.cancelButton:SetPoint("RIGHT", panel.acceptButton, "LEFT", -8, 0)
    panel.cancelButton:SetText("Cancel")

    panel.revertButton = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    panel.revertButton:SetSize(108, 24)
    panel.revertButton:SetPoint("BOTTOMLEFT", 18, 48)
    panel.revertButton:SetText("Revert")
    panel.revertButton:Disable()

    panel.resetButton = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    panel.resetButton:SetSize(340, 24)
    panel.resetButton:SetPoint("BOTTOM", 0, 14)
    panel.resetButton:SetText("Restore All Defaults")

    -- (Legacy exclude + per-row reset creation removed; handled inside FormBuilder)

    -- Layout Manager & Import/Export (secondary row above reset for spacing)
    panel.layoutBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    panel.layoutBtn:SetSize(136, 22)
    panel.layoutBtn:SetPoint("BOTTOMLEFT", panel.resetButton, "TOPLEFT", 0, 8)
    panel.layoutBtn:SetText("Layouts")
    panel.layoutBtn:SetScript("OnClick", function()
        if ReplayFrame.EditModeIntegration then ReplayFrame.EditModeIntegration:ShowLayoutManager() end
    end)

    panel.bundleBtn = CreateFrame("Button", nil, panel, "GameMenuButtonTemplate")
    panel.bundleBtn:SetSize(136, 22)
    panel.bundleBtn:SetPoint("LEFT", panel.layoutBtn, "RIGHT", 10, 0)
    panel.bundleBtn:SetText("Bundle…")
    panel.bundleBtn:SetScript("OnClick", function()
        if ReplayFrame.EditModeIntegration then ReplayFrame.EditModeIntegration:ShowBundleDialog() end
    end)
    
    -- Event handlers
    -- Live preview helpers (do not commit to DB until Accept)
    panel._preview = {}
    -- Hook slider changes (builder rows)
    panel._preview = panel._preview or {}
    local function hookRow(row)
        if not row or not row.slider then return end
        row.slider:HookScript("OnValueChanged", function(_, v)
            if panel._suppressDirty then return end
            local fmt = row.format or "%d"; if row.value then row.value:SetText(string.format(fmt, v)) end
            if row.key == "scale" and ReplayFrame and ReplayFrame.DisplayFrame then
                ReplayFrame.DisplayFrame:SetScale(v)
            elseif row.key == "textScale" and CLN and CLN.db and CLN.db.profile then
                panel._preview.oldTextScale = panel._preview.oldTextScale or CLN.db.profile.queueTextScale
                local old = CLN.db.profile.queueTextScale
                CLN.db.profile.queueTextScale = v
                if ReplayFrame and ReplayFrame.ApplyQueueTextScale then ReplayFrame:ApplyQueueTextScale() end
                CLN.db.profile.queueTextScale = old
            elseif row.key == "width" and ReplayFrame and ReplayFrame.DisplayFrame then
                ReplayFrame.DisplayFrame:SetWidth(v); if ReplayFrame.Relayout then ReplayFrame:Relayout() end
            elseif row.key == "height" and ReplayFrame and ReplayFrame.DisplayFrame then
                ReplayFrame.DisplayFrame:SetHeight(v); if ReplayFrame.Relayout then ReplayFrame:Relayout() end
            elseif row.key == "modelHeight" and ReplayFrame and ReplayFrame.NpcModelFrame then
                ReplayFrame.NpcModelFrame:SetHeight(v); if ReplayFrame.Relayout then ReplayFrame:Relayout() end
            end
            panel:RefreshDirtyIndicators()
        end)
    end
    for _, row in ipairs(panel._formBuilder.rows) do hookRow(row) end

    -- Inherit exclude visual for height row (linked to width exclude)
    local function updateHeightExcludeVisual()
        if not (widthRow and widthRow.exclude and heightRow and heightRow.label) then return end
        local excluded = widthRow.exclude:GetChecked()
        if excluded then
            heightRow.label:SetTextColor(0.55,0.55,0.55)
        else
            heightRow.label:SetTextColor(0.90,0.90,0.90)
        end
    end
    if widthRow and widthRow.exclude then
        widthRow.exclude:HookScript("OnClick", updateHeightExcludeVisual)
        updateHeightExcludeVisual()
        if attachTooltip and heightRow and heightRow.slider then
            attachTooltip(heightRow.slider, "Height (Linked)", "Height is persisted/ignored together with Width via the Width exclude toggle.")
        end
    end

    panel.acceptButton:SetScript("OnClick", function()
        ReplayFrame:ApplyEditPanelSettings(panel)
        local snap = {}
        for _, row in ipairs(panel._formBuilder.rows) do
            if row.type == "slider" and row.slider then
                snap[row.origKey or row.key] = row.slider:GetValue()
            end
        end
        panel._orig = snap
        panel:RefreshDirtyIndicators()
        if ReplayFrame._dummyPreviewActive then
            ReplayFrame._dummyPreviewActive = nil
            if ReplayFrame.SetQueueData then
                ReplayFrame:SetQueueData(ReplayFrame:BuildQueueEntries())
                if ReplayFrame.ApplyQueueTextScale then ReplayFrame:ApplyQueueTextScale() end
            end
        end
        panel:Hide()
    end)

    panel.cancelButton:SetScript("OnClick", function()
        if panel._orig and panel._formBuilder then
            panel._suppressDirty = true
            for _, row in ipairs(panel._formBuilder.rows) do
                if row.type == "slider" and row.slider then
                    local v = panel._orig[row.origKey or row.key]
                    if v ~= nil then row.slider:SetValue(v) end
                end
            end
            local s = panel._orig.scale or 1.0
            if ReplayFrame and ReplayFrame.DisplayFrame then ReplayFrame.DisplayFrame:SetScale(s) end
            if CLN and CLN.db and CLN.db.profile and panel._orig.textScale then
                local old = CLN.db.profile.queueTextScale; CLN.db.profile.queueTextScale = panel._orig.textScale
                if ReplayFrame and ReplayFrame.ApplyQueueTextScale then ReplayFrame:ApplyQueueTextScale() end
                CLN.db.profile.queueTextScale = old
            end
            local w = panel._orig.width or 475
            local h = panel._orig.height or 165
            if ReplayFrame and ReplayFrame.DisplayFrame then ReplayFrame.DisplayFrame:SetSize(w,h) end
            if ReplayFrame and ReplayFrame.NpcModelFrame and panel._orig.modelHeight then
                ReplayFrame.NpcModelFrame:SetHeight(panel._orig.modelHeight)
            end
            if ReplayFrame and ReplayFrame.Relayout then ReplayFrame:Relayout() end
            panel._suppressDirty = nil
        end
        panel:RefreshDirtyIndicators()
        if ReplayFrame._dummyPreviewActive then
            ReplayFrame._dummyPreviewActive = nil
            if ReplayFrame.SetQueueData then
                ReplayFrame:SetQueueData(ReplayFrame:BuildQueueEntries())
                if ReplayFrame.ApplyQueueTextScale then ReplayFrame:ApplyQueueTextScale() end
            end
        end
        panel:Hide()
    end)

    panel.revertButton:SetScript("OnClick", function()
        if not panel._orig or not panel._formBuilder then return end
        panel._suppressDirty = true
        for _, row in ipairs(panel._formBuilder.rows) do
            if row.type == "slider" and row.slider then
                local v = panel._orig[row.origKey or row.key]
                if v ~= nil then row.slider:SetValue(v) end
            end
        end
        panel._suppressDirty = nil
        if ReplayFrame and ReplayFrame.DisplayFrame and panel._orig.scale then ReplayFrame.DisplayFrame:SetScale(panel._orig.scale) end
        if CLN and CLN.db and CLN.db.profile and panel._orig.textScale then
            local old = CLN.db.profile.queueTextScale; CLN.db.profile.queueTextScale = panel._orig.textScale
            if ReplayFrame and ReplayFrame.ApplyQueueTextScale then ReplayFrame:ApplyQueueTextScale() end
            CLN.db.profile.queueTextScale = old
        end
        if ReplayFrame and ReplayFrame.DisplayFrame then
            local w = panel._orig.width or 475; local h = panel._orig.height or 165
            ReplayFrame.DisplayFrame:SetSize(w,h)
        end
        if ReplayFrame and ReplayFrame.NpcModelFrame and panel._orig.modelHeight then
            ReplayFrame.NpcModelFrame:SetHeight(panel._orig.modelHeight)
        end
        if ReplayFrame and ReplayFrame.Relayout then ReplayFrame:Relayout() end
        panel:RefreshDirtyIndicators()
    end)

    panel.resetButton:SetScript("OnClick", function()
        panel._suppressDirty = true
        local defaults = { scale=1.0, textScale=1.0, width=475, height=165, modelHeight=140 }
        for _, row in ipairs(panel._formBuilder.rows) do
            if row.type == "slider" and row.slider then
                local def = defaults[row.origKey or row.key]
                if def ~= nil then row.slider:SetValue(def) end
            end
        end
        panel._suppressDirty = nil
        if ReplayFrame and ReplayFrame.DisplayFrame then ReplayFrame.DisplayFrame:SetScale(1.0) end
        if CLN and CLN.db and CLN.db.profile then
            local old = CLN.db.profile.queueTextScale; CLN.db.profile.queueTextScale = 1.0
            if ReplayFrame and ReplayFrame.ApplyQueueTextScale then ReplayFrame:ApplyQueueTextScale() end
            CLN.db.profile.queueTextScale = old
        end
        if ReplayFrame and ReplayFrame.DisplayFrame then ReplayFrame.DisplayFrame:SetSize(475,165) end
        if ReplayFrame and ReplayFrame.NpcModelFrame then ReplayFrame.NpcModelFrame:SetHeight(140) end
        if ReplayFrame and ReplayFrame.Relayout then ReplayFrame:Relayout() end
        panel:RefreshDirtyIndicators()
    end)
    
    -- Register for automatic ESC close via the Blizzard UISpecialFrames mechanism
    if type(UISpecialFrames) == "table" then
        local n = panel:GetName()
        local exists = false
        for i, v in ipairs(UISpecialFrames) do if v == n then exists = true break end end
        if not exists then table.insert(UISpecialFrames, n) end
    else
        -- Fallback (very old clients): temporary key handler only while shown
        panel:SetScript("OnShow", function(self)
            self:SetScript("OnKeyDown", function(s, key)
                if key == "ESCAPE" then s:Hide() end
            end)
            self:EnableKeyboard(true)
        end)
        panel:HookScript("OnHide", function(self)
            self:SetScript("OnKeyDown", nil)
            self:EnableKeyboard(false)
        end)
    end
    
    -- Attach tooltips
    if panel._formBuilder and panel._formBuilder.ApplyTooltips then
        panel._formBuilder:ApplyTooltips({
            scale = { title="Frame Scale", text="Overall scale of the conversation window." },
            width = { title="Width", text="Pixel width of the window body." },
            height = { title="Height", text="Pixel height of the window body (linked with Width exclude)." },
            modelHeight = { title="Model Height", text="Height reserved for the NPC model area." },
            textScale = { title="Text Scale", text="Relative scale for text inside the window." },
        })
    end
    attachTooltip(panel.resetButton, "Defaults", "Restore all settings to default values.")
    attachTooltip(panel.layoutBtn, "Layout Buckets", "Manage per-layout saved Chatty settings (apply/delete/reset).")
    attachTooltip(panel.bundleBtn, "Bundle Export / Import", "Copy or paste a Blizzard layout string merged with Chatty settings.")

    -- Dynamic height auto-resize based on final builder position
    function panel:AutoSize()
        if not self._formBuilder then return end
        local lastY = self._formBuilder:GetCurrentY() or -250
        -- lastY is negative offset from top to top of LAST row; estimate content depth
        local contentDepth = math.abs(lastY) + 170 -- 170 = space for slider row height + buttons + padding
        local minHeight = 300
        local desired = math.max(minHeight, contentDepth)
        if math.abs(desired - self:GetHeight()) > 1 then
            self:SetHeight(desired)
            if CLN and CLN.Logger then
                CLN.Logger:debug("EditPanel autosized height="..tostring(desired), false, CLN.Utils.LogCategories.ui)
            end
        end
    end
    -- Defer to next frame to ensure all anchors resolved
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() if panel and panel.AutoSize then panel:AutoSize() end end)
    else
        panel:AutoSize()
    end
    self._editPanel = panel
    return panel
end

function ReplayFrame:ShowEditPanel()
    local panel = self:CreateEditPanel()
    if panel.RefreshLayoutBadge then panel:RefreshLayoutBadge() end
    
    -- Load current values
    local frameScale = (CLN.db.profile.frameScale or 1.0)
    local textScale = (CLN.db.profile.queueTextScale or 1.0)
    local frameSize = CLN.db.profile.frameSize or { width = 475, height = 165 }
    local modelHeight = (CLN.db.profile.npcModelFrameHeight or 140)
    
    panel.scaleSlider:SetValue(frameScale)
    panel.scaleValue:SetText(string.format("%.2f", frameScale))
    
    panel.textScaleSlider:SetValue(textScale)
    panel.textScaleValue:SetText(string.format("%.2f", textScale))
    
    if panel.widthSlider then
        panel.widthSlider:SetValue(frameSize.width or 475)
        panel.widthValue:SetText(string.format("%d", frameSize.width or 475))
    end
    if panel.heightSlider then
        panel.heightSlider:SetValue(frameSize.height or 165)
        panel.heightValue:SetText(string.format("%d", frameSize.height or 165))
    end
    if panel.modelHeightSlider then
        panel.modelHeightSlider:SetValue(modelHeight)
        panel.modelHeightValue:SetText(string.format("%d", modelHeight))
    end
    
    -- Position near the frame if possible
    -- Detached positioning: use saved placement if any, else dock near current display frame once (not tracking afterward)
    local positioned = false
    if CLN and CLN.db and CLN.db.profile and CLN.db.profile.editPanelPos then
        local pos = CLN.db.profile.editPanelPos
        if pos.point and pos.relativePoint then
            panel:ClearAllPoints(); panel:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x or 0, pos.y or 0)
            positioned = true
        end
    end
    if not positioned then
        if self.DisplayFrame and self.DisplayFrame:IsShown() then
            panel:ClearAllPoints()
            local frame = self.DisplayFrame
            panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", 12, 0)
            local r = panel:GetRight() or 0
            local sw = GetScreenWidth and GetScreenWidth() or 1920
            if r > sw - 10 then
                panel:ClearAllPoints(); panel:SetPoint("TOPRIGHT", frame, "TOPLEFT", -12, 0)
            end
            local l = panel:GetLeft() or 0
            if l < 10 then
                panel:ClearAllPoints(); panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
        else
            panel:ClearAllPoints(); panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
    
    -- Snapshot original (for Cancel/Revert) only if opening fresh or not already tracking
    -- Always establish snapshot on open (ensures Cancel works per open session)
    panel._orig = {
        scale = frameScale,
        textScale = textScale,
        width = frameSize.width or 475,
        height = frameSize.height or 165,
        modelHeight = modelHeight,
    }
    panel._suppressDirty = true
    panel:RefreshDirtyIndicators()
    panel._suppressDirty = nil
    panel:Show(); panel:Raise()

    -- -----------------------------------------------------------------
    -- Dummy queue/text preview population for text scaling adjustments
    -- Only inject if little/no real data and not already active.
    -- -----------------------------------------------------------------
    if self and self.SetQueueData and not self._dummyPreviewActive then
        local realCount = (CLN.questsQueue and #CLN.questsQueue or 0)
        local now = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
        if realCount < 2 and not now then
            self._dummyPreviewActive = true
            self._dummyPrevEntries = self:BuildQueueEntries() -- capture any existing
            local sample = {
                { isPlaying = true, label = "Speaking: The Secrets of the Ancient Titan Vault", tooltip = "Currently playing placeholder narrative line for preview." },
                { label = "Quest — Gathering Storm Shards", tooltip = "A mid-length quest title used to demonstrate wrapping." },
                { label = "Quest — A Very, Very, Very Long Quest Title To Test Truncation", tooltip = "Extremely long titles will truncate and should adapt to scaling." },
                { label = "NPC: Archivist Elyndra: 'Knowledge must be preserved.'", tooltip = "Generic NPC gossip style line for visual variety." },
                { label = "NPC: Captain Thorne: 'Hold the line! We fight here.'", tooltip = "Combat style emphatic line." },
            }
            -- Feed dummy entries directly
            self:SetQueueData(sample)
            if self.ApplyQueueTextScale then self:ApplyQueueTextScale() end
            if CLN.Logger then CLN.Logger:debug("Dummy preview queue populated for Edit Panel", false, CLN.Utils.LogCategories.ui) end
        end
    end

    -- ---------------------------------------------------------------------------------
    -- Preview Model: If no model currently shown, show player's model as a temporary preview
    -- ---------------------------------------------------------------------------------
    if self.NpcModelFrame then
        local mf = self.NpcModelFrame
        if not mf:IsShown() then
            panel._previewModel = true
            mf:Show()
        end
        -- Only apply player preview if frame appears empty (heuristic: check for GetModelFileID or GetDisplayInfo not available)
        if panel._previewModel then
            local ok = pcall(function()
                if mf.SetUnit then mf:SetUnit("player") end
            end)
            if CLN and CLN.Logger then
                CLN.Logger:debug("EditPanel preview model activated (player) ok="..tostring(ok), false, CLN.Utils.LogCategories.ui)
            end
        end
        -- Apply current slider-driven height immediately to preview
        if panel.modelHeightSlider then
            mf:SetHeight(panel.modelHeightSlider:GetValue() or (CLN.db.profile.npcModelFrameHeight or 140))
        end
    end

    -- Click-away auto-hide removed: panel now persists until Accept/Cancel/ESC/ leaving Edit Mode
    -- Rationale: prevents accidental dismissal while adjusting other Edit Mode UI elements.
end

function ReplayFrame:ApplyEditPanelSettings(panel)
    if not panel then return end
    
    local frameScale = panel.scaleSlider:GetValue()
    local textScale = panel.textScaleSlider:GetValue()
    local width = panel.widthSlider and panel.widthSlider:GetValue() or 475
    local height = panel.heightSlider and panel.heightSlider:GetValue() or 165
    local modelHeight = panel.modelHeightSlider and panel.modelHeightSlider:GetValue() or 140
    
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
    -- Persist to active Edit Mode layout (optional)
    if self.PersistToActiveLayout then
        self:PersistToActiveLayout()
    elseif self.EditModeIntegration and self.EditModeIntegration.PersistCurrentToLayout then
        self.EditModeIntegration:PersistCurrentToLayout()
    end
end

function ReplayFrame:HideEditPanel()
    if self._editPanel and self._editPanel:IsShown() then
        local panel = self._editPanel
        self._editPanel:Hide()
        -- Remove temporary preview model if we created one
        if panel._previewModel and self.NpcModelFrame then
            if CLN and CLN.Logger then
                CLN.Logger:debug("EditPanel preview model cleared", false, CLN.Utils.LogCategories.ui)
            end
            self.NpcModelFrame:Hide()
            panel._previewModel = nil
        end
        -- Restore real queue data if dummy preview active
        if self._dummyPreviewActive then
            self._dummyPreviewActive = nil
            if self.SetQueueData then
                self:SetQueueData(self:BuildQueueEntries())
                if self.ApplyQueueTextScale then self:ApplyQueueTextScale() end
            end
            if CLN.Logger then CLN.Logger:debug("Dummy preview queue cleared", false, CLN.Utils.LogCategories.ui) end
        end
    end
end

function ReplayFrame:ApplyFrameScale()
    local scale = CLN.db.profile.frameScale or 1.0
    if self.DisplayFrame then
        self.DisplayFrame:SetScale(scale)
    end
end
