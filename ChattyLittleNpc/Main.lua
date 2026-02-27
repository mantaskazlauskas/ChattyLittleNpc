---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc = CLN

-- Module references (will be populated by each module file)
CLN.EventHandler = nil
CLN.Options = nil

CLN.locale = nil
CLN.gameVersion = nil
CLN.useNamespaces = nil
CLN.expansions = { "Battle_for_Azeroth_voiceovers", "Cataclysm_voiceovers", "Vanilla_voiceovers", "Dragonflight_voiceovers", "Legion_voiceovers", "Mists_of_Pandaria_voiceovers", "Shadowlands_voiceovers", "The_Burning_Crusade_voiceovers", "The_War_Within_voiceovers", "Warlords_of_Draenor_voiceovers", "Wrath_of_the_Lich_King_voiceovers" }
CLN.loadedVoiceoverPacks = {}
CLN.VoiceoverPacks = {}
CLN.questsQueue = {}
CLN.isDUIAddonLoaded = false
CLN.isElvuiAddonLoaded = false
CLN.currentItemInfo = {
    ItemID = nil,
    ItemName = nil,
    ItemText = nil
}

-- Diagnostic function to check voiceover pack status
function CLN:CheckVoiceoverPacks()
    if not self.Logger then return end
    self.Logger:info("Checking for voiceover packs...")
    local foundCount = 0
    for _, expansion in ipairs(self.expansions) do
        local packName = "ChattyLittleNpc_" .. expansion
        local isLoaded = C_AddOns.IsAddOnLoaded(packName)
        if isLoaded then
            foundCount = foundCount + 1
            local addon = _G[packName]
            local voCount = (addon and addon.Voiceovers and #addon.Voiceovers) or 0
            self.Logger:info("|cff00ff00✓|r " .. packName .. " - " .. voCount .. " voiceovers")
        else
            self.Logger:info("|cffff0000✗|r " .. packName .. " - Not loaded")
        end
    end
    if foundCount == 0 then
        self.Logger:warn("No voiceover packs found!")
        self.Logger:info("You need to install voiceover pack addons separately.")
    else
        self.Logger:info("|cff00ff00Found " .. foundCount .. " voiceover pack(s)|r")
    end
end

local defaults = {
    profile = {
        schemaVersion = 1,
        autoPlayVoiceovers = true,
        playVoiceoverAfterDelay = 0,
        printMissingFiles = false,
        logNpcTexts = true,
        printNpcTexts = false,
        -- Mirror addon logs to the chat frame (the Logs window always captures). Off by default to keep chat clean.
        logToChat = false,
        overwriteExistingGossipValues = false,
        showGossipEditor = false,
        showReplayFrame = true,
        alwaysShowReplayFrame = false,
        showSpeakButton = true,
        lockInEditMode = false,
        hideInEditMode = false,
        compactMode = false,
        queueTextScale = 1.0,
        frameScale = 1.0,
        npcModelFrameHeight = 140,
        -- Last known window position/size
        framePos = { -- Default position
            point = "CENTER",
            relativeTo = nil,
            relativePoint = "CENTER",
            xOfs = 500,
            yOfs = 0
        },
        frameSize = { width = 310 + 165, height = 310 },
        buttonPosX = -15,
        buttonPosY = -30,
        -- Unified quest playback mode: "queue" | "stopOnClose" | "manual"
        questPlaybackMode = "queue",
        audioChannel = "MASTER",
        -- Rendering backend preference for the Replay Frame model host: 'auto' | 'scene' | 'player'
        renderBackend = "auto",
        -- Advanced projector-based fitting for ModelScene backend (optional)
        advancedCameraFitting = false,
        debugMode = false,
        debugAnimations = false,
        debugNoAnim = false,
        disableCameraAnimations = false,
        -- Per Edit Mode layout overrides (keyed by layoutName)
        editModeLayouts = {},
        -- Replay UI: combat behavior
        combatAutoCollapse = true,
        -- Replay UI: progress bar
        showProgressBar = true,
        -- Replay UI: subtitles
        showSubtitles = false,
        subtitleFontScale = 1.0,
        -- Replay UI: queue type badges
        showQuestTypeBadges = true,
        -- Replay UI: history
        queueHistoryMaxEntries = 20,
        historyTTLMinutes = 5,
        -- Replay UI: edit mode glow hints
        editModeGlowHints = true,
        -- Accessibility: high-contrast mode for colorblind users
        highContrastMode = false,
        -- Gossip cooldown: don't replay the same gossip line within a session
        gossipCooldownEnabled = false,
        -- Native VO handling: "off" (ignore), "all" (pause on any), "whitelist" (user-curated)
        nativeVOMode = "off",
        -- Whitelisted NPCs: keyed by NPC ID (number) or name (string) → true
        nativeVOWhitelist = {},
        -- Dismissed NPCs: don't ask about these again in the popup
        nativeVODismissed = {},
    }
}

-- Migrate legacy saved variables from upstream format to fork format
function CLN:_MigrateSavedVars()
    if not (self.db and self.db.profile) then return end
    local p = self.db.profile

    -- Schema version guard: run migrations in order, then stamp current version
    local sv = p.schemaVersion or 0

    if sv < 1 then
        -- v1: initial schema stamp (all existing migrations below remain for pre-v1 profiles)
    end

    p.schemaVersion = 1

    -- Migrate pauseOnNativeVO boolean → nativeVOMode
    if p.pauseOnNativeVO ~= nil then
        if p.pauseOnNativeVO == true and (not p.nativeVOMode or p.nativeVOMode == "off") then
            p.nativeVOMode = "whitelist"
        end
        p.pauseOnNativeVO = nil
    end

    -- Migrate legacy "all" mode → "whitelist" (all mode removed)
    if p.nativeVOMode == "all" then
        p.nativeVOMode = "whitelist"
    end

    -- Migrate enableQuestPlaybackQueueing + stopVoiceoverAfterDialogWindowClose → questPlaybackMode
    if p.enableQuestPlaybackQueueing ~= nil or p.stopVoiceoverAfterDialogWindowClose ~= nil then
        if p.stopVoiceoverAfterDialogWindowClose then
            p.questPlaybackMode = "stopOnClose"
        elseif p.enableQuestPlaybackQueueing == false then
            p.questPlaybackMode = "manual"
        else
            p.questPlaybackMode = "queue"
        end
        p.enableQuestPlaybackQueueing = nil
        p.stopVoiceoverAfterDialogWindowClose = nil
    end

    -- Migrate layoutPositions/layoutSizes → editModeLayouts
    if p.layoutPositions or p.layoutSizes then
        if not p.editModeLayouts then p.editModeLayouts = {} end
        -- Best-effort: merge any existing per-layout data
        if type(p.layoutPositions) == "table" then
            for name, pos in pairs(p.layoutPositions) do
                if not p.editModeLayouts[name] then p.editModeLayouts[name] = {} end
                p.editModeLayouts[name].framePos = pos
            end
        end
        if type(p.layoutSizes) == "table" then
            for name, size in pairs(p.layoutSizes) do
                if not p.editModeLayouts[name] then p.editModeLayouts[name] = {} end
                p.editModeLayouts[name].frameSize = size
            end
        end
        p.layoutPositions = nil
        p.layoutSizes = nil
    end
end

function CLN:OnInitialize()
    self.db = ChattyLittleNpc.Database:New("ChattyLittleNpcDB", defaults, true)

    -- Attach deferred IconAtlas if file loaded before addon existed
    if not self.IconAtlas and _G.ChattyLittleNpc_PendingAtlas then
        self.IconAtlas = _G.ChattyLittleNpc_PendingAtlas
        _G.ChattyLittleNpc_PendingAtlas = nil
    end

    -- Ensure questPlaybackMode always has a valid value
    local m = self.db.profile.questPlaybackMode
    if m ~= "queue" and m ~= "stopOnClose" and m ~= "manual" then
        self.db.profile.questPlaybackMode = "queue"
    end

    self.locale = GetLocale()
    self.gameVersion = select(4, GetBuildInfo())
    self.useNamespaces = self.gameVersion >= 90000 -- namespaces were added in starting Shadowlands

    -- Merge baked-in known voiced NPCs into user's whitelist (zero friction)
    self:MergeKnownVoicedNpcs()

    if (self.db.profile.debugMode) then
        local version, build, date, tocVersion = GetBuildInfo()
        local C = self.Utils and self.Utils.LogCategories or { misc = 'misc' }
        if self.Logger then
            self.Logger:debug("Game Version: " .. tostring(version), false, C.misc)
            self.Logger:debug("Build Number: " .. tostring(build), false, C.misc)
            self.Logger:debug("Build Date: " .. tostring(date), false, C.misc)
            self.Logger:debug("TOC Version: " .. tostring(tocVersion), false, C.misc)
        end
    end
end

function CLN:OnEnable()
    CLN.EventHandler:RegisterEvents()

    if (self.ReplayFrame.DisplayFrame) then
        self.ReplayFrame:LoadFramePosition()
    end

    -- Quest Log play button: QuestMapFrame is a load-on-demand Blizzard addon
    -- so it may not exist yet.  Try immediately, else defer until it loads.
    -- In modern WoW (11.x), DetailsFrame may be created lazily after the
    -- addon loads, so we also retry when QuestMapFrame is first shown.
    local questLogAttached = false
    local function installQuestLogHooks()
        if type(QuestMapFrame_UpdateAll) == "function" then
            hooksecurefunc("QuestMapFrame_UpdateAll", self.PlayButton.UpdatePlayButton)
        end
        if QuestMapFrame.DetailsFrame then
            QuestMapFrame.DetailsFrame:HookScript("OnShow", self.PlayButton.UpdatePlayButton)
            QuestMapFrame.DetailsFrame:HookScript("OnHide", self.PlayButton.HidePlayButton)
        end
    end
    local function tryAttachQuestLogButtons()
        if not QuestMapFrame then return false end
        if not QuestMapFrame.DetailsFrame then
            -- Frame exists but DetailsFrame not yet created — hook OnShow to retry
            QuestMapFrame:HookScript("OnShow", function()
                if not questLogAttached and QuestMapFrame.DetailsFrame then
                    questLogAttached = true
                    self.PlayButton:AttachQuestLogAndDetailsButtons()
                    installQuestLogHooks()
                    self.PlayButton:UpdatePlayButton()
                end
            end)
            return true -- stop listening for ADDON_LOADED; OnShow will handle it
        end
        questLogAttached = true
        self.PlayButton:AttachQuestLogAndDetailsButtons()
        installQuestLogHooks()
        QuestMapFrame:HookScript("OnShow", self.PlayButton.UpdatePlayButton)
        return true
    end
    if not tryAttachQuestLogButtons() then
        -- Use modern EventUtil if available (WoW 11.x+), with ADDON_LOADED fallback
        if EventUtil and EventUtil.ContinueOnAddOnLoaded then
            EventUtil.ContinueOnAddOnLoaded("Blizzard_QuestLog", function()
                tryAttachQuestLogButtons()
            end)
        else
            local waitFrame = CreateFrame("Frame")
            waitFrame:RegisterEvent("ADDON_LOADED")
            waitFrame:SetScript("OnEvent", function(f, event, addonName)
                if addonName == "Blizzard_QuestLog" or QuestMapFrame then
                    f:UnregisterEvent("ADDON_LOADED")
                    f:SetScript("OnEvent", nil)
                    -- Defer one frame to allow lazy initialization
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, tryAttachQuestLogButtons)
                    else
                        tryAttachQuestLogButtons()
                    end
                end
            end)
        end
    end

    self:GetLoadedExpansionVoiceoverPacks()
    self:GetLoadedAddonsForIntegrations()

    if (self.db.profile.logNpcTexts) then
        self.NpcDialogTracker:GatherTooltipInfo()
    end

    -- Live option change hooks: apply visuals immediately
    if self.db and self.db.RegisterCallback and not self._dbProfileHooked then
        local function applyKey(key)
            if key == "queueTextScale" and self.ReplayFrame and self.ReplayFrame.ApplyQueueTextScale then
                self.ReplayFrame:ApplyQueueTextScale()
            elseif key == "compactMode" and self.ReplayFrame and self.ReplayFrame.UpdateDisplayFrameState then
                self.ReplayFrame:UpdateDisplayFrameState()
            elseif key == "showReplayFrame" and self.ReplayFrame and self.ReplayFrame.UpdateDisplayFrameState then
                self.ReplayFrame:UpdateDisplayFrameState()
            elseif key == "alwaysShowReplayFrame" and self.ReplayFrame and self.ReplayFrame.UpdateDisplayFrameState then
                self.ReplayFrame:UpdateDisplayFrameState()
            elseif key == "combatAutoCollapse" and self.ReplayFrame then
                local inCombat = (self._inCombat == true) or (InCombatLockdown and InCombatLockdown())
                if inCombat and self.db.profile.combatAutoCollapse and self.ReplayFrame.OnCombatStart then
                    self.ReplayFrame:OnCombatStart()
                elseif (not self.db.profile.combatAutoCollapse) and self.ReplayFrame._combatAutoCollapsed and self.ReplayFrame.OnCombatEnd then
                    self.ReplayFrame:OnCombatEnd()
                end
            elseif key == "showProgressBar" and self.ReplayFrame and self.ReplayFrame.UpdateProgressBar then
                self.ReplayFrame:UpdateProgressBar()
            elseif key == "showSubtitles" and self.ReplayFrame then
                local cur = self.VoiceoverPlayer and self.VoiceoverPlayer.currentlyPlaying
                if self.db.profile.showSubtitles and cur and cur.title and self.ReplayFrame.ShowSubtitle then
                    self.ReplayFrame:ShowSubtitle(cur.title)
                elseif self.ReplayFrame.HideSubtitle then
                    self.ReplayFrame:HideSubtitle()
                end
            elseif key == "editModeGlowHints" and self.ReplayFrame then
                if self.db.profile.editModeGlowHints and self.ReplayFrame.StartEditGlowPulse then
                    self.ReplayFrame:StartEditGlowPulse()
                elseif self.ReplayFrame.StopEditGlowPulse then
                    self.ReplayFrame:StopEditGlowPulse()
                end
            elseif key == "showQuestTypeBadges" and self.ReplayFrame and self.ReplayFrame.MarkQueueDirty then
                self.ReplayFrame:MarkQueueDirty()
            elseif key == "highContrastMode" and self.ReplayFrame and self.ReplayFrame.MarkQueueDirty then
                self.ReplayFrame:MarkQueueDirty()
            elseif key == "subtitleFontScale" and self.ReplayFrame then
                if self.ReplayFrame.SubtitleText then
                    local fontScale = (self.db and self.db.profile and self.db.profile.subtitleFontScale) or 1.0
                    self.ReplayFrame.SubtitleText:SetFont("Fonts\\FRIZQT__.TTF", math.max(8, math.floor(12 * fontScale)), "")
                end
                local cur = self.VoiceoverPlayer and self.VoiceoverPlayer.currentlyPlaying
                if self.db.profile.showSubtitles and cur and cur.title and self.ReplayFrame.ShowSubtitle then
                    self.ReplayFrame:ShowSubtitle(cur.title)
                end
            elseif key == "debugMode" or key == "debugAnimations" then
                -- no-op: toggles just affect logging gates
            elseif key == "debugNoAnim" and self.ReplayFrame and self.ReplayFrame.SetNoAnimDebug then
                self.ReplayFrame:SetNoAnimDebug(self.db.profile.debugNoAnim)
                if self.ReplayFrame._UpdateModelOnUpdateHook then
                    self.ReplayFrame:_UpdateModelOnUpdateHook()
                end
            elseif key == "advancedCameraFitting" and self.ReplayFrame then
                -- Rebuild host so the framer delegation toggles cleanly
                if self.ReplayFrame.RebuildModelHost then
                    self.ReplayFrame:RebuildModelHost()
                end
                -- Re-apply default fit to the current model if visible
                if self.ReplayFrame.ApplyDefaultFit then
                    local cur = self.VoiceoverPlayer and self.VoiceoverPlayer.currentlyPlaying
                    if cur and (self.ReplayFrame.NpcModelFrame and self.ReplayFrame.NpcModelFrame.IsShown and self.ReplayFrame.NpcModelFrame:IsShown()) then
                        self.ReplayFrame:ApplyDefaultFit(cur.displayID)
                    end
                end
                    elseif key == "disableCameraAnimations" and self.ReplayFrame then
                        if self.ReplayFrame.AnimStop then
                            self.ReplayFrame:AnimStop('zoom')
                            self.ReplayFrame:AnimStop('pan')
                        end
                        if self.ReplayFrame._UpdateModelOnUpdateHook then
                            self.ReplayFrame:_UpdateModelOnUpdateHook()
                        end
            elseif key == "questPlaybackMode" then
                -- no-op: legacy sync removed; questPlaybackMode is the single source of truth
            end
        end
        -- Use dot-notation per CallbackHandler: self is the addon receiving callbacks
        self.db:RegisterCallback("OnProfileChanged", function()
            -- Rebuild UI scaling and visibility on profile switch
            applyKey("queueTextScale")
            applyKey("compactMode")
            applyKey("showReplayFrame")
            applyKey("alwaysShowReplayFrame")
            applyKey("debugNoAnim")
            applyKey("combatAutoCollapse")
            applyKey("showProgressBar")
            applyKey("showSubtitles")
            applyKey("editModeGlowHints")
            applyKey("showQuestTypeBadges")
            applyKey("subtitleFontScale")
            applyKey("highContrastMode")
        end)
        self.db:RegisterCallback("OnProfileCopied", function()
                    applyKey("queueTextScale"); applyKey("compactMode"); applyKey("showReplayFrame"); applyKey("alwaysShowReplayFrame"); applyKey("debugNoAnim"); applyKey("disableCameraAnimations"); applyKey("combatAutoCollapse"); applyKey("showProgressBar"); applyKey("showSubtitles"); applyKey("editModeGlowHints"); applyKey("showQuestTypeBadges"); applyKey("subtitleFontScale"); applyKey("highContrastMode")
        end)
        self.db:RegisterCallback("OnProfileReset", function()
                    applyKey("queueTextScale"); applyKey("compactMode"); applyKey("showReplayFrame"); applyKey("alwaysShowReplayFrame"); applyKey("debugNoAnim"); applyKey("disableCameraAnimations"); applyKey("combatAutoCollapse"); applyKey("showProgressBar"); applyKey("showSubtitles"); applyKey("editModeGlowHints"); applyKey("showQuestTypeBadges"); applyKey("subtitleFontScale"); applyKey("highContrastMode")
        end)
        self._dbProfileHooked = true
    end
end

-- Internal: keep legacy flags in sync for existing code paths until fully refactored
-- Legacy sync removed; flags fully deprecated.

function CLN:OnDisable()
    CLN.EventHandler:UnregisterEvents()
end

--[[
    Retrieves comprehensive information about a specified unit including name, gender, race, and ID.
    
    @param unit string: The unit identifier (e.g., "target", "npc", "player", "party1", etc.)
    @return string unitName: The name of the unit, empty string if unavailable
    @return string gender: The gender of the unit ("Neutral", "Male", "Female", or empty string)
    @return string race: The race of the unit, empty string if unavailable
    @return string unitGuid: The unique GUID of the unit, nil if unavailable
    @return string|nil unitType: The type of unit ("Creature", "Vehicle", "GameObject", etc.), nil if unavailable
    @return number|nil unitId: The numeric ID of the unit (for creatures, vehicles, game objects), nil if unavailable
]]
function CLN:GetUnitInfo(unit)
    local unitName = select(1, UnitName(unit)) or ""
    local sex = UnitSex(unit) -- 1 = neutral, 2 = male, 3 = female
    local gender = (sex == 1 and "Neutral") or (sex == 2 and "Male") or (sex == 3 and "Female") or ""
    local race = UnitRace(unit) or ""

    local unitGuid = UnitGUID(unit)
    local unitType = nil
    local unitId = nil

    if (unitGuid) then
        local success, uType, uId = pcall(function()
            local t = select(1, strsplit("-", unitGuid))
            local id = nil
            if (t == "Creature" or t == "Vehicle" or t == "GameObject") then
                local idString = select(6, strsplit("-", unitGuid))
                id = tonumber(idString)
            end
            return t, id
        end)
        if success then
            unitType = uType
            unitId = uId
        end
    end

    return unitName, gender, race, unitGuid, unitType, unitId
end

--[[
    Retrieves the title of a quest given its quest ID.
    
    @param questID number: The unique identifier for the quest.
    @return string: The title of the quest.
]]
function CLN:GetTitleForQuestID(questID)
    if (self.useNamespaces) then
        return C_QuestLog.GetTitleForQuestID(questID)
    elseif (QuestUtils_GetQuestName) then
        return QuestUtils_GetQuestName(questID)
    end
end

--[[
    Retrieves the list of loaded expansion voiceover packs for the ChattyLittleNpc addon.

    @return table: A table containing the loaded expansion voiceover packs.
]]
function CLN:GetLoadedExpansionVoiceoverPacks()
    for _, expansion in ipairs(self.expansions) do
        local voiceoverPackName = "ChattyLittleNpc_" .. expansion
        local isLoaded = C_AddOns.IsAddOnLoaded(voiceoverPackName)
        if (isLoaded) then
            table.insert(self.loadedVoiceoverPacks, expansion)
            if (self.db.profile.debugMode and self.Logger) then
                local C = self.Utils and self.Utils.LogCategories or { loader = 'loader' }
                self.Logger:debug("Loaded voiceover pack: " .. tostring(expansion), false, C.loader or 'misc')
            end

            local addon = _G[voiceoverPackName]
            if addon then
                self.VoiceoverPacks[voiceoverPackName] = addon
                if addon.Voiceovers then
                    addon._voiceoverIndex = {}
                    for _, name in ipairs(addon.Voiceovers) do
                        addon._voiceoverIndex[name] = true
                    end
                end
            end
        end      
    end

    if (self.db.profile.debugMode and self.Logger) then self:PrintLoadedVoiceoverPacks() end
end

function CLN:PrintLoadedVoiceoverPacks()
    for packName, packData in pairs(self.VoiceoverPacks) do
        if packData.Metadata then
            if self.Logger then self.Logger:info("Metadata for " .. tostring(packName), false, (self.Utils and self.Utils.LogCategories.loader) or 'misc') end
            self.Utils:PrintTable(packData.Metadata)
        end
        if packData.Voiceovers then
            if self.Logger then self.Logger:info("VO count for " .. tostring(packName) .. ": " .. tostring(#packData.Voiceovers), false, (self.Utils and self.Utils.LogCategories.loader) or 'misc') end
        end
    end
end

--[[
    Handles the start of playback for a given quest phase.

    @param questPhase (number) - The phase of the quest for which playback is starting.
]]
function CLN:HandlePlaybackStart(questPhase)
    local questId = GetQuestID()
    local _, gender, _, _, _, npcId = self:GetUnitInfo("npc")
    -- Capture display ID now while the NPC unit is available (for queued playback later)
    local displayID = (UnitCreatureDisplayID and UnitExists and UnitExists("npc"))
        and UnitCreatureDisplayID("npc") or nil
    
    if self.db.profile.debugMode and self.Logger then
        self.Logger:debug("HandlePlaybackStart phase=" .. tostring(questPhase)
            .. " questId=" .. tostring(questId)
            .. " npcId=" .. tostring(npcId)
            .. " displayID=" .. tostring(displayID)
            .. " gen=" .. tostring((self._questTimerGen or 0) + 1),
            false, self.Utils.LogCategories.loader)
    end

    if (questId > 0) then
        self._questTimerGen = (self._questTimerGen or 0) + 1
        local gen = self._questTimerGen
        C_Timer.After(self.db.profile.playVoiceoverAfterDelay, function()
            if self._questTimerGen ~= gen then
                if self.db.profile.debugMode and self.Logger then
                    self.Logger:debug("HandlePlaybackStart timer SKIPPED (gen mismatch: " .. tostring(gen) .. " vs " .. tostring(self._questTimerGen) .. ")",
                        false, self.Utils.LogCategories.loader)
                end
                return
            end
            self.VoiceoverPlayer:PlayQuestSound(questId, questPhase, npcId, displayID)
        end)
    end
end


--[[ Handles the completion of a quest, including playing the associated voiceover and logging the quest text.
    Handles the start of gossip playback.

    @param id number: The ID of the gossip.
    @param text string: The text of the gossip.
    @param type string: The type of sound associated with the gossip. Possible values include "Gossip", "GameObject".
    @param gender number: The gender associated with the gossip.
]]
function CLN:HandleGossipPlaybackStart(id, text, type, gender)
    if (id > 0 and text) then
        self._gossipTimerGen = (self._gossipTimerGen or 0) + 1
        local gen = self._gossipTimerGen
        C_Timer.After(self.db.profile.playVoiceoverAfterDelay, function()
            if self._gossipTimerGen ~= gen then return end
            self.VoiceoverPlayer:PlayNonQuestSound(id, type, text, gender)
        end)
    end
end

function CLN:GetLoadedAddonsForIntegrations()
    self.isDUIAddonLoaded = C_AddOns.IsAddOnLoaded("DialogueUI")
    if (self.db.profile.debugMode and self.Logger) then
        local C = self.Utils and self.Utils.LogCategories or { ui = 'ui' }
        self.Logger:debug("DialogueUI Addon Loaded: " .. tostring(self.isDUIAddonLoaded), false, C.ui or 'misc')
    end

    self.isElvuiAddonLoaded = C_AddOns.IsAddOnLoaded("ElvUI")
    if (self.db.profile.debugMode and self.Logger) then
        local C = self.Utils and self.Utils.LogCategories or { ui = 'ui' }
        self.Logger:debug("ElvUI Addon Loaded: " .. tostring(self.isElvuiAddonLoaded), false, C.ui or 'misc')
    end

    if (self.isElvuiAddonLoaded) then
        self.PlayButton:AttachQuestLogAndDetailsButtons()
    end
end

-- Create Print method as an alias for Print utility from Print.lua
function CLN:Print(...)
    return ChattyLittleNpc.PrintUtil:Print(...)
end

-- Shared event bus for cross-module messaging (replaces AceEvent)
CLN._sharedEvents = ChattyLittleNpc.EventSystem:New()

--- Send a message on the shared addon event bus
---@param message string Message name
---@param ... any Message arguments
function CLN:SendMessage(message, ...)
    self._sharedEvents:SendMessage(message, ...)
end

--- Register a callback for a message on the shared addon event bus
---@param message string Message name
---@param callback function Callback function
function CLN:RegisterMessage(message, callback)
    self._sharedEvents:RegisterMessage(message, callback)
end

--- Unregister a callback for a message on the shared addon event bus
---@param message string Message name
---@param callback function|nil Specific callback to remove, or nil to remove all
function CLN:UnregisterMessage(message, callback)
    self._sharedEvents:UnregisterMessage(message, callback)
end

-- ============================================================================
-- Known Voiced NPC Management
-- ============================================================================

--- Merge the baked-in KnownVoicedNpcsDB into the user's whitelist.
--- Called on init and when whitelist mode is enabled.
--- Pre-populates the whitelist so it's ready when the user enables the feature.
--- Only adds entries the user hasn't explicitly dismissed.
function CLN:MergeKnownVoicedNpcs()
    if not (self.db and self.db.profile) then return end
    local baked = _G.KnownVoicedNpcsDB
    if not baked then return end

    local wl = self.db.profile.nativeVOWhitelist
    if not wl then wl = {}; self.db.profile.nativeVOWhitelist = wl end
    local dismissed = self.db.profile.nativeVODismissed or {}
    local added = 0

    for name, data in pairs(baked) do
        -- Skip if user explicitly dismissed this NPC
        if not dismissed[name] then
            if not wl[name] then
                wl[name] = true
                added = added + 1
            end
            -- Also add any known IDs
            if data and data.ids then
                for _, id in ipairs(data.ids) do
                    if not wl[id] and not dismissed[id] then
                        wl[id] = true
                    end
                end
            end
        end
    end

    if added > 0 and self.Logger then
        self.Logger:debug("Merged " .. added .. " known voiced NPCs into whitelist", false,
            self.Utils and self.Utils.LogCategories and self.Utils.LogCategories.loader or "misc")
    end
end

--- Record a user-confirmed voiced NPC to the global contributions SavedVariable.
--- Only collects when logNpcTexts is enabled.
---@param npcName string
---@param npcIds table Array of creature IDs
function CLN:ContributeVoicedNpc(npcName, npcIds)
    if not (self.db and self.db.profile and self.db.profile.logNpcTexts) then return end
    if not npcName then return end

    -- Initialize the global SavedVariable table
    if not _G.VoicedNpcContributions then _G.VoicedNpcContributions = {} end
    local contrib = _G.VoicedNpcContributions

    if not contrib[npcName] then
        contrib[npcName] = { ids = {} }
    end
    if not contrib[npcName].ids then contrib[npcName].ids = {} end

    -- Merge any new IDs (normalize to numbers)
    if npcIds then
        local existing = {}
        for _, id in ipairs(contrib[npcName].ids) do existing[tonumber(id) or id] = true end
        for _, id in ipairs(npcIds) do
            local nid = tonumber(id) or id
            if nid and not existing[nid] then
                table.insert(contrib[npcName].ids, nid)
                existing[nid] = true
            end
        end
    end
end
