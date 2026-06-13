---@class CLNIconAtlas
-- Centralized icon path registry so future branding swaps only change here.
-- Placeholder custom icons (replace with real assets later):
--  Add files under Interface\\AddOns\\ChattyLittleNpc\\Icons\\
--  e.g. ChattyLittleNpc_Icon_Play.png, ChattyLittleNpc_Icon_Stop.png, etc.

local CLN = _G.ChattyLittleNpc

local Atlas = {}

-- If addon not yet initialized, stash globally for later pickup in Main.lua OnInitialize
if CLN then
    CLN.IconAtlas = Atlas
else
    _G.ChattyLittleNpc_PendingAtlas = Atlas
end

-- Base path helper
local BASE = "Interface\\AddOns\\ChattyLittleNpc\\Icons\\"
---Build a placeholder path (assumes .png extension for custom art)
---@param name string
---@return string
local function P(name)
    return BASE .. name .. ".png"
end

-- Public keys (stable identifiers). Real textures can later replace placeholder ones.
Atlas.keys = {
    play = "play",
    stop = "stop",
    glow = "glow",
    clear = "clear",
    options = "options",
    collapse = "collapse",
    expand = "expand",
    lock = "lock",
    unlock = "unlock",
    speaker = "speaker",
    queue = "queue",
    refresh = "refresh",
    portrait = "portrait",
    questBang = "questBang",
    gossipBubble = "gossipBubble",
    itemScroll = "itemScroll",
    replay = "replay",
}

-- Mapping: logical key -> texture path (placeholders referencing existing Blizzard icons until custom art arrives)
Atlas.textures = {
    [Atlas.keys.play] = BASE .. "speech-bubble-border.png",
    [Atlas.keys.stop] = P("Chatty_StopPlaceholder"),      -- TODO provide Chatty_StopPlaceholder.png
    [Atlas.keys.glow] = BASE .. "speech-bubble-border-glow.png",
    [Atlas.keys.clear] = "Interface/RAIDFRAME/ReadyCheck-NotReady", -- clean X mark (unified gold tint applied at render)
    [Atlas.keys.options] = "Interface/Buttons/UI-OptionsButton",
    [Atlas.keys.collapse] = "Interface/Buttons/UI-Panel-CollapseButton-Up",
    [Atlas.keys.expand] = "Interface/Buttons/UI-Panel-ExpandButton-Up",
    [Atlas.keys.lock] = "Interface/Buttons/LockButton-Locked",
    [Atlas.keys.unlock] = "Interface/Buttons/LockButton-Unlocked",
    [Atlas.keys.speaker] = "Interface/COMMON/VOICECHAT-SPEAKER",
    [Atlas.keys.queue] = P("Chatty_QueuePlaceholder"),    -- TODO add Chatty_QueuePlaceholder.png
    [Atlas.keys.refresh] = "Interface/Buttons/UI-RefreshButton",
    [Atlas.keys.portrait] = BASE .. "ChattyLittleNpc.png",
    [Atlas.keys.questBang] = "Interface/GossipFrame/AvailableQuestIcon",
    [Atlas.keys.gossipBubble] = "Interface/GossipFrame/GossipGossipIcon",
    [Atlas.keys.itemScroll] = "Interface/GossipFrame/BankerGossipIcon",
    [Atlas.keys.replay] = "Interface/Buttons/UI-SpellbookIcon-PrevPage-Up",
}

---Get the texture path for a logical icon key.
---@param key string Atlas key (see Atlas.keys)
---@return string path Texture path safe for SetTexture
function Atlas:Get(key)
    local path = self.textures[key]
    if not path then
        if CLN and CLN.Logger and CLN.Utils and CLN.Utils.LogCategories then
            CLN.Logger:warn("Unknown icon key: " .. tostring(key), false, CLN.Utils.LogCategories.ui)
        end
        return "Interface/Icons/INV_Misc_QuestionMark"
    end
    return path
end

---Swap (override) an icon at runtime (e.g., user theme packs)
---@param key string
---@param texturePath string
function Atlas:Set(key, texturePath)
    if not key or not texturePath then return end
    self.textures[key] = texturePath
end

return Atlas
