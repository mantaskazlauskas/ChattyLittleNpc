---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class NpcDialogTracker
local NpcDialogTracker = {}
CLN.NpcDialogTracker = NpcDialogTracker

function NpcDialogTracker:EnsureNpcInfoInitialized(npcID)
    if (not NpcInfoDB) then
        CLN:Print("Initializing NpcInfoDB")
        NpcInfoDB = {}
    end

    if (not NpcInfoDB[npcID]) then
        NpcInfoDB[npcID] = {}
    end

    if (not NpcInfoDB[npcID][CLN.locale]) then
        NpcInfoDB[npcID][CLN.locale] = {
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

    if (not NpcInfoDB[npcID][CLN.locale].quests) then
        NpcInfoDB[npcID][CLN.locale].quests = {}
    end

    if (not NpcInfoDB[npcID][CLN.locale].gossipOptions) then
        NpcInfoDB[npcID][CLN.locale].gossipOptions = {}
    end
end

function NpcDialogTracker:StoreNpcInfo(unitName, gender, race, npcID)
    CLN.Utils:LogDebug("Storing npc info for NPC ID: " .. npcID)
    self:EnsureNpcInfoInitialized(npcID)
    NpcInfoDB[npcID][CLN.locale].name = unitName

    if (NpcInfoDB[npcID][CLN.locale].sex and NpcInfoDB[npcID][CLN.locale].sex ~= gender) then
        NpcInfoDB[npcID][CLN.locale].hasMultipleGenders = true
    end

    NpcInfoDB[npcID][CLN.locale].sex = gender
    NpcInfoDB[npcID][CLN.locale].race = race
    NpcInfoDB[npcID][CLN.locale].zone = GetZoneText()
    NpcInfoDB[npcID][CLN.locale].subzone = GetSubZoneText()

    if (CLN.db.profile.printNpcTexts) then
        CLN:Print("|cff00ff00Npc info collected: \r\n- Id: " .. npcID .. "\r\n- Name: " .. NpcInfoDB[npcID][CLN.locale].name .. "\r\n- Gender: " ..  NpcInfoDB[npcID][CLN.locale].sex)
    end
end

function NpcDialogTracker:StoreQuestInfo(npcID, questID, eventType, text)
    self:EnsureNpcInfoInitialized(npcID)
    if (not NpcInfoDB[npcID][CLN.locale].quests[questID]) then
        NpcInfoDB[npcID][CLN.locale].quests[questID] = {
            quest_detail = "",
            quest_progress = "",
            quest_complete = ""
        }
    end

    text = CLN.Utils:CleanTextV2(text)
    if (eventType == "QUEST_DETAIL") then
        NpcInfoDB[npcID][CLN.locale].quests[questID].quest_detail = text
    elseif (eventType == "QUEST_PROGRESS") then
        NpcInfoDB[npcID][CLN.locale].quests[questID].quest_progress = text
    elseif (eventType == "QUEST_COMPLETE") then
        NpcInfoDB[npcID][CLN.locale].quests[questID].quest_complete = text
    elseif (eventType == "QUEST_GREETING") then
        NpcInfoDB[npcID][CLN.locale].quest_greeting = text
    end

    if (CLN.db.profile.printNpcTexts) then
        CLN:Print("|cff00ff00Npc quest collected: \r\n- Npc ID: " .. npcID .. "\r\n- Quest ID: " .. questID .. "\r\n- Quest Detail: ".. NpcInfoDB[npcID][CLN.locale].quests[questID].quest_detail .. "\r\n- Quest Progress: ".. NpcInfoDB[npcID][CLN.locale].quests[questID].quest_progress .. "\r\n- Quest Completion: ".. NpcInfoDB[npcID][CLN.locale].quests[questID].quest_complete .. "\r\n- Quest Greeting: ".. NpcInfoDB[npcID][CLN.locale].quest_greeting)
    end
end

function NpcDialogTracker:StoreGossipOptionsInfo(npcID, gossipText, overwrite, oldHash, gender)
    CLN.Utils:LogDebug("Storing gossip options for Npc ID: " .. npcID)
    self:EnsureNpcInfoInitialized(npcID)

    if (not NpcInfoDB[npcID][CLN.locale].gossipOptions) then
        NpcInfoDB[npcID][CLN.locale].gossipOptions = {}
    end

    local textForHashing = CLN.Utils:CleanText(gossipText)
    local gossip_id = CLN.MD5:GenerateHash(npcID .. textForHashing)
    if (gender) then
        gossip_id = gossip_id .. "_" .. gender
    end
    local hashRemainedTheSame = oldHash == gossip_id

    if (not NpcInfoDB[npcID][CLN.locale].gossipOptions[gossip_id] or overwrite) then
        if (overwrite) then
            CLN.Utils:LogDebug("Overwriting gossip option for Npc ID: " .. npcID .. " with hash: " .. gossip_id)
        else
            CLN.Utils:LogDebug("Storing new gossip option for Npc ID: " .. npcID .. " with hash: " .. gossip_id)
        end

        local text = CLN.Utils:CleanTextV2(gossipText)
        NpcInfoDB[npcID][CLN.locale].gossipOptions[gossip_id] = text
        if (oldHash and not hashRemainedTheSame and NpcInfoDB[npcID][CLN.locale].gossipOptions[oldHash]) then
            CLN.Utils:LogDebug("Removing old gossip option with hash: " .. oldHash .. " for Npc ID: " .. npcID)
            NpcInfoDB[npcID][CLN.locale].gossipOptions[oldHash] = nil
        end

        if (CLN.db.profile.printNpcTexts) then
            CLN:Print("|cff00ff00Npc gossip option collected: \r\n- Npc ID: " .. npcID .. "\r\n- Gossip text: " .. text .. "\r\n- Hash: " .. gossip_id)
        end
    end
end

function NpcDialogTracker:EnsureUnitInfoInitialized(unitID)
    if (not UnitInfoDB) then
        CLN:Print("Initializing UnitInfoDB")
        UnitInfoDB = {}
    end
    if (not UnitInfoDB[unitID]) then
        UnitInfoDB[unitID] = {}
    end

    if (not UnitInfoDB[unitID][CLN.locale]) then
        UnitInfoDB[unitID][CLN.locale] = {
            unitType = "",
            unitName = "",
            unitTexts = {},
            quests = {}
        } 
    end
end

function NpcDialogTracker:StoreUnitInfo(unitID, unitName, unitText, unitType, params)
    CLN.Utils:LogDebug("Storing unit info for Unit ID: " .. unitID)
    params = params or {}
    local questId = params.questId
    local questText = params.questText or ""
    local eventType = params.eventType or ""

    self:EnsureUnitInfoInitialized(unitID)
    UnitInfoDB[unitID][CLN.locale].unitName = unitName
    UnitInfoDB[unitID][CLN.locale].unitType = unitType
    local textHash = nil
    if (unitID and unitText) then
        local textForHashing = CLN.Utils:CleanText(unitText)
        textHash = CLN.MD5:GenerateHash(unitID .. textForHashing)

        unitText = CLN.Utils:CleanTextV2(unitText)
        UnitInfoDB[unitID][CLN.locale].unitTexts[textHash] = unitText
    end

    if (questId and questText) then
        if (not UnitInfoDB[unitID][CLN.locale].quests[questId]) then
            UnitInfoDB[unitID][CLN.locale].quests[questId]= {
                quest_detail = "",
                quest_progress = "",
                quest_complete = ""
            }
        end
        questText = CLN.Utils:CleanText(questText)

        if (eventType == "QUEST_DETAIL") then
            UnitInfoDB[unitID][CLN.locale].quests[questId].quest_detail = questText
        elseif (eventType == "QUEST_PROGRESS") then
            UnitInfoDB[unitID][CLN.locale].quests[questId].quest_progress = questText
        elseif (eventType == "QUEST_COMPLETE") then
            UnitInfoDB[unitID][CLN.locale].quests[questId].quest_complete = questText
        end
    end

    if (CLN.db.profile.printNpcTexts) then
        CLN:Print("|cff00ff00Unit info collected: \r\n- Unit ID: " .. unitID .."\r\n- Unit Name: " .. UnitInfoDB[unitID][CLN.locale].unitName .. "\r\n- Unit Type: " .. UnitInfoDB[unitID][CLN.locale].unitType)
        if (textHash) then
            CLN:Print("|cff00ff00Unit info collected: \r\n- Unit Text: " .. UnitInfoDB[unitID][CLN.locale].unitTexts[textHash] .. "\r\n- Unit Text Hash: " .. textHash)
        end

        if (questId) then
            CLN:Print("|cff00ff00" .. unitType .. " Quests: \r\n- Quest ID: " .. questId .. "\r\n- Quest Detail: " .. UnitInfoDB[unitID][CLN.locale].quests[questId].quest_detail .. "\r\n- Quest Progress: " .. UnitInfoDB[unitID][CLN.locale].quests[questId].quest_progress .. "\r\n- Quest Completion: " .. UnitInfoDB[unitID][CLN.locale].quests[questId].quest_complete)
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
    local unitName, gender, race, unitGuid, unitType, unitId = CLN:GetUnitInfo("npc")
    if (unitGuid and unitType == "Creature") then -- QUESTS FROM NPCS
        self:StoreNpcInfo(unitName, gender, race, unitId)
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
    local unitGuid = UnitGUID('npc')
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
    local unitName, gender, race, unitGuid, unitType, unitId = CLN:GetUnitInfo("npc")
    local gossipText = C_GossipInfo.GetText()
    if (UnitExists("npc")) then
        self:StoreNpcInfo(unitName, gender, race, unitId)
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
    if (not NpcInfoDB[npcTooltipInfo.Id]) then
        return
    end

    local npcInfo = NpcInfoDB[npcTooltipInfo.Id][CLN.locale]
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
    f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
    f:SetScript("OnEvent", function()
        if not UnitIsPlayer("mouseover") then
            local unitGuid = UnitGUID("mouseover")
            if (unitGuid) then
                local unitID = select(6, strsplit("-", unitGuid))
                local unitIdAsNumber = tonumber(unitID)
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
                        -- Remove color codes from the text
                        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                        table.insert(npcTooltipInfo.tooltip_info, text)
                    end
                    lineIndex = lineIndex + 1
                end

                if (CLN.db.profile.logNpcTexts) then
                    NpcDialogTracker:HandleNpcTooltip(npcTooltipInfo)
                end
            end
        end
    end)
end
