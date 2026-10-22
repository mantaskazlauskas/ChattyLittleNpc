---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- ============================================================================
-- Welcome Window
-- Shown once per account after login: pick a frame style, set the few
-- settings most people care about, and learn where everything else lives.
-- Reopen with /clnwelcome or from the About tab of the settings window.
-- ============================================================================

local Widgets = CLN.Widgets
local C, rgba = Widgets.Colors, Widgets.rgba

local WIN_WIDTH  = 600
local WIN_HEIGHT = 600
local PADDING    = 12
local HEADER_H   = 44
local FOOTER_H   = 44
local SCROLLBAR_W = 14

local STYLE_ORDER = { "minimal", "panel", "cinematic" }
local STYLE_DESC = {
    minimal   = "Frameless, like the quest objectives tracker.",
    panel     = "Dark panel with a framed portrait and nameplate.",
    cinematic = "Head-and-shoulders portrait with a large name.",
}

local PORTRAIT_POSITIONS = { "above", "below", "left", "right" }

-- Settings offered on the welcome page, as { option group, option key }.
local QUICK_SETTINGS = {
    { "Playback",       "autoPlayVoiceovers" },
    { "VoiceoverFrame", "showReplayFrame" },
    { "VoiceoverFrame", "compactMode" },
    { "Playback",       "showSpeakButton" },
    { "DataCollection", "logNpcTexts" },
}

---@class WelcomeWindow
local WelcomeWindow = {}
CLN.WelcomeWindow = WelcomeWindow

local _frame = nil ---@type Frame|nil
local _pickers = {} -- { tiles = { [value] = tile }, get = fn }

-- ─────────────────────────────────────────────────────────────────────────────
-- Tile pickers (frame style, portrait position)
-- ─────────────────────────────────────────────────────────────────────────────

local function refreshPickers()
    for _, picker in ipairs(_pickers) do
        local current = picker.get()
        for value, tile in pairs(picker.tiles) do
            local selected = value == current
            tile:SetBackdropColor(rgba(selected and { 1, 0.78, 0.2, 0.10 } or C.controlBg))
            tile:SetBackdropBorderColor(rgba(selected and C.accent or C.border))
            tile._title:SetTextColor(rgba(selected and C.accent or C.text))
            if tile._onSelect then tile._onSelect(selected) end
        end
    end
end

--- Row of clickable tiles, one per value; the current value is highlighted.
--- items = { { value, label, desc? }, ... }; decorate(tile, value) adds extras.
local function createTilePicker(layout, items, get, set, tileH, decorate)
    local gap = 8
    local tileW = math.floor((layout.textW - gap * (#items - 1)) / #items)

    local holder = CreateFrame("Frame", nil, layout.frame)
    holder:SetSize(layout.textW, tileH)

    local picker = { tiles = {}, get = get }
    for i, item in ipairs(items) do
        local tile = CreateFrame("Button", nil, holder, "BackdropTemplate")
        tile:SetSize(tileW, tileH)
        tile:SetPoint("TOPLEFT", holder, "TOPLEFT", (i - 1) * (tileW + gap), 0)
        Widgets.ApplyBackdrop(tile)

        local title = tile:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", tile, "TOPLEFT", 10, -10)
        title:SetText(item.label)
        tile._title = title

        if item.desc then
            local desc = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
            desc:SetWidth(tileW - 20)
            desc:SetJustifyH("LEFT")
            desc:SetText(item.desc)
            desc:SetTextColor(rgba(C.textMuted))
        end
        if decorate then decorate(tile, item.value) end

        local hover = tile:CreateTexture(nil, "HIGHLIGHT")
        hover:SetPoint("TOPLEFT", 1, -1)
        hover:SetPoint("BOTTOMRIGHT", -1, 1)
        hover:SetColorTexture(1, 1, 1, 0.04)

        tile:SetScript("OnClick", function()
            set(item.value)
            Widgets.PlayClick(true)
            refreshPickers()
        end)

        picker.tiles[item.value] = tile
    end
    _pickers[#_pickers + 1] = picker

    layout:Add(holder, tileH)
end

local function createStyleTiles(layout)
    local styles = CLN.ReplayFrame and CLN.ReplayFrame.FrameStyles or {}
    local items = {}
    for _, key in ipairs(STYLE_ORDER) do
        items[#items + 1] = { value = key, label = styles[key] and styles[key].label or key, desc = STYLE_DESC[key] }
    end
    createTilePicker(layout, items,
        function() return CLN.db.profile.frameStyle or "minimal" end,
        function(value)
            CLN.db.profile.frameStyle = value
            if CLN.ReplayFrame and CLN.ReplayFrame.ApplyFrameStyle then CLN.ReplayFrame:ApplyFrameStyle() end
        end,
        64)
end

-- Mini diagram: the conversation window as an outline, the portrait as a
-- filled block on the chosen side.
local function drawPortraitDiagram(tile, position)
    local BOX_W, BOX_H, P = 44, 20, 14
    local area = CreateFrame("Frame", nil, tile)
    area:SetSize(BOX_W + P + 2, BOX_H + P + 2)
    area:SetPoint("RIGHT", tile, "RIGHT", -10, 0)

    local box = area:CreateTexture(nil, "ARTWORK")
    box:SetSize(BOX_W, BOX_H)
    Widgets.AddBorder(area, box, C.borderHover, "ARTWORK")

    local portrait = area:CreateTexture(nil, "ARTWORK")
    tile._onSelect = function(selected)
        portrait:SetColorTexture(rgba(selected and C.accent or C.textMuted))
    end
    if position == "left" or position == "right" then
        portrait:SetSize(P, BOX_H)
        box:SetPoint("CENTER", area, "CENTER", position == "left" and (P + 2) / 2 or -(P + 2) / 2, 0)
        if position == "left" then
            portrait:SetPoint("RIGHT", box, "LEFT", -2, 0)
        else
            portrait:SetPoint("LEFT", box, "RIGHT", 2, 0)
        end
    else
        portrait:SetSize(BOX_W, P)
        box:SetPoint("CENTER", area, "CENTER", 0, position == "above" and -(P + 2) / 2 or (P + 2) / 2)
        if position == "above" then
            portrait:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 0, 2)
        else
            portrait:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -2)
        end
    end
end

-- Uses the Display tab's option so the frame is re-laid out the same way.
local function createPortraitTiles(layout)
    local args = CLN.OptionsDefinition and CLN.OptionsDefinition.args
    local opt = args and args.FrameLayout and args.FrameLayout.args and args.FrameLayout.args.portraitPosition
    if not opt then return end
    layout:Gap(2)
    layout:Text("Portrait Position", "GameFontNormal", C.text)
    local items = {}
    for _, value in ipairs(PORTRAIT_POSITIONS) do
        items[#items + 1] = { value = value, label = opt.values[value] or value }
    end
    createTilePicker(layout, items, opt.get, function(value) opt.set(nil, value) end, 48, drawPortraitDiagram)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Content
-- ─────────────────────────────────────────────────────────────────────────────

local function buildContent(content)
    local Info = CLN.AddonInfo
    local layout = Info.NewLayout(content)

    layout:BeginCard("Welcome!")
    layout:Text("Chatty Little NPC gives quest givers, gossiping NPCs, books and letters a voice. "
        .. "Here are the settings most people care about. Everything else is in the settings window.")
    layout:EndCard()

    -- Voiceover packs
    layout:BeginCard("Voiceover Packs")
    local count = Info:GetLoadedPackCount()
    if count == 0 then
        layout:Text("|cffff7359No voiceover packs found.|r The voices come in separate addons, one per expansion, "
            .. "so install at least one and /reload.")
    else
        layout:Text(string.format("|cff00ff00%d voiceover pack%s loaded.|r Voices for other expansions come in their own packs.",
            count, count == 1 and "" or "s"))
    end
    local links = Widgets.CreateButton(content, "Show Download Links")
    links:FitToText(160)
    links:SetScript("OnClick", function()
        if CLN.SettingsWindow then CLN.SettingsWindow:OpenTab("about") end
    end)
    layout:Add(links, 22)
    layout:EndCard()

    -- Frame style
    layout:BeginCard("Frame Style")
    layout:Text("How the conversation frame and NPC portrait look. You'll see it on the next voiceover.",
        "GameFontHighlightSmall", C.textMuted)
    createStyleTiles(layout)
    createPortraitTiles(layout)
    layout:EndCard()

    -- Quick settings, built from the real option definitions so they behave
    -- exactly like the same switches in the settings window.
    layout:BeginCard("Quick Setup")
    local args = CLN.OptionsDefinition and CLN.OptionsDefinition.args or {}
    local cfg = CLN.ConfigSystem:New()
    content._trackedControls = {}
    for _, entry in ipairs(QUICK_SETTINGS) do
        local group = args[entry[1]]
        local opt = group and group.args and group.args[entry[2]]
        local row = opt and cfg:CreateControl(content, opt)
        if row then
            row:SetPoint("TOPLEFT", content, "TOPLEFT", PADDING, layout.y)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PADDING, layout.y)
            layout.y = layout.y - row:GetHeight() - 2
            table.insert(content._trackedControls, { control = row, opt = opt })
        end
    end
    layout:Gap(4)
    layout:Text("Hover a setting to see what it does.", "GameFontHighlightSmall", C.textMuted)
    layout:EndCard()

    -- Pointers to the rest of the settings
    layout:BeginCard("Good to Know")
    layout:Text(
        "|cffffd100Minimap button|r  Left-click opens settings, right-click shows or hides the voiceover frame.\n"
        .. "|cffffd100Moving the frame|r  Drag it, or use Edit Mode on Retail. Size and portrait placement are under Display.\n"
        .. "|cffffd100Keybind|r  Bind a key to Play / Stop Voiceover in the General tab.\n"
        .. "|cffffd100Playback|r  Choose whether voiceovers queue up or stop when you close the dialog, in General.\n"
        .. "|cffffd100Language|r  Pick the voiceover language in the Language tab if you have non-English packs.\n"
        .. "|cffffd100Library|r  Browse and play every installed voiceover with /clnlibrary.\n"
        .. "|cffffd100Missing voiceover|r  A |cffffd100?|r on a dialog means it isn't voiced yet. Hover it to see how you can help.")
    layout:EndCard()

    Info:AddContributeCard(layout)

    content:SetHeight(math.max(layout:Height(), 80))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Frame
-- ─────────────────────────────────────────────────────────────────────────────

local function buildFrame()
    if _frame then return end

    local f = CreateFrame("Frame", "CLN_WelcomeWindow", UIParent, "BackdropTemplate")
    f:SetSize(WIN_WIDTH, WIN_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    Widgets.ApplyBackdrop(f, C.windowBg, C.windowBorder)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()
    tinsert(UISpecialFrames, "CLN_WelcomeWindow")

    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = getMetadata and getMetadata("ChattyLittleNpc", "Version")
    Widgets.CreateTitleBar(f, "Chatty Little NPC", {
        height   = HEADER_H,
        subtitle = version and ("Welcome  ·  v" .. version) or "Welcome",
    })

    local sf, content = Widgets.CreateScrollFrame(f)
    sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     PADDING, -(HEADER_H + 10))
    sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PADDING + SCROLLBAR_W), FOOTER_H + 4)
    content:SetWidth(WIN_WIDTH - PADDING * 2 - SCROLLBAR_W)
    buildContent(content)

    -- Footer
    local done = Widgets.CreateButton(f, "Let's Go!", 120, 26)
    done:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PADDING, PADDING)
    done:SetScript("OnClick", function() f:Hide() end)

    local settings = Widgets.CreateButton(f, "Open Settings", 120, 26)
    settings:SetPoint("RIGHT", done, "LEFT", -8, 0)
    settings:SetScript("OnClick", function()
        f:Hide()
        if CLN.SettingsWindow then CLN.SettingsWindow:Open() end
    end)

    f:SetScript("OnShow", function()
        refreshPickers()
        CLN.ConfigSystem._RefreshVisibleControls(content)
    end)
    f:SetScript("OnHide", function()
        -- Closing in any way counts as seen; keep an open settings window in sync.
        CLN.db.sv.welcomeShown = true
        if CLN.SettingsWindow then CLN.SettingsWindow:Refresh() end
    end)

    _frame = f
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

function WelcomeWindow:Open()
    buildFrame()
    _frame:Show()
    _frame:Raise()
end

function WelcomeWindow:Close()
    if _frame then _frame:Hide() end
end

--- Open the window if this account has never seen it.
function WelcomeWindow:ShowIfFirstRun()
    if not (CLN.db and CLN.db.sv) or CLN.db.sv.welcomeShown then return end
    -- Wait for combat to end rather than popping up mid-fight.
    if InCombatLockdown and InCombatLockdown() then
        C_Timer.After(5, function() WelcomeWindow:ShowIfFirstRun() end)
        return
    end
    self:Open()
end

SLASH_CLNWELCOME1 = "/clnwelcome"
SlashCmdList["CLNWELCOME"] = function()
    WelcomeWindow:Open()
end
