---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local NpcDialogTracker = {}
ChattyLittleNpc.NpcDialogTracker = NpcDialogTracker

function NpcDialogTracker:EnsureNpcInfoInitialized(npcID)
    if not NpcInfoDB[npcID] then
        NpcInfoDB[npcID] = {}
    end

    if not NpcInfoDB[npcID][ChattyLittleNpc.locale] then
        NpcInfoDB[npcID][ChattyLittleNpc.locale] = {
            name = "",
            sex = "",
            hasMultipleGenders = false,
            race = "",
            quest_greeting = "",
            zone = "",
            subZone = "",
            quests = {},
            gossipOptions = {}
        }
    end

    if not NpcInfoDB[npcID][ChattyLittleNpc.locale].quests then
        NpcInfoDB[npcID][ChattyLittleNpc.locale].quests = {}
    end

    if not NpcInfoDB[npcID][ChattyLittleNpc.locale].gossipOptions then
        NpcInfoDB[npcID][ChattyLittleNpc.locale].gossipOptions = {}
    end
end

function NpcDialogTracker:StoreNpcInfo(unitName, gender, race, npcID)
    self:EnsureNpcInfoInitialized(npcID)
    NpcInfoDB[npcID][ChattyLittleNpc.locale].name = unitName
    if NpcInfoDB[npcID][ChattyLittleNpc.locale].sex and NpcInfoDB[npcID][ChattyLittleNpc.locale].sex ~= gender then
        NpcInfoDB[npcID][ChattyLittleNpc.locale].hasMultipleGenders = true
    end
    NpcInfoDB[npcID][ChattyLittleNpc.locale].sex = gender
    NpcInfoDB[npcID][ChattyLittleNpc.locale].race = race
    NpcInfoDB[npcID][ChattyLittleNpc.locale].zone = GetZoneText()
    NpcInfoDB[npcID][ChattyLittleNpc.locale].subzone = GetSubZoneText()

    if ChattyLittleNpc.db.profile.printNpcTexts then
        ChattyLittleNpc:Print("|cff00ff00Npc info collected: \r\n- Id: " .. npcID .. "\r\n- Name: " .. NpcInfoDB[npcID][ChattyLittleNpc.locale].name .. "\r\n- Gender: " ..  NpcInfoDB[npcID][ChattyLittleNpc.locale].sex)
    end
end

function NpcDialogTracker:StoreQuestInfo(npcID, questID, eventType, text)
    self:EnsureNpcInfoInitialized(npcID)
    if not NpcInfoDB[npcID][ChattyLittleNpc.locale].quests[questID] then
        NpcInfoDB[npcID][ChattyLittleNpc.locale].quests[questID] = {
            quest_detail = "",
            quest_progress = "",
            quest_complete = ""
        }
    end

    text = ChattyLittleNpc.Utils:CleanText(text)
    if eventType == "QUEST_DETAIL" then
        NpcInfoDB[npcID][ChattyLittleNpc.locale].quests[questID].quest_detail = text
    elseif eventType == "QUEST_PROGRESS" then
        NpcInfoDB[npcID][ChattyLittleNpc.locale].quests[questID].quest_progress = text
    elseif eventType == "QUEST_COMPLETE" then
        NpcInfoDB[npcID][ChattyLittleNpc.locale].quests[questID].quest_complete = text
    elseif eventType == "QUEST_GREETING" then
        NpcInfoDB[npcID][ChattyLittleNpc.locale].quest_greeting = text
    end

    if ChattyLittleNpc.db.profile.printNpcTexts then
        ChattyLittleNpc:Print("|cff00ff00Npc quest collected: \r\n- Npc ID: " .. npcID .. "\r\n- Quest ID: " .. questID .. "\r\n- Quest Detail: ".. NpcInfoDB[npcID][ChattyLittleNpc.locale].quests[questID].quest_detail .. "\r\n- Quest Progress: ".. NpcInfoDB[npcID][ChattyLittleNpc.locale].quests[questID].quest_progress .. "\r\n- Quest Completion: ".. NpcInfoDB[npcID][ChattyLittleNpc.locale].quests[questID].quest_complete .. "\r\n- Quest Greeting: ".. NpcInfoDB[npcID][ChattyLittleNpc.locale].quest_greeting)
    end
end

function NpcDialogTracker:StoreGossipOptionsInfo(npcID, gossipText)
    self:EnsureNpcInfoInitialized(npcID)

    if not NpcInfoDB[npcID][ChattyLittleNpc.locale].gossipOptions then
        NpcInfoDB[npcID][ChattyLittleNpc.locale].gossipOptions = {}
    end

    local text = ChattyLittleNpc.Utils:CleanText(gossipText)
    local hash = ChattyLittleNpc.MD5:GenerateHash(npcID .. text)
    if not NpcInfoDB[npcID][ChattyLittleNpc.locale].gossipOptions[hash] then
        NpcInfoDB[npcID][ChattyLittleNpc.locale].gossipOptions[hash] = text

        if ChattyLittleNpc.db.profile.printNpcTexts then
            ChattyLittleNpc:Print("|cff00ff00Npc gossip option collected: \r\n-Npc ID: " .. npcID .. "\r\n- Gossip text: " .. text .. "\r\n- Hash: " .. hash)
        end
    end
end

function NpcDialogTracker:EnsureUnitInfoInitialized(unitID)
    if not UnitInfoDB[unitID] then
        UnitInfoDB[unitID] = {}
    end

    if not UnitInfoDB[unitID][ChattyLittleNpc.locale] then
        UnitInfoDB[unitID][ChattyLittleNpc.locale] = {
            unitType = "",
            unitName = "",
            unitTexts = {},
            quests = {}
        } 
    end
end

function NpcDialogTracker:StoreUnitInfo(unitID, unitName, unitText, unitType, params)
    params = params or {}
    local questId = params.questId
    local questText = params.questText or ""
    local eventType = params.eventType or ""

    self:EnsureUnitInfoInitialized(unitID)
    UnitInfoDB[unitID][ChattyLittleNpc.locale].unitName = unitName
    UnitInfoDB[unitID][ChattyLittleNpc.locale].unitType = unitType
    local textHash = nil
    if unitID and unitText then
        unitText = ChattyLittleNpc.Utils:CleanText(unitText)
        textHash = ChattyLittleNpc.MD5:GenerateHash(unitID .. unitText)
        UnitInfoDB[unitID][ChattyLittleNpc.locale].unitTexts[textHash] = unitText
    end

    if questId and questText then
        if not UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId] then
            UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId]= {
                quest_detail = "",
                quest_progress = "",
                quest_complete = ""
            }
        end
        questText = ChattyLittleNpc.Utils:CleanText(questText)

        if eventType == "QUEST_DETAIL" then
            UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId].quest_detail = questText
        elseif eventType == "QUEST_PROGRESS" then
            UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId].quest_progress = questText
        elseif eventType == "QUEST_COMPLETE" then
            UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId].quest_complete = questText
        end
    end

    if ChattyLittleNpc.db.profile.printNpcTexts then
        ChattyLittleNpc:Print("|cff00ff00Unit info collected: \r\n- Unit ID: " .. unitID .."\r\n- Unit Name: " .. UnitInfoDB[unitID][ChattyLittleNpc.locale].unitName .. "\r\n- Unit Type: " .. UnitInfoDB[unitID][ChattyLittleNpc.locale].unitType)
        if textHash then
            ChattyLittleNpc:Print("|cff00ff00Unit info collected: \r\n- Unit Text: " .. UnitInfoDB[unitID][ChattyLittleNpc.locale].unitTexts[textHash] .. "\r\n- Unit Text Hash: " .. textHash)
        end

        if questId then
            ChattyLittleNpc:Print("|cff00ff00" .. unitType .. " Quests: \r\n- Quest ID: " .. questId .. "\r\n- Quest Detail: " .. UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId].quest_detail .. "\r\n- Quest Progress: " .. UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId].quest_progress .. "\r\n- Quest Completion: " .. UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId].quest_complete)
        end
    end
end

function NpcDialogTracker:HandleQuestTexts(event)
    local questID = GetQuestID()
    local text
    if event == "QUEST_DETAIL" then
        text = GetQuestText()
    elseif event == "QUEST_PROGRESS" then
        text = GetProgressText()
    elseif event == "QUEST_COMPLETE" then
        text = GetRewardText()
    elseif event == "QUEST_GREETING" then
        text = GetGreetingText()
    end

    -- QUESTS FROM NPCS
    local unitName, gender, race, unitGuid, unitType, unitId = ChattyLittleNpc:GetUnitInfo("npc")
    if unitGuid and unitType == "Creature" then -- QUESTS FROM NPCS
        self:StoreNpcInfo(unitName, gender, race, unitId)
        self:StoreQuestInfo(unitId, questID, event, text)
    elseif unitType == "Player" then -- POPUP QUESTS
        self:StoreNpcInfo("Player", "", "", 0)
        self:StoreQuestInfo(0, questID, event, text)
    elseif unitType == "GameObject" then -- Quests from GameObjects
        self:StoreUnitInfo(unitId, unitName, "", unitType, { questId = questID, questText = text, eventType = event } )
    else -- HANDLE QUESTS FROM INVENTORY ITEMS
        if ChattyLittleNpc.currentItemInfo.ItemID and ChattyLittleNpc.currentItemInfo.ItemName and (ChattyLittleNpc.currentItemInfo.ItemText or text) then
            self:StoreUnitInfo(ChattyLittleNpc.currentItemInfo.ItemID, ChattyLittleNpc.currentItemInfo.ItemName, ChattyLittleNpc.currentItemInfo.ItemText , "Item", { questId = questID, questText = text, eventType = event } )
        end
    end
end

function NpcDialogTracker:HandleItemTextReady(itemId, itemText, itemName)
    local unitGuid = UnitGUID('npc')
    if itemName and itemText and unitGuid then
        local unitType = select(1, string.split('-', unitGuid))
        if unitType == "Item" then
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
    local unitName, gender, race, unitGuid, unitType, unitId = ChattyLittleNpc:GetUnitInfo("npc")
    local gossipText = C_GossipInfo.GetText()
    if UnitExists("npc") then
        self:StoreNpcInfo(unitName, gender, race, unitId)
        if gossipText then
            self:StoreGossipOptionsInfo(unitId, gossipText)
        end
    end
    -- THIS IS FOR INTERACTING WITH GAME OBJECTS
    if unitGuid then
        if unitType == "GameObject" then
            ChattyLittleNpc.NpcDialogTracker:StoreUnitInfo(unitId, unitName, gossipText, unitType)
        end
    end
end

function NpcDialogTracker:InitializeTables()
    if not NpcInfoDB then
        NpcInfoDB = {}
    end
    if not UnitInfoDB then
        UnitInfoDB = {}
    end
end