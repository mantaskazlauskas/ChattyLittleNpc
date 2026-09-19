-- Print.lua - Simple print utility
-- Provides a Print function that outputs to the chat frame with addon prefix

-- TEMP DIAGNOSTIC (SavedVariables load timing). This is the first file in the
-- TOC, so it shows whether saved data exists before any addon code runs.
-- Inspect in game with: /dump ChattyLittleNpcSVDiag
ChattyLittleNpcSVDiag = {
    firstFile = { db = ChattyLittleNpcDB ~= nil, npcInfo = NpcInfoDB ~= nil, charDb = ChattyLittleNpcCharDB ~= nil },
    events = {},
}

local ADDON_PREFIX = "|cff00ff00[Chatty Little NPC]|r "

---@class PrintUtil
local PrintUtil = {}

---Print a message to the default chat frame with addon prefix
---@param ... any
function PrintUtil:Print(...)
    local message = ""
    for i = 1, select("#", ...) do
        local arg = select(i, ...)
        if i > 1 then
            message = message .. " "
        end
        message = message .. tostring(arg)
    end
    DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. message)
end

-- Export globally for the addon
_G.ChattyLittleNpc = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc.PrintUtil = PrintUtil

return PrintUtil
