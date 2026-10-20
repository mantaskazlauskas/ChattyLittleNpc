---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- ============================================================================
-- Settings Window
-- Tabbed popup window providing the primary settings UI for the addon.
-- Groups option settings into logical tabs so related controls stay together.
-- Based on the same draggable-popup pattern as WhitelistWindow.
-- ============================================================================

local Widgets = CLN.Widgets
local C, rgba = Widgets.Colors, Widgets.rgba

local WIN_WIDTH  = 660
local WIN_HEIGHT = 540
local PADDING    = 12
local TAB_BAR_H  = 30     -- height of the tab strip
local HEADER_H   = 44     -- height of the title bar

-- Each tab maps to one or more option-group keys from CLN.OptionsDefinition.args.
local TABS = {
    {
        key    = "general",
        label  = "General",
        groups = { "Playback" },
        tip    = "Playback behaviour, audio channel, keybind and gossip settings.",
    },
    {
        key    = "language",
        label  = "Language",
        groups = { "VoiceoverLanguage", "InstalledVoiceoverPacks" },
        tip    = "Voiceover language and the voiceover packs installed in your AddOns folder.",
    },
    {
        key    = "library",
        label  = "Library",
        -- Custom content: built by VoiceoverLibrary instead of option groups.
        build  = function(parent) if CLN.VoiceoverLibrary then CLN.VoiceoverLibrary:Build(parent) end end,
        tip    = "Browse, search and play every installed voiceover.",
    },
    {
        key    = "display",
        label  = "Display",
        groups = { "VoiceoverFrame", "FrameLayout", "Accessibility", "Advanced" },
        tip    = "Voiceover frame appearance, sizing, subtitles and model renderer.",
    },
    {
        key    = "npcs",
        label  = "NPCs",
        groups = { "NativeVoicedNpcs" },
        tip    = "Pause-for whitelist for NPCs with Blizzard native voice acting.",
    },
    {
        key    = "profiles",
        label  = "Profiles",
        groups = { "Profiles" },
        tip    = "Create, copy, reset and delete settings profiles.",
    },
    {
        key    = "developer",
        label  = "Developer",
        groups = { "DataCollection", "DeveloperDebug" },
        tip    = "Data collection, debug logging and developer diagnostics.",
    },
}

-- Tab width (px). All tabs are the same width for a clean look.
local TAB_W = math.floor((WIN_WIDTH - PADDING * 2) / #TABS)

-- ─────────────────────────────────────────────────────────────────────────────
-- Module-level state
-- ─────────────────────────────────────────────────────────────────────────────

local _frame        = nil   ---@type Frame|nil
local _activeTabKey = "general"
local _tabButtons   = {}    -- key → Button
local _tabPanels    = {}    -- key → { sf=ScrollFrame, content=Frame, built=bool }

-- ─────────────────────────────────────────────────────────────────────────────
-- Tab visual helpers
-- ─────────────────────────────────────────────────────────────────────────────

local function applyTabActive(key, isActive)
    local btn = _tabButtons[key]
    if not btn then return end
    if isActive then
        btn._bg:SetColorTexture(1, 0.78, 0.2, 0.08)
        btn._text:SetTextColor(rgba(C.accent))
        btn._underline:SetColorTexture(rgba(C.accent))
    else
        btn._bg:SetColorTexture(0, 0, 0, 0)
        btn._text:SetTextColor(rgba(C.textMuted))
        btn._underline:SetColorTexture(0, 0, 0, 0)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Content building
-- ─────────────────────────────────────────────────────────────────────────────

--- Build the controls for one tab's scroll content on first activation.
local function buildTabContent(tabDef, panel)
    if tabDef.build then
        tabDef.build(panel.content)
        return
    end
    local opts = CLN.OptionsDefinition
    if not (opts and opts.args) then return end
    -- Fresh ConfigSystem instance per tab so counters stay independent.
    local cfg = CLN.ConfigSystem:New()
    panel.content._trackedControls = {}
    local h = cfg:LayoutGroupsInFrame(panel.content, tabDef.groups, opts.args)
    panel.content:SetHeight(math.max(h + PADDING, 80))
end

--- Refresh disabled/enabled state of all built controls on a tab.
local function refreshTabControls(key)
    local panel = _tabPanels[key]
    if not panel then return end
    CLN.ConfigSystem._RefreshVisibleControls(panel.content)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Tab switching
-- ─────────────────────────────────────────────────────────────────────────────

local function activateTab(key)
    -- Deactivate the current tab.
    local prevPanel = _tabPanels[_activeTabKey]
    if prevPanel and prevPanel.sf then prevPanel.sf:Hide() end
    applyTabActive(_activeTabKey, false)

    _activeTabKey = key

    -- Find the tab definition.
    local tabDef = nil
    for _, t in ipairs(TABS) do
        if t.key == key then tabDef = t; break end
    end

    -- Show and lazily build the new tab.
    local panel = _tabPanels[key]
    if panel and panel.sf then
        if not panel.built then
            panel.built = true
            buildTabContent(tabDef, panel)
        end
        panel.sf:Show()
        CLN.ConfigSystem._RefreshVisibleControls(panel.content)
    end

    applyTabActive(key, true)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Frame construction (called once on first Open)
-- ─────────────────────────────────────────────────────────────────────────────

local function buildFrame()
    if _frame then return end

    local f = CreateFrame("Frame", "CLN_SettingsWindow", UIParent, "BackdropTemplate")
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

    -- Register so Escape closes the window.
    tinsert(UISpecialFrames, "CLN_SettingsWindow")

    -- ── Title bar ────────────────────────────────────────────────────────────
    local titleBg = f:CreateTexture(nil, "BACKGROUND")
    titleBg:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    titleBg:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -1, -HEADER_H)
    titleBg:SetColorTexture(rgba(C.titleBg))

    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26)
    icon:SetPoint("LEFT", titleBg, "LEFT", PADDING - 1, 0)
    icon:SetTexture("Interface\\AddOns\\ChattyLittleNpc\\Icons\\ChattyLittleNpc.png")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText("Chatty Little NPC")
    title:SetTextColor(rgba(C.textHeader))

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
    subtitle:SetTextColor(rgba(C.textMuted))
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local version = getMetadata and getMetadata("ChattyLittleNpc", "Version")
    subtitle:SetText(version and ("Settings  ·  v" .. version) or "Settings")

    local closeBtn = Widgets.CreateCloseButton(f)
    closeBtn:SetPoint("RIGHT", titleBg, "RIGHT", -PADDING + 2, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Thin separator below title bar.
    local titleSep = f:CreateTexture(nil, "ARTWORK")
    titleSep:SetHeight(1)
    titleSep:SetPoint("TOPLEFT",  titleBg, "BOTTOMLEFT")
    titleSep:SetPoint("TOPRIGHT", titleBg, "BOTTOMRIGHT")
    titleSep:SetColorTexture(rgba(C.cardBorder))

    -- ── Tab bar ──────────────────────────────────────────────────────────────
    -- Tabs sit between the title separator and the content area.
    local tabTopY = -(HEADER_H)  -- Y from frame top edge

    for i, tab in ipairs(TABS) do
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(TAB_W, TAB_BAR_H)
        btn._key = tab.key

        -- Background (active highlight / hover)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0)
        btn._bg = bg

        -- Bottom-edge underline (indicates active tab)
        local ul = btn:CreateTexture(nil, "ARTWORK")
        ul:SetHeight(2)
        ul:SetPoint("BOTTOMLEFT",  btn, "BOTTOMLEFT",  0, 0)
        ul:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
        ul:SetColorTexture(0, 0, 0, 0)
        btn._underline = ul

        -- Label
        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT",  btn, "LEFT",  8, 0)
        lbl:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
        lbl:SetJustifyH("CENTER")
        lbl:SetText(tab.label)
        lbl:SetTextColor(rgba(C.textMuted))
        btn._text = lbl

        -- Position
        if i == 1 then
            btn:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING, tabTopY)
        else
            btn:SetPoint("TOPLEFT", _tabButtons[TABS[i - 1].key], "TOPRIGHT", 0, 0)
        end

        -- Hover scripts
        btn:SetScript("OnEnter", function(self)
            if self._key ~= _activeTabKey then
                self._bg:SetColorTexture(1, 1, 1, 0.04)
                self._text:SetTextColor(rgba(C.text))
            end
            if tab.tip then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:SetText(tab.tip, nil, nil, nil, nil, true)
                GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self._key ~= _activeTabKey then
                self._bg:SetColorTexture(0, 0, 0, 0)
                self._text:SetTextColor(rgba(C.textMuted))
            end
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function(self)
            activateTab(self._key)
        end)

        _tabButtons[tab.key] = btn
    end

    -- Thin separator below tab bar.
    local tabSep = f:CreateTexture(nil, "ARTWORK")
    tabSep:SetHeight(1)
    tabSep:SetPoint("TOPLEFT",  f, "TOPLEFT",   PADDING,  tabTopY - TAB_BAR_H)
    tabSep:SetPoint("TOPRIGHT", f, "TOPRIGHT",  -PADDING, tabTopY - TAB_BAR_H)
    tabSep:SetColorTexture(rgba(C.cardBorder))

    -- ── Per-tab scroll frames ─────────────────────────────────────────────────
    -- Content area spans from just below the tab bar to the bottom of the window.
    local contentTopY    = tabTopY - TAB_BAR_H - 10
    local contentBottomY = PADDING

    -- Widgets.CreateScrollFrame hangs its scrollbar outside the scroll frame's right
    -- edge (8px gap + 6px bar), so inset the scroll frame by that much.
    local SCROLLBAR_W = 14
    local contentW = WIN_WIDTH - PADDING * 2 - SCROLLBAR_W

    for _, tab in ipairs(TABS) do
        if tab.build then
            -- Custom tabs manage their own scrolling: a plain frame over the content area.
            local panelFrame = CreateFrame("Frame", nil, f)
            panelFrame:SetPoint("TOPLEFT",     f, "TOPLEFT",     PADDING,  contentTopY)
            panelFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PADDING, contentBottomY)
            panelFrame:Hide()
            _tabPanels[tab.key] = { sf = panelFrame, content = panelFrame, built = false }
        else
            local sf, content = Widgets.CreateScrollFrame(f)
            sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     PADDING,       contentTopY)
            sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PADDING + SCROLLBAR_W), contentBottomY)
            sf:Hide()

            content:SetWidth(contentW)
            content:SetHeight(1)  -- grows after buildTabContent
            content._trackedControls = {}

            _tabPanels[tab.key] = { sf = sf, content = content, built = false }
        end
    end

    -- Refresh active tab controls whenever the window is shown.
    f:SetScript("OnShow", function()
        refreshTabControls(_activeTabKey)
    end)
    f:SetScript("OnHide", Widgets.CloseMenu)

    -- Activate the default tab (builds its content immediately).
    activateTab(_activeTabKey)

    _frame = f
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Public API
-- ─────────────────────────────────────────────────────────────────────────────

---@class SettingsWindow
local SettingsWindow = {}
CLN.SettingsWindow = SettingsWindow

--- Open (or bring to front) the settings window.
function SettingsWindow:Open()
    buildFrame()
    refreshTabControls(_activeTabKey)
    _frame:Show()
    _frame:Raise()
end

--- Close the settings window.
function SettingsWindow:Close()
    if _frame then _frame:Hide() end
end

--- Toggle visibility.
function SettingsWindow:Toggle()
    if _frame and _frame:IsShown() then
        self:Close()
    else
        self:Open()
    end
end

--- Refresh all built tab controls (call after profile changes).
function SettingsWindow:Refresh()
    for _, tab in ipairs(TABS) do
        local panel = _tabPanels[tab.key]
        if panel and panel.built then
            CLN.ConfigSystem._RefreshVisibleControls(panel.content)
        end
    end
end

--- Switch to a specific tab and open the window.
---@param tabKey string  One of: "general", "language", "library", "display", "npcs", "profiles", "developer"
function SettingsWindow:OpenTab(tabKey)
    buildFrame()
    activateTab(tabKey)
    _frame:Show()
    _frame:Raise()
end
