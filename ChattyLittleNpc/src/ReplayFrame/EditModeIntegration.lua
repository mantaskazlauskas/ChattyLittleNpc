---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local Integration = {}
ReplayFrame.EditModeIntegration = Integration
local hasAPI = (C_EditMode and type(C_EditMode.GetLayouts) == "function")
local EditMode -- resolved in Init()
local function clearBlizzardSelection()
    if EditModeManagerFrame and EditModeManagerFrame.ClearSelectedSystem then
        EditModeManagerFrame:ClearSelectedSystem()
    end
    if EditModeSystemSettingsDialog and EditModeSystemSettingsDialog.IsShown
       and EditModeSystemSettingsDialog:IsShown() then
        EditModeSystemSettingsDialog:Hide()
    end
end
local function logDebug(msg)
    if CLN and CLN.Logger then CLN.Logger:debug(msg, false, CLN.Utils.LogCategories.ui) end
end
local function logInfo(msg, chat)
    if CLN and CLN.Logger then CLN.Logger:info(msg, chat or false, CLN.Utils.LogCategories.ui) end
end
local function resolve()
    if not EditMode then EditMode = ReplayFrame.EditMode end
    return EditMode
end
local function getModules()
    local em = resolve()
    if not em then return nil end
    return em.Registry, em.Persistence, em.ImportExport, em.OverlayFactory
end
local function clearSamplesAndPreview(self)
    if self._previewModel and ReplayFrame.NpcModelFrame then ReplayFrame.NpcModelFrame:Hide(); self._previewModel = nil end
    if self._previewModelContainer and ReplayFrame.ModelContainer then
        ReplayFrame._hasValidModel = false
        ReplayFrame.ModelContainer:Hide()
        self._previewModelContainer = nil
    end
    if ReplayFrame and ReplayFrame._editModeSamples then
        ReplayFrame._editModeSamples = nil
        if ReplayFrame.SetQueueData and ReplayFrame.BuildQueueEntries then ReplayFrame:SetQueueData(ReplayFrame:BuildQueueEntries()) end
        if ReplayFrame.ApplyQueueTextScale then ReplayFrame:ApplyQueueTextScale() end
        logDebug("Cleared sample queue entries after hiding overlay")
    end
end
function Integration:GetActiveLayoutName()
    local _, Persistence = getModules()
    if not hasAPI or not Persistence then return nil end
    return Persistence:GetActiveLayoutName()
end
function Integration:ApplyLayout(name)
    local _, Persistence = getModules()
    if not hasAPI or not Persistence then return end
    Persistence:ApplyLayout(name)
end
function Integration:PersistCurrentToLayout()
    local _, Persistence = getModules()
    if not hasAPI or not Persistence then return end
    Persistence:PersistAll()
    Persistence:SyncToLegacyProfile()
end
function Integration:ShowBundleDialog()
    local _, _, ImportExport = getModules()
    if not hasAPI or not ImportExport then
        if CLN and CLN.Print then CLN:Print("Edit Mode API unavailable") end
        return
    end
    if not self._bundleDialog then
        local frame = CreateFrame("Frame", "ChattyNpcBundleDialog", UIParent, "BasicFrameTemplateWithInset")
        frame:SetSize(560, 420)
        frame:SetPoint("CENTER")
        frame:Hide()
        local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        title:SetPoint("TOP", 0, -12)
        title:SetText("Chatty NPC Import / Export")
        local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 16, -40)
        scroll:SetPoint("BOTTOMRIGHT", -32, 58)
        local editBox = CreateFrame("EditBox", nil, scroll)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
        editBox:SetWidth(500)
        editBox:SetText("")
        editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
        editBox:SetScript("OnCursorChanged", function(_, _, y)
            local range = scroll:GetVerticalScrollRange() or 0
            if y < 0 then scroll:SetVerticalScroll(math.min(-y, range)) end
        end)
        scroll:SetScrollChild(editBox)
        local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        exportBtn:SetSize(110, 24)
        exportBtn:SetPoint("BOTTOMLEFT", 16, 20)
        exportBtn:SetText("Export")
        exportBtn:SetScript("OnClick", function()
            local bundle, err = ImportExport:ExportBundle()
            if not bundle then
                if CLN and CLN.Print then CLN:Print("Export failed: " .. tostring(err)) end
                return
            end
            editBox:SetText(bundle)
            if editBox.HighlightText then editBox:HighlightText() end
            if editBox.SetFocus then editBox:SetFocus() end
            if CLN and CLN.Print then CLN:Print("Bundle exported to dialog") end
        end)
        local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        importBtn:SetSize(110, 24)
        importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 8, 0)
        importBtn:SetText("Import")
        importBtn:SetScript("OnClick", function()
            local ok, msg = ImportExport:ImportBundle(editBox:GetText() or "")
            if CLN and CLN.Print then CLN:Print((ok and "Import success: " or "Import failed: ") .. tostring(msg)) end
            if ok then Integration:UpdateLayoutBadge() end
        end)
        local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        closeBtn:SetSize(110, 24)
        closeBtn:SetPoint("BOTTOMRIGHT", -16, 20)
        closeBtn:SetText("Close")
        closeBtn:SetScript("OnClick", function() frame:Hide() end)
        frame.editBox = editBox
        self._bundleDialog = frame
    end
    self._bundleDialog:Show()
    self._bundleDialog:Raise()
end
function Integration:ShowLayoutManager()
    if CLN and CLN.Print then CLN:Print("Layout Manager: coming soon") end
end
function Integration:UpdateLayoutBadge()
    local Registry, _, _, OverlayFactory = getModules()
    if not hasAPI or not Registry or not OverlayFactory then return end
    Registry:ForEach(function(_, controller) OverlayFactory:RefreshVisuals(controller) end)
end
function Integration:InjectSampleDataIfNeeded()
    if not ReplayFrame or not ReplayFrame.SetQueueData then return end
    local realCount = (CLN.questsQueue and #CLN.questsQueue or 0)
    local playing = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying or nil
    if realCount > 0 or playing or ReplayFrame._editModeSamples then return end
    local samples = {
        { isPlaying = true, label = "[Now Playing] Sample: The Fallen Watcher", tooltip = "Sample active narration" },
        { label = "Camp Torchlighting", tooltip = "Sample queued quest #1" },
        { label = "A Delicate Delivery", tooltip = "Sample queued quest #2" },
        { label = "Secrets in the Dust", tooltip = "Sample queued quest #3" },
        { label = "Tide of Shadows", tooltip = "Sample queued quest #4" },
    }
    ReplayFrame._editModeSamples = samples
    ReplayFrame:SetQueueData(samples)
    if ReplayFrame.ApplyQueueTextScale then ReplayFrame:ApplyQueueTextScale() end
end
function Integration:ShowOverlay()
    if not hasAPI then return end
    local Registry, _, _, OverlayFactory = getModules()
    if not Registry or not OverlayFactory then return end
    Registry:ForEach(function(_, controller) OverlayFactory:Show(controller) end)
    self:InjectSampleDataIfNeeded()
    if ReplayFrame.ModelContainer and not ReplayFrame.ModelContainer:IsShown() then
        self._previewModelContainer = true
        ReplayFrame._hasValidModel = true
        ReplayFrame.ModelContainer:Show()
        if ReplayFrame.NpcModelFrame and not ReplayFrame.NpcModelFrame:IsShown() then
            self._previewModel = true
            ReplayFrame.NpcModelFrame:Show()
            pcall(function() if ReplayFrame.NpcModelFrame.SetUnit then ReplayFrame.NpcModelFrame:SetUnit("player") end end)
        end
        if ReplayFrame.LayoutModelArea and ReplayFrame.DisplayFrame then ReplayFrame:LayoutModelArea(ReplayFrame.DisplayFrame) end
    end
end
function Integration:HideOverlay()
    local Registry, _, _, OverlayFactory = getModules()
    if Registry and OverlayFactory then Registry:ForEach(function(_, controller) OverlayFactory:Hide(controller) end) end
    clearSamplesAndPreview(self)
end
Integration.overlay = {
    SetSelected = function(_, selected)
        if not EditMode or not EditMode.Registry then return end
        if selected then
            EditMode.Registry:Select("conversation", "panel")
        else
            EditMode.Registry:Select(nil, "panel")
        end
    end,
}
function Integration:Init()
    EditMode = ReplayFrame.EditMode
    if self._init or not hasAPI then return end
    local Registry, Persistence, ImportExport = getModules()
    if not Registry or not Persistence then return end

    -- Inject UI methods onto ImportExport so EditPanel.lua can find them
    if ImportExport then
        if not ImportExport.ShowBundleDialog then
            ImportExport.ShowBundleDialog = function() Integration:ShowBundleDialog() end
        end
        if not ImportExport.ShowLayoutManager then
            ImportExport.ShowLayoutManager = function() Integration:ShowLayoutManager() end
        end
    end

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "EDIT_MODE_LAYOUTS_UPDATED" then
            C_Timer.After(0.05, function()
                local name = Persistence:GetActiveLayoutName()
                if name then Persistence:ApplyLayout(name) end
                self:UpdateLayoutBadge()
                if ReplayFrame._editPanel and ReplayFrame._editPanel:IsShown() and ReplayFrame._editPanel.RefreshLayoutBadge then
                    ReplayFrame._editPanel:RefreshLayoutBadge()
                end
            end)
        elseif event == "PLAYER_REGEN_ENABLED" then
            Persistence:ApplyPendingLayout()
            if self._pendingPersist then self._pendingPersist = false; self:PersistCurrentToLayout() end
        end
    end)
    self._eventFrame = eventFrame
    if C_EditMode and C_EditMode.OnEditModeExit and hooksecurefunc and not self._exitHooked then
        hooksecurefunc(C_EditMode, "OnEditModeExit", function()
            ReplayFrame._blizzardEditMode = false
            self:HideOverlay()
            if ReplayFrame._editPanel and ReplayFrame._editPanel:IsShown() then ReplayFrame._editPanel:Hide() end
            if ReplayFrame.DisplayFrame then
                ReplayFrame._forceShow = false
                local playing = ReplayFrame.IsVoiceoverCurrenltyPlaying and ReplayFrame:IsVoiceoverCurrenltyPlaying()
                local empty = ReplayFrame.IsQuestQueueEmpty and ReplayFrame:IsQuestQueueEmpty()
                if not playing and empty and not ReplayFrame._manualEdit then ReplayFrame.DisplayFrame:Hide() end
            end
        end)
        self._exitHooked = true
    end
    if not self._buttonTicker then
        local elapsed = 0
        self._buttonTicker = C_Timer.NewTicker(0.25, function(ticker)
            elapsed = elapsed + 0.25
            if EditModeManagerFrame then
                if not self._buttonInjected then
                    local b = CreateFrame("Button", nil, EditModeManagerFrame, "UIPanelButtonTemplate")
                    b:SetSize(120, 20)
                    b:SetText("Chatty NPC")
                    if EditModeManagerFrame.RevertAllChangesButton then
                        b:SetPoint("TOPLEFT", EditModeManagerFrame.RevertAllChangesButton, "BOTTOMLEFT", 0, -6)
                    else
                        b:SetPoint("BOTTOMLEFT", EditModeManagerFrame, "BOTTOMLEFT", 16, 16)
                    end
                    b:SetScript("OnClick", function()
                        clearBlizzardSelection()
                        Registry:Select("conversation", "button")
                        if ReplayFrame.ShowEditPanel then ReplayFrame:ShowEditPanel() end
                        self:ShowOverlay()
                    end)
                    self._buttonInjected = true
                    logDebug("Injected Chatty NPC button into Edit Mode UI")
                end
                ticker:Cancel()
            elseif elapsed >= 5 then
                ticker:Cancel()
            end
        end)
    end
    if EditModeManagerFrame and hooksecurefunc and not self._enterHooked then
        hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
            if InCombatLockdown and InCombatLockdown() then return end
            ReplayFrame._blizzardEditMode = true
            ReplayFrame._forceShow = true
            ReplayFrame.userHidden = false
            ReplayFrame:GetDisplayFrame()
            if ReplayFrame.DisplayFrame then ReplayFrame.DisplayFrame:Show() end
            self:ShowOverlay()
        end)
        self._enterHooked = true
    end
    if EditModeManagerFrame and EditModeManagerFrame.SelectSystem and hooksecurefunc and not self._selectHooked then
        hooksecurefunc(EditModeManagerFrame, "SelectSystem", function()
            if ReplayFrame._editPanel and ReplayFrame._editPanel:IsShown() then ReplayFrame._editPanel:Hide() end
        end)
        self._selectHooked = true
    end
    self._init = true
    logInfo("Edit Mode integration initialized")
end
function ReplayFrame:InitEditModeIntegration()
    local em = self.EditMode
    if em and em.Bootstrap then em.Bootstrap() end
    if self.EditModeIntegration then self.EditModeIntegration:Init() end
end
function ReplayFrame:PersistToActiveLayout()
    local Persistence = self.EditMode and self.EditMode.Persistence
    if not hasAPI or not Persistence then return end
    if InCombatLockdown and InCombatLockdown() then
        if self.EditModeIntegration then self.EditModeIntegration._pendingPersist = true end
        logDebug("Persist deferred (combat)")
        return
    end
    Persistence:PersistAll()
    Persistence:SyncToLegacyProfile()
end
function ReplayFrame:SetEditMode(enabled)
    self._editMode = not not enabled
    self:GetDisplayFrame()
    local frame = self.DisplayFrame
    if not frame then return end
    if self._editMode then
        if not self._manualEditHooks then
            self._manualEditHooks = { onDragStart = frame:GetScript("OnDragStart"), onDragStop = frame:GetScript("OnDragStop") }
        end
        frame:SetMovable(true)
        if frame.SetResizable then frame:SetResizable(true) end
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function(f) if not self._isResizing then f:StartMoving() end end)
        frame:SetScript("OnDragStop", function(f) f:StopMovingOrSizing(); if self.SaveFramePosition then self:SaveFramePosition() end end)
        if self.ResizeGrip then self.ResizeGrip:Show() end
    else
        frame:StopMovingOrSizing()
        frame:RegisterForDrag()
        frame:SetMovable(false)
        if frame.SetResizable then frame:SetResizable(false) end
        if self._manualEditHooks then
            frame:SetScript("OnDragStart", self._manualEditHooks.onDragStart)
            frame:SetScript("OnDragStop", self._manualEditHooks.onDragStop)
        end
        if self.ResizeGrip then self.ResizeGrip:Hide() end
    end
end
function ReplayFrame:ShowForEdit()
    self._forceShow = true
    self.userHidden = false
    self:GetDisplayFrame()
    if self.DisplayFrame then self.DisplayFrame:Show() end
    self:SetEditMode(true)
end
function ReplayFrame:BeginManualEdit()
    self._manualEdit = true
    self._forceShow = true
    self.userHidden = false
    self:GetDisplayFrame()
    if self.DisplayFrame then self.DisplayFrame:Show() end
    self:SetEditMode(true)
end
function ReplayFrame:EndManualEdit()
    self._manualEdit = false
    self:SetEditMode(false)
    if self.SaveFramePosition then self:SaveFramePosition() end
    local blizActive = hasAPI and EditModeManagerFrame
        and EditModeManagerFrame.IsInEditMode and EditModeManagerFrame:IsInEditMode()
    if not blizActive then
        self._forceShow = false
        local playing = self.IsVoiceoverCurrenltyPlaying and self:IsVoiceoverCurrenltyPlaying()
        local empty = self.IsQuestQueueEmpty and self:IsQuestQueueEmpty()
        if not playing and empty and self.DisplayFrame then self.DisplayFrame:Hide() end
    end
end
C_Timer.After(2, function()
    if hasAPI and EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        Integration:ShowOverlay()
        local Registry = ReplayFrame.EditMode and ReplayFrame.EditMode.Registry
        if Registry then Registry:OnEnter() end
    end
end)

