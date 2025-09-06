---@class ChattyLittleNpc: table, AceAddon-3.0, AceConsole-3.0, AceEvent-3.0
local CLN = LibStub("AceAddon-3.0"):NewAddon("ChattyLittleNpc", "AceConsole-3.0", "AceEvent-3.0")

---@class EventHandler
CLN.EventHandler = LibStub("AceAddon-3.0"):GetAddon("EventHandler")
CLN.EventHandler:SetChattyLittleNpcReference(CLN)

---@class Options
CLN.Options = LibStub("AceAddon-3.0"):GetAddon("Options")
CLN.Options:SetChattyLittleNpcReference(CLN)

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

local defaults = {
    profile = {
        autoPlayVoiceovers = true,
        playVoiceoverAfterDelay = 0,
        printMissingFiles = false,
        logNpcTexts = false,
        printNpcTexts = false,
    -- Mirror addon logs to the chat frame (the Logs window always captures). Off by default to keep chat clean.
    logToChat = false,
        overwriteExistingGossipValues = false,
        showGossipEditor = false,
        showReplayFrame = true,
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
    frameSize = { width = 310 + 165, height = 165 },
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
    disableCameraAnimations = false
    ,
    -- Per Edit Mode layout overrides (keyed by layoutName)
    editModeLayouts = {}
    }
}

function CLN:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ChattyLittleNpcDB", defaults, true)

    -- Ensure questPlaybackMode always has a valid value
    local m = self.db.profile.questPlaybackMode
    if m ~= "queue" and m ~= "stopOnClose" and m ~= "manual" then
        self.db.profile.questPlaybackMode = "queue"
    end

    self.locale = GetLocale()
    self.gameVersion = select(4, GetBuildInfo())
    self.useNamespaces = self.gameVersion >= 90000 -- namespaces were added in starting Shadowlands

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

    self.PlayButton:AttachQuestLogAndDetailsButtons()

    if type(QuestMapFrame_UpdateAll) == "function" then
        hooksecurefunc("QuestMapFrame_UpdateAll", self.PlayButton.UpdatePlayButton)
    end

    if (QuestMapFrame) then
        QuestMapFrame:HookScript("OnShow", self.PlayButton.UpdatePlayButton)
        QuestMapFrame.DetailsFrame:HookScript("OnHide", self.PlayButton.HidePlayButton)
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
                self:_SyncLegacyQuestPlaybackFlags()
            end
        end
        -- Use dot-notation per CallbackHandler: self is the addon receiving callbacks
        self.db.RegisterCallback(self, "OnProfileChanged", function()
            -- Rebuild UI scaling and visibility on profile switch
            applyKey("queueTextScale")
            applyKey("compactMode")
            applyKey("showReplayFrame")
            applyKey("debugNoAnim")
        end)
        self.db.RegisterCallback(self, "OnProfileCopied", function()
                    applyKey("queueTextScale"); applyKey("compactMode"); applyKey("showReplayFrame"); applyKey("debugNoAnim"); applyKey("disableCameraAnimations")
        end)
        self.db.RegisterCallback(self, "OnProfileReset", function()
                    applyKey("queueTextScale"); applyKey("compactMode"); applyKey("showReplayFrame"); applyKey("debugNoAnim"); applyKey("disableCameraAnimations")
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
        unitType = select(1, strsplit("-", unitGuid))
        if (unitType == "Creature" or unitType == "Vehicle" or unitType == "GameObject") then
            local idString = select(6, strsplit("-", unitGuid))
            unitId = tonumber(idString)
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

            local addon = LibStub("AceAddon-3.0"):GetAddon(voiceoverPackName, true)
            if addon then
                self.VoiceoverPacks[voiceoverPackName] = addon
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
    local npcId = select(6, self:GetUnitInfo("npc"))
    local gender = select(2, self:GetUnitInfo("npc"))
    
    if (questId > 0) then
        C_Timer.After(self.db.profile.playVoiceoverAfterDelay, function()
            self.VoiceoverPlayer:PlayQuestSound(questId, questPhase, npcId)
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
        C_Timer.After(self.db.profile.playVoiceoverAfterDelay, function()
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

CLN:OnInitialize()