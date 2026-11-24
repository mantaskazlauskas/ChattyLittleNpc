---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- ============================================================================
-- Minimap Button
-- A LibDataBroker launcher shown on the minimap through LibDBIcon-1.0, the
-- library most addons use for their minimap button. Button collectors
-- (EllesmereUI's minimap flyout, OneForAll's button bar, Leatrix Plus, ...)
-- look for LibDBIcon buttons first, and LibDBIcon follows square minimaps and
-- remembers the position for us. LDB displays (Titan Panel, ChocolateBar)
-- pick up the same launcher.
--
-- Left-click  → toggle Settings window
-- Right-click → toggle the Voiceover replay frame
-- Drag        → reposition around the minimap edge (saved to the profile)
-- ============================================================================

local NAME = "ChattyLittleNpc"   -- the LDB object name; the frame is LibDBIcon10_ChattyLittleNpc
local ICON = "Interface\\AddOns\\ChattyLittleNpc\\Icons\\ChattyLittleNpc.png"

---@class MinimapButton
local MinimapButton = {}
CLN.MinimapButton = MinimapButton

local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

--- The profile table LibDBIcon keeps its state in ({ minimapPos, hide }).
--- Before LibDBIcon the button saved its angle in radians as
--- `minimapButtonAngle`; LibDBIcon uses degrees with the same zero and
--- direction, so the old position carries over.
local function iconDb()
    local profile = CLN.db.profile
    local db = profile.minimapIcon
    if type(db) ~= "table" then
        db = {}
        profile.minimapIcon = db
    end
    if db.minimapPos == nil and type(profile.minimapButtonAngle) == "number" then
        db.minimapPos = math.deg(profile.minimapButtonAngle) % 360
    end
    return db
end

local launcher = LDB and LDB:NewDataObject(NAME, {
    type = "launcher",
    label = "Chatty Little NPC",
    icon = ICON,
    OnClick = function(_, button)
        if button == "RightButton" then
            CLN.ReplayFrame:ToggleUserHidden()
        else
            CLN.SettingsWindow:Toggle()
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("Chatty Little NPC", 1, 0.82, 0)
        tooltip:AddLine("Left-click: Open Settings", 0.8, 0.8, 0.8)
        tooltip:AddLine("Right-click: Toggle Voiceover Frame", 0.8, 0.8, 0.8)
        tooltip:AddLine("Drag: Reposition", 0.6, 0.6, 0.6)
    end,
})

--- Register the button with LibDBIcon.  Idempotent.
function MinimapButton:Create()
    if not (launcher and LDBIcon) or LDBIcon:IsRegistered(NAME) then return end
    LDBIcon:Register(NAME, launcher, iconDb())
    -- Each profile keeps its own position and visibility.
    local function refresh() LDBIcon:Refresh(NAME, iconDb()) end
    CLN.db:RegisterCallback("OnProfileChanged", refresh)
    CLN.db:RegisterCallback("OnProfileCopied", refresh)
    CLN.db:RegisterCallback("OnProfileReset", refresh)
end

--- Show the button (create if needed).
function MinimapButton:Show()
    self:Create()
    if not LDBIcon then return end
    iconDb().hide = false
    LDBIcon:Show(NAME)
end

--- Hide the button.
function MinimapButton:Hide()
    if not (LDBIcon and LDBIcon:IsRegistered(NAME)) then return end
    iconDb().hide = true
    LDBIcon:Hide(NAME)
end
