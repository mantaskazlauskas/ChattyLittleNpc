---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- ============================================================================
-- Addon Info
-- Download links for the voiceover packs, the "help expand the database"
-- message, and the "About" tab of the settings window. The welcome window and
-- the missing-voiceover "?" marker reuse the same text and layout helpers.
-- ============================================================================

local Widgets = CLN.Widgets
local C, rgba = Widgets.Colors, Widgets.rgba

---@class AddonInfo
local AddonInfo = {}
CLN.AddonInfo = AddonInfo

AddonInfo.DISCORD_URL = "https://discord.gg/dVjTXBgNb"
AddonInfo.DISCORD_CHANNEL = "#data-gathering-chat"
AddonInfo.SAVED_VARIABLES_PATH = "WTF\\Account\\<ACCOUNT>\\SavedVariables\\ChattyLittleNpc.lua"

-- English voiceover packs on CurseForge, in release order. expansion matches
-- the pack folder name (ChattyLittleNpc_<expansion>_voiceovers).
AddonInfo.VoiceoverPackLinks = {
    { expansion = "Vanilla",                label = "Vanilla (Classic / Classic Era)", url = "https://www.curseforge.com/wow/addons/chatty-little-npc-vanilla" },
    { expansion = "The_Burning_Crusade",    label = "The Burning Crusade",             url = "https://www.curseforge.com/wow/addons/chatty-little-npc-the-burning-crusade" },
    { expansion = "Wrath_of_the_Lich_King", label = "Wrath of the Lich King",          url = "https://www.curseforge.com/wow/addons/chatty-little-npc-wrath-of-the-lich-king" },
    { expansion = "Cataclysm",              label = "Cataclysm",                       url = "https://www.curseforge.com/wow/addons/chatty-little-npc-cataclysm" },
    { expansion = "Mists_of_Pandaria",      label = "Mists of Pandaria",               url = "https://www.curseforge.com/wow/addons/chatty-little-npc-mists-of-pandaria" },
    { expansion = "Warlords_of_Draenor",    label = "Warlords of Draenor",             url = "https://www.curseforge.com/wow/addons/chatty-little-npc-warlords-of-draenor" },
    { expansion = "Legion",                 label = "Legion",                          url = "https://www.curseforge.com/wow/addons/chatty-little-npc-legion" },
    { expansion = "Battle_for_Azeroth",     label = "Battle for Azeroth",              url = "https://www.curseforge.com/wow/addons/chatty-little-npc-battle-for-azeroth" },
    { expansion = "Shadowlands",            label = "Shadowlands",                     url = "https://www.curseforge.com/wow/addons/chatty-little-npc-shadowlands" },
    { expansion = "Dragonflight",           label = "Dragonflight",                    url = "https://www.curseforge.com/wow/addons/chatty-little-npc-dragonflight" },
    { expansion = "The_War_Within",         label = "The War Within",                  url = "https://www.curseforge.com/wow/addons/chatty-little-npc-the-war-within-en-us" },
    { expansion = "Midnight",               label = "Midnight",                        url = "https://www.curseforge.com/wow/addons/chatty-little-npc-midnight-english-ai-voiceover" },
}

AddonInfo.CONTRIBUTE_TEXT = "Missing a voiceover? Help expand the database by sharing your "
    .. "|cffffd100ChattyLittleNpc.lua|r file with us in the " .. AddonInfo.DISCORD_CHANNEL
    .. " channel on Discord. It holds the quest and NPC dialog the addon recorded while you played, "
    .. "which is what new voiceovers are made from."

AddonInfo.SAVED_VARIABLES_HINT = "You'll find it in your World of Warcraft game folder (_retail_, _classic_ or "
    .. "_classic_era_) under |cffffffff" .. AddonInfo.SAVED_VARIABLES_PATH .. "|r. "
    .. "The game writes it when you log out or /reload."

--- Install state of each English pack, keyed by expansion.
---@return table<string, string> states  "loaded" | "disabled"; absent when not installed
function AddonInfo:GetPackStates()
    local states = {}
    for _, pack in ipairs(CLN:GetInstalledVoiceoverPacks()) do
        if pack.locale == CLN.DEFAULT_VOICEOVER_LOCALE then
            states[pack.expansion] = pack.loaded and "loaded" or "disabled"
        end
    end
    return states
end

--- Number of voiceover packs loaded right now, in any language.
---@return number
function AddonInfo:GetLoadedPackCount()
    local count = 0
    for _ in pairs(CLN.VoiceoverPacks or {}) do count = count + 1 end
    return count
end

--- Append the "help expand the database" lines to a tooltip.
---@param tooltip GameTooltip
function AddonInfo:AddContributeTooltipLines(tooltip)
    tooltip:AddLine("Help expand the database!", 1, 0.82, 0)
    tooltip:AddLine("Share your ChattyLittleNpc.lua file in the " .. self.DISCORD_CHANNEL
        .. " channel on our Discord. It holds the dialog the addon recorded while you played,"
        .. " and new voiceovers are made from it.", 0.9, 0.9, 0.9, true)
    tooltip:AddLine(" ")
    tooltip:AddLine(self.SAVED_VARIABLES_PATH, 0.6, 0.6, 0.65, true)
    if not (CLN.db and CLN.db.profile and CLN.db.profile.logNpcTexts) then
        tooltip:AddLine(" ")
        tooltip:AddLine("Dialog recording is off. Turn on 'Track NPC Dialog Data' in Settings > Developer.", 1, 0.45, 0.35, true)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Layout helpers shared with the welcome window
-- ─────────────────────────────────────────────────────────────────────────────

local CARD_PAD = 12
local CARD_GAP = 12

---@class AddonInfoLayout
local Layout = {}
Layout.__index = Layout

--- Top-to-bottom layout cursor over a content frame whose width is already
--- set. Sections are drawn as cards matching the settings tabs.
---@param frame Frame
---@return AddonInfoLayout
function AddonInfo.NewLayout(frame)
    return setmetatable({ frame = frame, y = 0, textW = frame:GetWidth() - CARD_PAD * 2 - 16 }, Layout)
end

function Layout:BeginCard(title)
    self.cardTop = self.y
    self.y = self.y - CARD_PAD
    local fs = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", CARD_PAD + 8, self.y)
    fs:SetText(title)
    fs:SetTextColor(rgba(C.textHeader))
    self.y = self.y - 24
end

function Layout:EndCard()
    self.y = self.y - CARD_PAD + 6
    local bg = self.frame:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(rgba(C.cardBg))
    bg:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, self.cardTop)
    bg:SetPoint("BOTTOMRIGHT", self.frame, "TOPRIGHT", 0, self.y)
    Widgets.AddBorder(self.frame, bg, C.cardBorder)
    -- Gold tab on the card's left edge, level with the title.
    local marker = self.frame:CreateTexture(nil, "ARTWORK")
    marker:SetColorTexture(rgba(C.accent))
    marker:SetSize(3, 18)
    marker:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 0, self.cardTop - CARD_PAD + 1)
    self.y = self.y - CARD_GAP
end

--- Wrapping text line. font defaults to GameFontHighlight, color to the body text.
---@return FontString
function Layout:Text(text, font, color)
    local fs = self.frame:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetWidth(self.textW)
    fs:SetJustifyH("LEFT")
    fs:SetSpacing(2)
    fs:SetText(text)
    fs:SetTextColor(rgba(color or C.text))
    fs:SetPoint("TOPLEFT", self.frame, "TOPLEFT", CARD_PAD + 8, self.y)
    self.y = self.y - math.ceil(fs:GetStringHeight()) - 8
    return fs
end

--- Place a region at the cursor, indented like the text, and advance by its height.
function Layout:Add(region, height, indent)
    region:SetPoint("TOPLEFT", self.frame, "TOPLEFT", CARD_PAD + 8 + (indent or 0), self.y)
    self.y = self.y - (height or region:GetHeight()) - 8
    return region
end

--- Leave extra space before the next item.
function Layout:Gap(px)
    self.y = self.y - (px or 6)
end

--- Total height laid out so far.
function Layout:Height()
    return -self.y
end

--- Card with the Discord link and where to find the saved variables file.
function AddonInfo:AddContributeCard(layout)
    layout:BeginCard("Help Expand the Database")
    layout:Text(self.CONTRIBUTE_TEXT)
    layout:Text(self.SAVED_VARIABLES_HINT, "GameFontHighlightSmall", C.textMuted)
    layout:Add(Widgets.CreateCopyBox(layout.frame, self.DISCORD_URL, 320), 24)
    layout:Text("Click the link, then press Ctrl+C to copy it.", "GameFontHighlightSmall", C.textMuted)
    -- Re-read by _RefreshVisibleControls, so it follows the Quick Setup switch.
    local function recordingNote()
        if CLN.db and CLN.db.profile and CLN.db.profile.logNpcTexts then return "" end
        return "|cffff7359Dialog recording is off.|r Turn on 'Track NPC Dialog Data' in the Developer tab so the addon has something to share."
    end
    local note = layout:Text(recordingNote(), "GameFontHighlightSmall")
    note._textFn = recordingNote
    layout.frame._trackedControls = layout.frame._trackedControls or {}
    table.insert(layout.frame._trackedControls, { control = note })
    layout:EndCard()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- About tab
-- ─────────────────────────────────────────────────────────────────────────────

local PACK_STATE_TEXT = {
    loaded   = "|cff00ff00Installed|r",
    disabled = "|cffffd100Installed, disabled|r",
}

--- One row per pack: name, install state and a copyable CurseForge link.
local function addPackRows(layout, states)
    local frame = layout.frame
    local linkW = 300
    for _, pack in ipairs(AddonInfo.VoiceoverPackLinks) do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(layout.textW, 22)

        local box = Widgets.CreateCopyBox(row, pack.url, linkW, 22)
        box:SetPoint("RIGHT", row, "RIGHT", 0, 0)

        local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        name:SetPoint("LEFT", row, "LEFT", 0, 0)
        name:SetText(pack.label)

        local state = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        state:SetPoint("RIGHT", box, "LEFT", -10, 0)
        state:SetText(PACK_STATE_TEXT[states[pack.expansion]] or "|cff808080Not installed|r")

        layout:Add(row, 22)
        layout.y = layout.y + 4 -- rows sit closer together than text blocks
    end
end

--- Build the About tab into the settings window's custom panel frame.
---@param parent Frame
function AddonInfo:BuildAboutPanel(parent)
    local SCROLLBAR_W = 14
    local sf, content = Widgets.CreateScrollFrame(parent)
    sf:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -SCROLLBAR_W, 0)
    content:SetWidth(parent:GetWidth() - SCROLLBAR_W)

    local layout = AddonInfo.NewLayout(content)

    layout:BeginCard("Chatty Little NPC")
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = getMetadata and getMetadata("ChattyLittleNpc", "Version")
    layout:Text("Plays pre-recorded voiceovers for quests, gossip, books and more."
        .. (version and ("  |cff999999v" .. version .. "|r") or ""))
    local welcome = Widgets.CreateButton(content, "Show Welcome Screen")
    welcome:FitToText(160)
    welcome:SetScript("OnClick", function()
        if CLN.WelcomeWindow then CLN.WelcomeWindow:Open() end
    end)
    layout:Add(welcome, 22)
    layout:EndCard()

    layout:BeginCard("Voiceover Packs")
    layout:Text("The voices live in separate addons, one per expansion. Install the ones for the content you play, "
        .. "then /reload. Copy a link into your browser or search for it in the CurseForge app.",
        "GameFontHighlightSmall", C.textMuted)
    addPackRows(layout, self:GetPackStates())
    layout:EndCard()

    self:AddContributeCard(layout)

    layout:BeginCard("Commands")
    layout:Text("|cffffd100/clnsettings|r  Open or close this window\n"
        .. "|cffffd100/clnlibrary|r  Browse and play every installed voiceover\n"
        .. "|cffffd100/clnwelcome|r  Show the welcome screen again\n"
        .. "|cffffd100/clnlogs|r  Open the addon log window")
    layout:EndCard()

    content:SetHeight(math.max(layout:Height(), 80))
end
