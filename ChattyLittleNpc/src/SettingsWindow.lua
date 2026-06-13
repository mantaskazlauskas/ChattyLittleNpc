---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- ============================================================================
-- Settings Window
-- Tabbed popup window providing the primary settings UI for the addon.
-- Groups option settings into logical tabs so related controls stay together.
-- Based on the same draggable-popup pattern as WhitelistWindow.
-- ============================================================================

local WIN_WIDTH  = 660
local WIN_HEIGHT = 530
local PADDING    = 12
local TAB_BAR_H  = 30     -- height of the tab strip
local HEADER_H   = 42     -- height occupied by the title + separator

-- Each tab maps to one or more option-group keys from CLN.OptionsDefinition.args.
local TABS = {
    {
        key    = "general",
        label  = "General",
        groups = { "Playback" },
        tip    = "Playback behaviour, audio channel, keybind and gossip settings.",
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
        btn._bg:SetColorTexture(1, 0.82, 0, 0.15)
        btn._text:SetTextColor(1, 0.82, 0)
        btn._underline:SetColorTexture(1, 0.82, 0, 1)
    else
        btn._bg:SetColorTexture(0, 0, 0, 0)
        btn._text:SetTextColor(0.65, 0.65, 0.65)
        btn._underline:SetColorTexture(0, 0, 0, 0)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Content building
-- ─────────────────────────────────────────────────────────────────────────────

--- Build the controls for one tab's scroll content on first activation.
local function buildTabContent(tabDef, panel)
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
    f:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile     = true, tileSize = 16, edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
    f:SetBackdropBorderColor(0.25, 0.22, 0.20, 0.80)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    -- Register so Escape closes the window.
    tinsert(UISpecialFrames, "CLN_SettingsWindow")

    -- ── Close button ─────────────────────────────────────────────────────────
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetSize(26, 26)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- ── Title ────────────────────────────────────────────────────────────────
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING + 2, -PADDING)
    title:SetText("Chatty Little NPC  —  Settings")
    title:SetTextColor(1.0, 0.82, 0.0)

    -- Thin separator below title.
    local titleSep = f:CreateTexture(nil, "ARTWORK")
    titleSep:SetHeight(1)
    titleSep:SetPoint("TOPLEFT",  f, "TOPLEFT",   PADDING,  -HEADER_H + 2)
    titleSep:SetPoint("TOPRIGHT", f, "TOPRIGHT",  -PADDING, -HEADER_H + 2)
    titleSep:SetColorTexture(0.3, 0.3, 0.3, 0.6)

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
        lbl:SetTextColor(0.65, 0.65, 0.65)
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
                self._bg:SetColorTexture(1, 1, 1, 0.06)
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
    tabSep:SetColorTexture(0.3, 0.3, 0.3, 0.6)

    -- ── Per-tab scroll frames ─────────────────────────────────────────────────
    -- Content area spans from just below the tab bar to the bottom of the window.
    local contentTopY    = tabTopY - TAB_BAR_H - 2
    local contentBottomY = PADDING

    -- Scroll content width: window minus padding on both sides minus scrollbar (~20px).
    local contentW = WIN_WIDTH - PADDING * 2 - 22

    for _, tab in ipairs(TABS) do
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT",     f, "TOPLEFT",     PADDING,       contentTopY)
        sf:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(PADDING + 4), contentBottomY)
        sf:Hide()

        local content = CreateFrame("Frame", nil, sf)
        content:SetWidth(contentW)
        content:SetHeight(1)  -- grows after buildTabContent
        sf:SetScrollChild(content)
        content._trackedControls = {}

        _tabPanels[tab.key] = { sf = sf, content = content, built = false }
    end

    -- Refresh active tab controls whenever the window is shown.
    f:SetScript("OnShow", function()
        refreshTabControls(_activeTabKey)
    end)

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
---@param tabKey string  One of: "general", "display", "npcs", "profiles", "developer"
function SettingsWindow:OpenTab(tabKey)
    buildFrame()
    activateTab(tabKey)
    _frame:Show()
    _frame:Raise()
end
