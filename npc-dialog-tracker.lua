---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

local NpcDialogTracker = {}
ChattyLittleNpc.NpcDialogTracker = NpcDialogTracker

-- remove any new line tags and player identifyable data so that this would fit everyone.
function NpcDialogTracker:cleanText(text)
    text = text:gsub("\n\n", " ")
    text = text:gsub("\r\n", " ")
    text = text:gsub(UnitName("player"), "Hero")
    text = text:gsub(UnitClass("player"), "Hero")
    text = text:gsub(UnitRace("player"), "Hero")
    return text
end

function NpcDialogTracker:ensureNpcInfoInitialized(npcID)
    if not NpcInfoDB[npcID] then
        NpcInfoDB[npcID] = {}
    end

    if not NpcInfoDB[npcID][ChattyLittleNpc.locale] then
        NpcInfoDB[npcID][ChattyLittleNpc.locale] = {
            name = "",
            sex = "",
            race = "",
            quest_greeting = "",
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

function NpcDialogTracker:storeNpcInfo(unitName, gender, race, npcID)
    self:ensureNpcInfoInitialized(npcID)
    NpcInfoDB[npcID][ChattyLittleNpc.locale].name = unitName
    NpcInfoDB[npcID][ChattyLittleNpc.locale].sex = gender
    NpcInfoDB[npcID][ChattyLittleNpc.locale].race = race

    if ChattyLittleNpc.db.profile.printNpcTexts then
        print("------------------------>")
        print("|cff00ff00Npc info collected: \r\n- Id: " .. npcID .. "\r\n- Name: " .. NpcInfoDB[npcID][ChattyLittleNpc.locale].name .. "\r\n- Gender: " ..  NpcInfoDB[npcID][ChattyLittleNpc.locale].sex)
    end
end

function NpcDialogTracker:storeQuestInfo(npcID, questID, eventType, text)
    self:ensureNpcInfoInitialized(npcID)
    if not NpcInfoDB[npcID][ChattyLittleNpc.locale].quests[questID] then
        NpcInfoDB[npcID][ChattyLittleNpc.locale].quests[questID] = {
            quest_detail = "",
            quest_progress = "",
            quest_complete = ""
        }
    end

    text = self:cleanText(text)
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
        print("------------------------>")
        print("|cff00ff00Npc quest collected: \r\n- Npc ID: " .. npcID .. "\r\n- Quest ID: " .. questID .. "\r\n- Quest Detail: ".. NpcInfoDB[npcID][ChattyLittleNpc.locale].quests[questID].quest_detail .. "\r\n- Quest Progress: ".. NpcInfoDB[npcID][ChattyLittleNpc.locale].quests[questID].quest_progress .. "\r\n- Quest Completion: ".. NpcInfoDB[npcID][ChattyLittleNpc.locale].quests[questID].quest_complete .. "\r\n- Quest Greeting: ".. NpcInfoDB[npcID][ChattyLittleNpc.locale].quest_greeting)
    end
end

function NpcDialogTracker:storeGossipOptionsInfo(npcID, gossipText)
    self:ensureNpcInfoInitialized(npcID)
    local text = self:cleanText(gossipText)
    if not tContains(NpcInfoDB[npcID][ChattyLittleNpc.locale].gossipOptions, text) then
        table.insert(NpcInfoDB[npcID][ChattyLittleNpc.locale].gossipOptions, text)
        if ChattyLittleNpc.db.profile.printNpcTexts then
            print("------------------------>")
            print("|cff00ff00Npc gossip option collected: \r\n-Npc ID: " .. npcID .. "\r\n- Gossip text: " .. text)
        end
    end
end

function NpcDialogTracker:ensureUnitInfoInitialized(unitID)
    if not UnitInfoDB[unitID] then
        UnitInfoDB[unitID] = {}
    end

    if not UnitInfoDB[unitID][ChattyLittleNpc.locale] then
        UnitInfoDB[unitID][ChattyLittleNpc.locale] = {
            unitType = "",
            unitName = "",
            unitText = "",
            quests = {}
        }
    end
end

function NpcDialogTracker:storeUnitInfo(unitID, unitName, unitText, unitType, params)
    if not unitText then
        unitText = ""
    end
    params = params or {}
    local questId = params.questId
    local questText = params.questText or ""
    local eventType = params.eventType or ""

    self:ensureUnitInfoInitialized(unitID)
    UnitInfoDB[unitID][ChattyLittleNpc.locale].unitName = unitName
    UnitInfoDB[unitID][ChattyLittleNpc.locale].unitType = unitType
    UnitInfoDB[unitID][ChattyLittleNpc.locale].unitText = self:cleanText(unitText)

    if questId and questText then
        if not UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId] then
            UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId]= {
                quest_detail = "",
                quest_progress = "",
                quest_complete = ""
            }
        end

        if eventType == "QUEST_DETAIL" then
            UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId].quest_detail = self:cleanText(questText)
        elseif eventType == "QUEST_PROGRESS" then
            UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId].quest_progress = self:cleanText(questText)
        elseif eventType == "QUEST_COMPLETE" then
            UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId].quest_complete = self:cleanText(questText)
        end
    end

    if ChattyLittleNpc.db.profile.printNpcTexts then
        print("------------------------>")
        print("|cff00ff00Unit info collected: \r\n- Unit ID: " .. unitID .."\r\n- Unit Name: " .. UnitInfoDB[unitID][ChattyLittleNpc.locale].unitName .. "\r\n- Unit Type: " .. UnitInfoDB[unitID][ChattyLittleNpc.locale].unitType .. "\r\n- Unit Text: \r\n" .. UnitInfoDB[unitID][ChattyLittleNpc.locale].unitText)
        if questId then
            print("|cff00ff00" .. unitType .. " Quests: \r\n- Quest ID: " .. questId .. "\r\n- Quest Detail: " .. UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId].quest_detail .. "\r\n- Quest Progress: " .. UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId].quest_progress .. "\r\n- Quest Completion: " .. UnitInfoDB[unitID][ChattyLittleNpc.locale].quests[questId].quest_complete)
        end
    end
    ChattyLittleNpc.currentItemInfo.ItemID = nil
    ChattyLittleNpc.currentItemInfo.ItemName = nil
    ChattyLittleNpc.currentItemInfo.ItemText = nil
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
    local unitName, gender, race, unitGuid, unitType, unitId = ChattyLittleNpc:getUnitInfo("npc")
    if unitGuid and unitType == "Creature" then -- QUESTS FROM NPCS
        self:storeNpcInfo(unitName, gender, race, unitId)
        self:storeQuestInfo(unitId, questID, event, text)
    elseif unitType == "Player" then -- POPUP QUESTS
        self:storeNpcInfo("Player", "", "", 0)
        self:storeQuestInfo(0, questID, event, text)
    else -- HANDLE QUESTS FROM INVENTORY ITEMS
        if ChattyLittleNpc.currentItemInfo.ItemID and ChattyLittleNpc.currentItemInfo.ItemName and ChattyLittleNpc.currentItemInfo.ItemText then
            ChattyLittleNpc.currentItemInfo.ItemName = select(1, C_Item.GetItemInfo(ChattyLittleNpc.currentItemInfo.ItemID))
            self:storeUnitInfo(ChattyLittleNpc.currentItemInfo.ItemID, ChattyLittleNpc.currentItemInfo.ItemName, ChattyLittleNpc.currentItemInfo.ItemText , "Item", { questId = questID, questText = text, eventType = event } )
        end
    end
end

function NpcDialogTracker:HandleItemTextReady()
    if ChattyLittleNpc.useNamespaces then
        C_Timer.After(0.5, function ()
            ChattyLittleNpc.currentItemInfo.ItemName = ItemTextGetItem()
            ChattyLittleNpc.currentItemInfo.ItemText = ItemTextGetText()
            local unitGuid = UnitGUID('npc')
            if ChattyLittleNpc.currentItemInfo.ItemName and ChattyLittleNpc.currentItemInfo.ItemText and unitGuid then
                local unitType = select(1, string.split('-', unitGuid))
                if unitType == "Item" then
                    self:storeUnitInfo(ChattyLittleNpc.currentItemInfo.ItemID, ChattyLittleNpc.currentItemInfo.ItemName, ChattyLittleNpc.currentItemInfo.ItemText, unitType)
                else 
                    local itemID = select(6, string.split("-", unitGuid));
                    self:storeUnitInfo(itemID, ChattyLittleNpc.currentItemInfo.ItemName, ChattyLittleNpc.currentItemInfo.ItemText, unitType)
                    return
                end
            end
        end)
    else
        self:ScheduleTimer(0.5, function ()
            ChattyLittleNpc.currentItemInfo.ItemName = ItemTextGetItem()
            ChattyLittleNpc.currentItemInfo.ItemText = ItemTextGetText()
            local unitGuid = UnitGUID('npc')
            if ChattyLittleNpc.currentItemInfo.ItemName and ChattyLittleNpc.currentItemInfo.ItemText and unitGuid then
                local unitType = select(1, string.split('-', unitGuid))
                if unitType == "Item" then
                    self:storeUnitInfo(ChattyLittleNpc.currentItemInfo.ItemID, ChattyLittleNpc.currentItemInfo.ItemName, ChattyLittleNpc.currentItemInfo.ItemText, unitType)
                else 
                    local itemID = select(6, string.split("-", unitGuid));
                    self:storeUnitInfo(itemID, ChattyLittleNpc.currentItemInfo.ItemName, ChattyLittleNpc.currentItemInfo.ItemText, unitType)
                    return
                end
            end
        end)
    end
end

function NpcDialogTracker:HandleGossipText()
    -- THIS IS FOR INTERACTING WITH NPCS
    local unitName, gender, race, unitGuid, unitType, unitId = ChattyLittleNpc:getUnitInfo("npc")
    local gossipText = C_GossipInfo.GetText()
    if UnitExists("npc") then
        self:storeNpcInfo(unitName, gender, race, unitId)
        if gossipText then
            self:storeGossipOptionsInfo(unitId, gossipText)
        end
    end
    -- THIS IS FOR INTERACTING WITH GAME OBJECTS
    if unitGuid then
        if unitType == "GameObject" then
            ChattyLittleNpc.NpcDialogTracker:storeUnitInfo(unitId, unitName, gossipText, unitType)
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