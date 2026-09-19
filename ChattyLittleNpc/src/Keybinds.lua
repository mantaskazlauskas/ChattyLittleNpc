-- Voiceover hotkey, backed by a regular WoW key binding declared in Bindings.xml.
--
-- The game owns the key press: it shows up under AddOns in the game's Key
-- Bindings UI (where controller buttons can be bound too), and pressing it just
-- runs OnBindingPressed. No keyboard-capturing frame, no SetPropagateKeyboardInput
-- and no override bindings, so nothing here can raise ADDON_ACTION_BLOCKED at
-- key press time, in combat or with gamepad mode enabled.
--
-- The options panel can also set a keyboard key. That goes through SetBinding,
-- which is refused in combat, so it is only done out of combat.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

local Keybinds = {}
CLN.Keybinds = Keybinds

local ACTION = "CHATTYLITTLENPC_PLAY_VOICEOVER"
Keybinds.ACTION = ACTION

_G.BINDING_HEADER_CHATTYLITTLENPC = "Chatty Little NPC"
_G["BINDING_NAME_" .. ACTION] = "Play / Stop Voiceover"

function Keybinds:OnBindingPressed()
    if CLN.VoiceoverPlayer and CLN.VoiceoverPlayer:IsEffectivelyPlaying() then
        CLN.VoiceoverPlayer:ForceStopCurrentSound(false, true)
    elseif CLN.PlayButton and CLN.PlayButton._currentPlayCallback then
        CLN.PlayButton._currentPlayCallback()
    end
end

--- Controller buttons ("PAD1", "PADLSHOULDER-PAD2", ...) are left to the game's
--- Key Bindings UI; the options panel only manages keyboard keys.
local function IsGamePadKey(key)
    local base = key:match("[^-]*$") or ""
    return base:sub(1, 3) == "PAD"
end

--- All keys currently bound to the voiceover action.
function Keybinds:GetKeys()
    return { GetBindingKey(ACTION) }
end

--- Display text for the options panel, e.g. "CTRL-F, PAD1".
function Keybinds:GetKeyText()
    local keys = self:GetKeys()
    if #keys == 0 then return nil end
    return table.concat(keys, ", ")
end

local function SaveCurrentBindings()
    local set = GetCurrentBindingSet and GetCurrentBindingSet()
    if set and SaveBindings then SaveBindings(set) end
end

--- Replace the keyboard key(s) bound to the voiceover action.
--- Controller buttons bound through the game's Key Bindings UI are kept.
---@param key string|nil New key (e.g. "CTRL-F"); nil or "" only clears
---@return boolean changed
function Keybinds:SetKeyboardKey(key)
    if InCombatLockdown() then
        CLN:Print("Key bindings can't be changed in combat.")
        return false
    end

    for _, existing in ipairs(self:GetKeys()) do
        if not IsGamePadKey(existing) then
            SetBinding(existing)
        end
    end

    if key and key ~= "" then
        local previous = GetBindingAction(key)
        SetBinding(key, ACTION)
        if previous and previous ~= "" and previous ~= ACTION then
            local previousName = _G["BINDING_NAME_" .. previous] or previous
            CLN:Print(key .. " was unbound from " .. previousName .. ".")
        end
    end

    SaveCurrentBindings()
    return true
end

-- One-time migration of the old self-managed hotkey (db.profile.playVoiceoverKey)
-- into a real binding. Never steals a key that's already bound to something else.
local function MigrateLegacyKey()
    local profile = CLN.db and CLN.db.profile
    local key = profile and profile.playVoiceoverKey
    if not key or key == "" then return end
    profile.playVoiceoverKey = nil

    if #Keybinds:GetKeys() > 0 then return end

    local action = GetBindingAction(key)
    if action == nil or action == "" then
        SetBinding(key, ACTION)
        SaveCurrentBindings()
    else
        local actionName = _G["BINDING_NAME_" .. action] or action
        CLN:Print("Your voiceover hotkey " .. key .. " is already bound to " .. actionName
            .. ". Set a new one in Options or in the game's Key Bindings (AddOns).")
    end
end

local migrationFrame = CreateFrame("Frame")
migrationFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
migrationFrame:SetScript("OnEvent", function(self)
    if InCombatLockdown() then
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    self:UnregisterAllEvents()
    self:SetScript("OnEvent", nil)
    MigrateLegacyKey()
end)
