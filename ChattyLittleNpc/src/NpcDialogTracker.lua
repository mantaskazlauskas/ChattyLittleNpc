---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class NpcDialogTracker
local NpcDialogTracker = {}
CLN.NpcDialogTracker = NpcDialogTracker

--- This client's entry for an NPC (NpcInfoDB[locale][npcID], see
--- Core/CollectedData.lua), created with empty fields when missing.
---@return table info
function NpcDialogTracker:EnsureNpcInfoInitialized(npcID)
    if (not NpcInfoDB) then
    CLN.Logger:info("Initializing NpcInfoDB", false, CLN.Utils.LogCategories.misc)
        NpcInfoDB = {}
    end

    npcID = CLN.CollectedData.ToId(npcID) or npcID
    local npcs = CLN.CollectedData.Bucket(NpcInfoDB, CLN.locale)
    if (not npcs[npcID]) then
        npcs[npcID] = {
            name = "",
            sex = "",
            hasMultipleGenders = false,
            race = "",
            quest_greeting = "",
            zone = "",
            subzone = "",
            quests = {},
            gossipOptions = {}
        }
    end

    local info = npcs[npcID]
    if (not info.quests) then
        info.quests = {}
    end

    if (not info.gossipOptions) then
        info.gossipOptions = {}
    end
    return info
end

function NpcDialogTracker:StoreNpcInfo(unitName, gender, race, npcID, creatureType)
    CLN.Logger:debug("Storing npc info NPC ID=" .. tostring(npcID), false, CLN.Utils.LogCategories.loader)
    local info = self:EnsureNpcInfoInitialized(npcID)
    info.name = unitName

    -- New entries start with sex = "", which is not a different gender
    local previousSex = info.sex
    if (previousSex and previousSex ~= "" and previousSex ~= gender) then
        info.hasMultipleGenders = true
    end

    info.sex = gender

    -- Read the NPC's model once: the model file ID is stored with the NPC and
    -- identifies the race when UnitRace() is empty (as it is for NPCs). The
    -- display ID isn't stored: the client doesn't reliably expose it.
    local fileId, displayId
    if (npcID ~= 0 and CLN.NpcRaceLookup) then
        fileId, displayId = CLN.NpcRaceLookup:GetUnitModelFileID("npc")
    end
    if (fileId) then
        info.modelFileId = fileId
    end

    -- Unknown models yield "", and an empty result never overwrites a known race.
    if (npcID ~= 0 and (not race or race == "") and CLN.NpcRaceLookup) then
        race = CLN.NpcRaceLookup:GetRaceForFileID(fileId)
        if (race == "" and fileId) then
            CLN.NpcRaceLookup:RecordUnknown(fileId, {
                npcId = npcID,
                name = unitName,
                displayId = displayId,
                creatureType = creatureType,
            })
        end
    end
    if (race and race ~= "") then
        info.race = race
    end
    info.zone = GetZoneText()
    info.subzone = GetSubZoneText()
    if creatureType and creatureType ~= "" then
        info.creatureType = creatureType
    end

    if CLN.db.profile.printNpcTexts then
        local highlight = function(value)
            return "|cffc080ff" .. ((value and value ~= "") and tostring(value) or "?") .. "|r" -- light purple
        end
        -- Model file ID from this read ("?" = not collected this time)
        CLN.Logger:info("Npc info collected: Id=" .. npcID .. ", Name=" .. info.name .. ", Gender=" .. highlight(info.sex) .. ", Race=" .. highlight(info.race)
            .. ", ModelFileId=" .. highlight(fileId), true, CLN.Utils.LogCategories.ui)
    end
end

function NpcDialogTracker:StoreQuestInfo(npcID, questID, eventType, text)
    local info = self:EnsureNpcInfoInitialized(npcID)
    if (not info.quests[questID]) then
        info.quests[questID] = {
            quest_detail = "",
            quest_progress = "",
            quest_complete = ""
        }
    end

    text = CLN.Utils:CleanTextV2(text)
    if (eventType == "QUEST_DETAIL") then
        info.quests[questID].quest_detail = text
    elseif (eventType == "QUEST_PROGRESS") then
        info.quests[questID].quest_progress = text
    elseif (eventType == "QUEST_COMPLETE") then
        info.quests[questID].quest_complete = text
    elseif (eventType == "QUEST_GREETING") then
        info.quest_greeting = text
    end

    if CLN.db.profile.printNpcTexts then
        local s = info.quests[questID]
        CLN.Logger:info("Npc quest collected: NpcID=" .. npcID .. ", QuestID=" .. questID ..
            ", Detail=" .. s.quest_detail .. ", Progress=" .. s.quest_progress .. ", Complete=" .. s.quest_complete .. ", Greeting=" .. (info.quest_greeting or ""), true, CLN.Utils.LogCategories.ui)
    end
end

function NpcDialogTracker:StoreGossipOptionsInfo(npcID, gossipText, overwrite, oldHash, gender)
    CLN.Logger:debug("Storing gossip options NPC ID=" .. tostring(npcID), false, CLN.Utils.LogCategories.loader)
    local info = self:EnsureNpcInfoInitialized(npcID)

    local textForHashing = CLN.Utils:CleanTextForHash(gossipText)
    local gossip_id = CLN.MD5:GenerateHash(npcID .. textForHashing)
    if (gender) then
        gossip_id = gossip_id .. "_" .. gender
    end
    local hashRemainedTheSame = oldHash == gossip_id

    if (not info.gossipOptions[gossip_id] or overwrite) then
        if (overwrite) then
            CLN.Logger:debug("Overwriting gossip option NPC ID=" .. tostring(npcID) .. " hash=" .. tostring(gossip_id), false, CLN.Utils.LogCategories.loader)
        else
            CLN.Logger:debug("Storing new gossip option NPC ID=" .. tostring(npcID) .. " hash=" .. tostring(gossip_id), false, CLN.Utils.LogCategories.loader)
        end

        local text = CLN.Utils:CleanTextV2(gossipText)
        info.gossipOptions[gossip_id] = text
        if (oldHash and not hashRemainedTheSame and info.gossipOptions[oldHash]) then
            CLN.Logger:debug("Removing old gossip option NPC ID=" .. tostring(npcID) .. " oldHash=" .. tostring(oldHash), false, CLN.Utils.LogCategories.loader)
            info.gossipOptions[oldHash] = nil
        end

        if CLN.db.profile.printNpcTexts then
            CLN.Logger:info("Npc gossip option collected: NpcID=" .. npcID .. ", Hash=" .. gossip_id .. ", Text=" .. text, true, CLN.Utils.LogCategories.ui)
        end
    end
end

--- This client's entry for an item or game object (UnitInfoDB[locale][unitID]),
--- created with empty fields when missing. Ids are stored as numbers: a book's
--- id comes from its GUID as a string, and "123" and 123 are different keys.
---@return table info
function NpcDialogTracker:EnsureUnitInfoInitialized(unitID)
    if (not UnitInfoDB) then
    CLN.Logger:info("Initializing UnitInfoDB", false, CLN.Utils.LogCategories.misc)
        UnitInfoDB = {}
    end

    unitID = CLN.CollectedData.ToId(unitID) or unitID
    local units = CLN.CollectedData.Bucket(UnitInfoDB, CLN.locale)
    if (not units[unitID]) then
        units[unitID] = {
            unitType = "",
            unitName = "",
            unitTexts = {},
            quests = {}
        }
    end
    return units[unitID]
end

function NpcDialogTracker:StoreUnitInfo(unitID, unitName, unitText, unitType, params)
    CLN.Logger:debug("Storing unit info UnitID=" .. tostring(unitID), false, CLN.Utils.LogCategories.loader)
    params = params or {}
    local questId = params.questId
    local questText = params.questText or ""
    local eventType = params.eventType or ""

    local info = self:EnsureUnitInfoInitialized(unitID)
    info.unitName = unitName
    info.unitType = unitType
    local textHash = nil
    if (unitID and unitText) then
        local textForHashing = CLN.Utils:CleanTextForHash(unitText)
        textHash = CLN.MD5:GenerateHash(unitID .. textForHashing)

        unitText = CLN.Utils:CleanTextV2(unitText)
        info.unitTexts[textHash] = unitText
    end

    if (questId and questText) then
        if (not info.quests[questId]) then
            info.quests[questId]= {
                quest_detail = "",
                quest_progress = "",
                quest_complete = ""
            }
        end
        questText = CLN.Utils:CleanTextForHash(questText)

        if (eventType == "QUEST_DETAIL") then
            info.quests[questId].quest_detail = questText
        elseif (eventType == "QUEST_PROGRESS") then
            info.quests[questId].quest_progress = questText
        elseif (eventType == "QUEST_COMPLETE") then
            info.quests[questId].quest_complete = questText
        end
    end

    if CLN.db.profile.printNpcTexts then
        CLN.Logger:info("Unit info collected: UnitID=" .. unitID .. ", Name=" .. info.unitName .. ", Type=" .. info.unitType, true, CLN.Utils.LogCategories.ui)
        if (textHash) then
            CLN.Logger:info("Unit text collected: Text=" .. info.unitTexts[textHash] .. ", Hash=" .. textHash, true, CLN.Utils.LogCategories.ui)
        end
        if (questId) then
            local q = info.quests[questId]
            CLN.Logger:info(unitType .. " Quest: ID=" .. questId .. ", Detail=" .. q.quest_detail .. ", Progress=" .. q.quest_progress .. ", Complete=" .. q.quest_complete, true, CLN.Utils.LogCategories.ui)
        end
    end
end

function NpcDialogTracker:HandleQuestTexts(event)
    local questID = GetQuestID()
    local text
    if (event == "QUEST_DETAIL") then
        text = GetQuestText()
    elseif (event == "QUEST_PROGRESS") then
        text = GetProgressText()
    elseif (event == "QUEST_COMPLETE") then
        text = GetRewardText()
    elseif (event == "QUEST_GREETING") then
        text = GetGreetingText()
    end

    -- QUESTS FROM NPCS
    local unitName, gender, race, unitGuid, unitType, unitId, creatureType = CLN:GetUnitInfo("npc")
    if (unitGuid and unitType == "Creature") then -- QUESTS FROM NPCS
        self:StoreNpcInfo(unitName, gender, race, unitId, creatureType)
        self:StoreQuestInfo(unitId, questID, event, text)
    elseif (unitType == "Player") then -- POPUP QUESTS
        self:StoreNpcInfo("Player", "", "", 0)
        self:StoreQuestInfo(0, questID, event, text)
    elseif (unitType == "GameObject") then -- Quests from GameObjects
        self:StoreUnitInfo(unitId, unitName, "", unitType, { questId = questID, questText = text, eventType = event } )
    else -- HANDLE QUESTS FROM INVENTORY ITEMS
        if (CLN.currentItemInfo.ItemID and CLN.currentItemInfo.ItemName and (CLN.currentItemInfo.ItemText or text)) then
            self:StoreUnitInfo(CLN.currentItemInfo.ItemID, CLN.currentItemInfo.ItemName, CLN.currentItemInfo.ItemText , "Item", { questId = questID, questText = text, eventType = event } )
        end
    end
end

function NpcDialogTracker:HandleItemTextReady(itemId, itemText, itemName)
    -- Desecret UnitGUID against potential secret values (WoW 12.0+).
    local unitGuid
    do
        local raw = UnitGUID('npc')
        if type(raw) == "string" then
            local blocked
            unitGuid, blocked = CLN.Utils.Desecret(raw)
            if blocked then
                CLN.Logger:warn("Secret value blocked: UnitGUID in HandleItemTextReady",
                    false, CLN.Utils.LogCategories.secrets)
            end
        end
    end
    if (itemName and itemText and unitGuid) then
        local unitType = select(1, string.split('-', unitGuid))
        if (unitType == "Item") then
            self:StoreUnitInfo(itemId, itemName, itemText, unitType)
        else
            local itemID = select(6, string.split("-", unitGuid));
            self:StoreUnitInfo(itemID, itemName, itemText, unitType)
            return
        end
    end
end

function NpcDialogTracker:HandleGossipText()
    -- THIS IS FOR INTERACTING WITH NPCS
    local unitName, gender, race, unitGuid, unitType, unitId, creatureType = CLN:GetUnitInfo("npc")
    local gossipText = C_GossipInfo.GetText()
    if (UnitExists("npc")) then
        self:StoreNpcInfo(unitName, gender, race, unitId, creatureType)
        if (gossipText) then
            local overwrite = CLN.db.profile.overwriteExistingGossipValues
            self:StoreGossipOptionsInfo(unitId, gossipText, overwrite, nil, gender)
        end
    end
    -- THIS IS FOR INTERACTING WITH GAME OBJECTS
    if (unitGuid) then
        if unitType == "GameObject" then
            CLN.NpcDialogTracker:StoreUnitInfo(unitId, unitName, gossipText, unitType)
        end
    end
end

function NpcDialogTracker:HandleNpcTooltip(npcTooltipInfo)
    local npcInfo = CLN.CollectedData.Get(NpcInfoDB, npcTooltipInfo.Id)
    if not npcInfo then return end
    if (not npcInfo.tooltip_info) then
        npcInfo.tooltip_info = npcTooltipInfo.tooltip_info
    end
end

function NpcDialogTracker:InitializeTables()
    if (not NpcInfoDB) then
        NpcInfoDB = {}
    end
    if (not UnitInfoDB) then
        UnitInfoDB = {}
    end
end

function NpcDialogTracker:GatherTooltipInfo()
    local f = CreateFrame("Frame")
    local lastGuid = nil
    f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    f:SetScript("OnEvent", function()
        -- pcall guards against tainted/secret UnitGUID values (WoW 11.x)
        pcall(function()
            if UnitIsPlayer("mouseover") then return end
            local unitGuid = UnitGUID("mouseover")
            if not unitGuid then return end
            -- Skip if we already processed this exact unit
            if unitGuid == lastGuid then return end
            lastGuid = unitGuid

            local unitID = select(6, strsplit("-", unitGuid))
            local unitIdAsNumber = tonumber(unitID)
            -- Early-out: skip tooltip scanning if NPC isn't tracked
            if not CLN.CollectedData.Get(NpcInfoDB, unitIdAsNumber) then return end

            local npcTooltipInfo = {
                Id = unitIdAsNumber,
                tooltip_info = {}
            }

            local lineIndex = 1
            while true do
                local line = _G["GameTooltipTextLeft" .. lineIndex]
                if not line then
                    break
                end
                local text = line:GetText()
                if text then
                    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    table.insert(npcTooltipInfo.tooltip_info, text)
                end
                lineIndex = lineIndex + 1
            end

            if CLN.db.profile.logNpcTexts then
                NpcDialogTracker:HandleNpcTooltip(npcTooltipInfo)
            end
        end)
    end)
end
