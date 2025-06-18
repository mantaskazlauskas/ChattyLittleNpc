---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class Editor
local Editor = {}
CLN.Editor = Editor

Editor.NpcId = nil
Editor.NpcName = nil
Editor.GossipId = nil
Editor.GossipText = nil
Editor.Locale = GetLocale()

-- Create a frame for the editor
Editor.Frame = CreateFrame("Frame", nil, UIParent, "BasicFrameTemplateWithInset")
Editor.Frame:SetSize(450, 600)
Editor.Frame:SetPoint("CENTER")
Editor.Frame:SetMovable(true)
Editor.Frame:EnableMouse(true)
Editor.Frame:RegisterForDrag("LeftButton")
Editor.Frame:SetScript("OnDragStart", Editor.Frame.StartMoving)
Editor.Frame:SetScript("OnDragStop", Editor.Frame.StopMovingOrSizing)

-- Create a title for the frame
Editor.Frame.title = Editor.Frame:CreateFontString(nil, "OVERLAY")
Editor.Frame.title:SetFontObject("GameFontHighlightLarge")
Editor.Frame.title:SetPoint("TOP", 10, -5)
Editor.Frame.title:SetText("Gossip Editor")

-- Create a search box for gossipId
Editor.Frame.gossipIDLabel = Editor.Frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
Editor.Frame.gossipIDLabel:SetPoint("TOPLEFT", 10, -40)
Editor.Frame.gossipIDLabel:SetText("Gossip ID:")

Editor.Frame.gossipIDInput = CreateFrame("EditBox", nil, Editor.Frame, "InputBoxTemplate")
Editor.Frame.gossipIDInput:SetSize(250, 20)
Editor.Frame.gossipIDInput:SetPoint("TOPLEFT", Editor.Frame.gossipIDLabel, "BOTTOMLEFT", 0, -5)
Editor.Frame.gossipIDInput:SetAutoFocus(false)

-- Create a search button for gossipId
Editor.Frame.gossipSearchButton = CreateFrame("Button", nil, Editor.Frame, "GameMenuButtonTemplate")
Editor.Frame.gossipSearchButton:SetSize(100, 25)
Editor.Frame.gossipSearchButton:SetPoint("TOPLEFT", Editor.Frame.gossipIDInput, "BOTTOMLEFT", 0, -5)
Editor.Frame.gossipSearchButton:SetText("Search Gossip")
Editor.Frame.gossipSearchButton:SetScript("OnClick", function()
    Editor.NpcId = nil
    Editor.NpcName = nil
    Editor.Locale = GetLocale()
    Editor.GossipText = "Gossip ID not found."
    Editor.GossipId = Editor.Frame.gossipIDInput:GetText()

    for id, npcData in pairs(NpcInfoDB) do
        if npcData[Editor.Locale] and npcData[Editor.Locale].gossipOptions[Editor.GossipId] then
            Editor.GossipText = npcData[Editor.Locale].gossipOptions[Editor.GossipId]
            Editor.NpcId = id
            Editor.NpcName = npcData[Editor.Locale].name
            break
        end
    end

    Editor.Frame.textInput:SetText(Editor.GossipText)
    Editor.Frame.npcIDLabel:SetText("NPC ID: " .. (Editor.NpcId or "Unknown"))
    Editor.Frame.localeLabel:SetText("Locale: " .. Editor.Locale)
    Editor.Frame.npcNameLabel:SetText("Name: " .. (Editor.NpcName or "Unknown"))
end)

-- Add a variable to keep track of the current position in the result set
Editor.currentResultIndex = 1
Editor.searchResults = {}

-- Create a search box for gossip text
Editor.Frame.gossipTextLabel = Editor.Frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
Editor.Frame.gossipTextLabel:SetPoint("TOPLEFT", Editor.Frame.gossipSearchButton, "BOTTOMLEFT", 0, -10)
Editor.Frame.gossipTextLabel:SetText("Gossip Text:")

Editor.Frame.gossipTextInput = CreateFrame("EditBox", nil, Editor.Frame, "InputBoxTemplate")
Editor.Frame.gossipTextInput:SetSize(250, 20)
Editor.Frame.gossipTextInput:SetPoint("TOPLEFT", Editor.Frame.gossipTextLabel, "BOTTOMLEFT", 0, -5)
Editor.Frame.gossipTextInput:SetAutoFocus(false)

-- Create a search button for gossip text
Editor.Frame.gossipTextSearchButton = CreateFrame("Button", nil, Editor.Frame, "GameMenuButtonTemplate")
Editor.Frame.gossipTextSearchButton:SetSize(100, 25)
Editor.Frame.gossipTextSearchButton:SetPoint("TOPLEFT", Editor.Frame.gossipTextInput, "BOTTOMLEFT", 0, -5)
Editor.Frame.gossipTextSearchButton:SetText("Search Text")
Editor.Frame.gossipTextSearchButton:SetScript("OnClick", function()
    Editor.Locale = GetLocale()
    local searchText = Editor.Frame.gossipTextInput:GetText()
    Editor.searchResults = {}
    Editor.currentResultIndex = 1

    for id, npcData in pairs(NpcInfoDB) do
        if npcData[Editor.Locale] then
            for gossipId, gossipText in pairs(npcData[Editor.Locale].gossipOptions) do
                if string.find(gossipText, searchText) then
                    table.insert(Editor.searchResults, {id = id, gossipId = gossipId, gossipText = gossipText, npcName = npcData[Editor.Locale].name})
                end
            end
        end
    end

    if #Editor.searchResults > 0 then
        local result = Editor.searchResults[Editor.currentResultIndex]
        Editor.GossipText = result.gossipText
        Editor.NpcId = result.id
        Editor.NpcName = result.npcName
        Editor.GossipId = result.gossipId
    else
        Editor.GossipText = "Gossip text not found."
        Editor.NpcId = nil
        Editor.NpcName = nil
        Editor.GossipId = nil
    end

    Editor.Frame.textInput:SetText(Editor.GossipText)
    Editor.Frame.npcIDLabel:SetText("NPC ID: " .. (Editor.NpcId or "Unknown"))
    Editor.Frame.localeLabel:SetText("Locale: " .. Editor.Locale)
    Editor.Frame.npcNameLabel:SetText("Name: " .. (Editor.NpcName or "Unknown"))
    Editor.Frame.resultCountLabel:SetText(Editor.currentResultIndex .. " / " .. #Editor.searchResults)
end)

-- Create a previous button
Editor.Frame.previousButton = CreateFrame("Button", nil, Editor.Frame, "GameMenuButtonTemplate")
Editor.Frame.previousButton:SetSize(100, 25)
Editor.Frame.previousButton:SetPoint("LEFT", Editor.Frame.gossipTextSearchButton, "RIGHT", 0, 0)
Editor.Frame.previousButton:SetText("Previous")
Editor.Frame.previousButton:SetScript("OnClick", function()
    if #Editor.searchResults > 1 then
        Editor.currentResultIndex = Editor.currentResultIndex - 1
        if Editor.currentResultIndex == 0 then
            Editor.currentResultIndex = #Editor.searchResults
        end

        local result = Editor.searchResults[Editor.currentResultIndex]
        Editor.GossipText = result.gossipText
        Editor.NpcId = result.id
        Editor.NpcName = result.npcName
        Editor.GossipId = result.gossipId

        Editor.Frame.textInput:SetText(Editor.GossipText)
        Editor.Frame.npcIDLabel:SetText("NPC ID: " .. (Editor.NpcId or "Unknown"))
        Editor.Frame.localeLabel:SetText("Locale: " .. Editor.Locale)
        Editor.Frame.npcNameLabel:SetText("Name: " .. (Editor.NpcName or "Unknown"))
        Editor.Frame.resultCountLabel:SetText(Editor.currentResultIndex .. " / " .. #Editor.searchResults)
    end
end)

-- Create a skip button
Editor.Frame.skipButton = CreateFrame("Button", nil, Editor.Frame, "GameMenuButtonTemplate")
Editor.Frame.skipButton:SetSize(100, 25)
Editor.Frame.skipButton:SetPoint("LEFT", Editor.Frame.previousButton, "RIGHT", 0, 0)
Editor.Frame.skipButton:SetText("Next")
Editor.Frame.skipButton:SetScript("OnClick", function()
    if #Editor.searchResults > 0 then
        Editor.currentResultIndex = Editor.currentResultIndex + 1
        if Editor.currentResultIndex > #Editor.searchResults then
            Editor.currentResultIndex = 1
        end

        local result = Editor.searchResults[Editor.currentResultIndex]
        Editor.GossipText = result.gossipText
        Editor.NpcId = result.id
        Editor.NpcName = result.npcName
        Editor.GossipId = result.gossipId

        Editor.Frame.textInput:SetText(Editor.GossipText)
        Editor.Frame.npcIDLabel:SetText("NPC ID: " .. (Editor.NpcId or "Unknown"))
        Editor.Frame.localeLabel:SetText("Locale: " .. Editor.Locale)
        Editor.Frame.npcNameLabel:SetText("Name: " .. (Editor.NpcName or "Unknown"))
        Editor.Frame.resultCountLabel:SetText(Editor.currentResultIndex .. " / " .. #Editor.searchResults)
    end
end)

-- Create a label to display the result count
Editor.Frame.resultCountLabel = Editor.Frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
Editor.Frame.resultCountLabel:SetPoint("TOP", Editor.Frame.previousButton, "BOTTOM", 0, -5)
Editor.Frame.resultCountLabel:SetText("0 / 0")

-- Create labels for NPC info
Editor.Frame.npcIDLabel = Editor.Frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
Editor.Frame.npcIDLabel:SetPoint("TOPRIGHT", -20, -40)
Editor.Frame.npcIDLabel:SetText("NPC ID: Unknown")

Editor.Frame.localeLabel = Editor.Frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
Editor.Frame.localeLabel:SetPoint("TOPRIGHT", Editor.Frame.npcIDLabel, "BOTTOMRIGHT", 0, -5)
Editor.Frame.localeLabel:SetText("Locale: " .. GetLocale())

Editor.Frame.npcNameLabel = Editor.Frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
Editor.Frame.npcNameLabel:SetPoint("TOPRIGHT", Editor.Frame.localeLabel, "BOTTOMRIGHT", 0, -5)
Editor.Frame.npcNameLabel:SetText("Name: Unknown")

Editor.Frame.generatedIDLabel = Editor.Frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
Editor.Frame.generatedIDLabel:SetPoint("TOPRIGHT", Editor.Frame.npcNameLabel, "BOTTOMRIGHT", 0, -5)
Editor.Frame.generatedIDLabel:SetText("Generated ID: None")

-- Create a scroll frame for the edit box
Editor.Frame.scrollFrame = CreateFrame("ScrollFrame", nil, Editor.Frame, "UIPanelScrollFrameTemplate")
Editor.Frame.scrollFrame:SetPoint("TOPLEFT", Editor.Frame.gossipTextSearchButton, "BOTTOMLEFT", 0, -10)
Editor.Frame.scrollFrame:SetSize(400, 350) -- Adjust the size as needed

-- Create a multiline text editor
Editor.Frame.textInput = CreateFrame("EditBox", nil, Editor.Frame.scrollFrame)
Editor.Frame.textInput:SetMultiLine(true)
Editor.Frame.textInput:SetAutoFocus(false)
Editor.Frame.textInput:SetFontObject("ChatFontNormal")
Editor.Frame.textInput:SetTextInsets(10, 10, 10, 10) -- Add padding inside the edit box
Editor.Frame.textInput:SetSize(Editor.Frame.scrollFrame:GetSize())

-- Enable mouse interaction and scrolling
Editor.Frame.textInput:EnableMouse(true)
Editor.Frame.textInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- Update Editor.GossipText when the text changes
Editor.Frame.textInput:SetScript("OnTextChanged", function(self)
    Editor.GossipText = self:GetText()
end)

-- Set the scroll child of the scroll frame to the edit box
Editor.Frame.scrollFrame:SetScrollChild(Editor.Frame.textInput)

-- Save Button (non-functional for now)
Editor.Frame.saveButton = CreateFrame("Button", nil, Editor.Frame, "GameMenuButtonTemplate")
Editor.Frame.saveButton:SetSize(100, 25)
Editor.Frame.saveButton:SetPoint("BOTTOMLEFT", 10, 10)
Editor.Frame.saveButton:SetText("Save")
Editor.Frame.saveButton:SetScript("OnClick", function()
    CLN.NpcDialogTracker:StoreGossipOptionsInfo(Editor.NpcId, Editor.GossipText, true, Editor.GossipId)
end)

-- Hash Button (non-functional for now)
Editor.Frame.generateIdButton = CreateFrame("Button", nil, Editor.Frame, "GameMenuButtonTemplate")
Editor.Frame.generateIdButton:SetSize(100, 25)
Editor.Frame.generateIdButton:SetPoint("BOTTOMRIGHT", -10, 10)
Editor.Frame.generateIdButton:SetText("Generate id")
Editor.Frame.generateIdButton:SetScript("OnClick", function()
    local generatedID = CLN.MD5:GenerateHash(Editor.NpcId .. Editor.GossipText)
    local ngramSizes = {2, 3}
    local simhash = CLN.SimHash64:GenerateHash(Editor.GossipText, ngramSizes, true)
    CLN:Print("Generated ID: " .. generatedID .. " Simhash: " .. simhash)
    Editor.Frame.generatedIDLabel:SetText("Generated ID: " .. generatedID)
end)

Editor.Frame:Hide()