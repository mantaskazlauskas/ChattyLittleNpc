---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local Widgets = CLN.Widgets

-- ============================================================================
-- Whitelist Management Window
-- Standalone draggable window for managing the Native VO "Pause For" whitelist.
-- Provides a scrollable list of whitelisted NPCs with per-row remove buttons
-- and an add-by-name input at the bottom.
-- ============================================================================

local WIN_WIDTH  = 380
local WIN_HEIGHT = 440
local PADDING    = 12
local ROW_HEIGHT = 26

-- Inner width available for scroll content (accounts for scrollbar ~20px).
local SCROLL_CHILD_WIDTH = WIN_WIDTH - PADDING * 2 - 22

local _frame     = nil   ---@type Frame|nil
local _rowFrames = {}    -- reusable row Frame pool

-- ──────────────────────────────────────────────────────────────────────────────
-- Helpers (mirror Options.lua local helpers — kept local to this file)
-- ──────────────────────────────────────────────────────────────────────────────

--- Collect all known numeric IDs for npcName from baked and contribution DBs.
local function getKnownIdsForName(npcName)
    local ids = {}
    local baked = _G.KnownVoicedNpcsDB
    if baked and baked[npcName] and baked[npcName].ids then
        for _, id in ipairs(baked[npcName].ids) do ids[id] = true end
    end
    local contrib = _G.VoicedNpcContributions
    if contrib and contrib[npcName] and contrib[npcName].ids then
        for _, id in ipairs(contrib[npcName].ids) do ids[id] = true end
    end
    return ids
end

--- Remove npcName (and its known IDs) from the whitelist.
local function removeNpcFromWhitelist(npcName)
    if not (CLN.db and CLN.db.profile) then return end
    local wl = CLN.db.profile.nativeVOWhitelist
    if not wl then return end
    wl[npcName] = nil
    for id in pairs(getKnownIdsForName(npcName)) do wl[id] = nil end
end

--- Add npcName (and its known IDs) to the whitelist.
local function addNpcToWhitelist(npcName)
    if not (CLN.db and CLN.db.profile) then return end
    if not CLN.db.profile.nativeVOWhitelist then CLN.db.profile.nativeVOWhitelist = {} end
    local wl = CLN.db.profile.nativeVOWhitelist
    wl[npcName] = true
    for id in pairs(getKnownIdsForName(npcName)) do wl[id] = true end
end

--- Return a sorted list of NPC names (string keys only) currently whitelisted.
local function getWhitelistNames()
    local wl = CLN.db and CLN.db.profile and CLN.db.profile.nativeVOWhitelist or {}
    local names = {}
    for k, v in pairs(wl) do
        if v and type(k) == "string" then names[#names + 1] = k end
    end
    table.sort(names)
    return names
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Row management
-- ──────────────────────────────────────────────────────────────────────────────

local function refreshRows()
    if not (_frame and _frame._scrollChild) then return end
    local scrollChild = _frame._scrollChild
    local names = getWhitelistNames()

    -- Update or create rows.
    for i, npcName in ipairs(names) do
        local row = _rowFrames[i]
        if not row then
            row = CreateFrame("Frame", nil, scrollChild)
            row:SetHeight(ROW_HEIGHT)

            row._bg = row:CreateTexture(nil, "BACKGROUND")
            row._bg:SetAllPoints()

            row._label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row._label:SetPoint("LEFT",  row, "LEFT",  8, 0)
            row._label:SetPoint("RIGHT", row, "RIGHT", -72, 0)
            row._label:SetJustifyH("LEFT")
            if row._label.SetWordWrap then row._label:SetWordWrap(false) end

            row._btn = Widgets.CreateButton(row)
            row._btn:SetSize(64, 20)
            row._btn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            row._btn:SetText("Remove")

            _rowFrames[i] = row
        end

        -- Anchor
        row:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)

        -- Alternating row tint
        if i % 2 == 0 then
            row._bg:SetColorTexture(1, 1, 1, 0.04)
        else
            row._bg:SetColorTexture(0, 0, 0, 0)
        end

        row._label:SetText(npcName)

        -- Capture the name for the remove closure.
        local capturedName = npcName
        row._btn:SetScript("OnClick", function()
            removeNpcFromWhitelist(capturedName)
            refreshRows()
        end)

        row:Show()
    end

    -- Hide surplus rows from a previous (longer) list.
    for i = #names + 1, #_rowFrames do
        _rowFrames[i]:Hide()
    end

    -- Resize the scroll child to fit the current content.
    scrollChild:SetHeight(math.max(#names * ROW_HEIGHT, 1))

    -- Empty-state label
    if _frame._emptyLabel then
        if #names == 0 then
            _frame._emptyLabel:Show()
        else
            _frame._emptyLabel:Hide()
        end
    end

    -- Fade out and close when the list is now empty.
    if #names == 0 and _frame:IsShown() then
        local FADE_DURATION = 0.5
        local startAlpha = _frame:GetAlpha()
        local startTime  = GetTime and GetTime() or 0
        _frame:SetScript("OnUpdate", function(self)
            local elapsed = ((GetTime and GetTime()) or 0) - startTime
            local pct = math.min(elapsed / FADE_DURATION, 1)
            self:SetAlpha(startAlpha * (1 - pct))
            if pct >= 1 then
                self:SetScript("OnUpdate", nil)
                self:SetAlpha(1) -- restore so next Open() starts opaque
                self:Hide()
            end
        end)
    end
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Frame construction (called once on first open)
-- ──────────────────────────────────────────────────────────────────────────────

local function buildFrame()
    if _frame then return end

    local f = CreateFrame("Frame", "CLN_WhitelistWindow", UIParent, "BackdropTemplate")
    f:SetSize(WIN_WIDTH, WIN_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    Widgets.ApplyBackdrop(f, Widgets.Colors.windowBg, Widgets.Colors.windowBorder)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    -- Title bar
    local bar = Widgets.CreateTitleBar(f, "Chatty Little NPC", { subtitle = "Whitelist" })

    -- Count badge next to the subtitle (updated in refreshRows via f._countLabel)
    local countLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLabel:SetPoint("BOTTOMLEFT", bar.subtitle, "BOTTOMRIGHT", 6, 0)
    countLabel:SetTextColor(Widgets.rgba(Widgets.Colors.textMuted))
    f._countLabel = countLabel

    -- Description
    local sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", f, "TOPLEFT", PADDING + 2, -46)
    sub:SetText("NPCs whose native speech pauses addon playback.")
    sub:SetTextColor(Widgets.rgba(Widgets.Colors.textMuted))

    -- Separator
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT",  sub, "BOTTOMLEFT",  -2, -8)
    sep:SetPoint("TOPRIGHT", f,   "TOPRIGHT",   -PADDING, 0)
    sep:SetHeight(1)
    sep:SetColorTexture(Widgets.rgba(Widgets.Colors.cardBorder))

    -- Bottom bar: EditBox + Add button
    -- Add button sits flush at the right edge.
    local addBtn = Widgets.CreateButton(f)
    addBtn:SetSize(68, 24)
    addBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PADDING, PADDING)
    addBtn:SetText("Add")

    -- EditBox stretches between left edge and the Add button.
    local addBox = Widgets.CreateEditBox(f)
    addBox:SetHeight(24)
    addBox:SetPoint("BOTTOMLEFT",  f,      "BOTTOMLEFT",  PADDING,  PADDING)
    addBox:SetPoint("BOTTOMRIGHT", addBtn, "BOTTOMLEFT",  -6, 0)
    addBox:SetAutoFocus(false)
    addBox:SetMaxLetters(128)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Placeholder hint text (shown when box is empty and unfocused)
    local hint = addBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", addBox, "TOPLEFT", 8, 0)
    hint:SetPoint("BOTTOMRIGHT", addBox, "BOTTOMRIGHT", -8, 0)
    hint:SetJustifyH("LEFT")
    hint:SetText("NPC name…")
    -- HookScript keeps the edit box's own focus highlight.
    addBox:HookScript("OnEditFocusGained", function() hint:Hide() end)
    addBox:HookScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then hint:Show() end
    end)
    addBox:SetScript("OnTextChanged", function(self)
        hint:SetShown(self:GetText() == "" and not self:HasFocus())
    end)

    local function doAdd()
        local raw = addBox:GetText() or ""
        local name = raw:match("^%s*(.-)%s*$")
        if name == "" then return end
        addNpcToWhitelist(name)
        addBox:SetText("")
        hint:Show()
        addBox:ClearFocus()
        refreshRows()
    end

    addBtn:SetScript("OnClick", doAdd)
    addBox:SetScript("OnEnterPressed", function() doAdd() end)

    -- Scroll frame (fills the space between the separator and the bottom bar)
    local sf = Widgets.CreateScrollFrame(f)
    sf:SetPoint("TOPLEFT",    sep, "BOTTOMLEFT",  PADDING,        -4)
    sf:SetPoint("BOTTOMRIGHT", f,  "BOTTOMRIGHT", -(PADDING + 14), PADDING + 28 + 4)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(SCROLL_CHILD_WIDTH)
    sc:SetHeight(1) -- grows dynamically in refreshRows
    sf:SetScrollChild(sc)

    -- Empty-state label (shown when whitelist is empty)
    local emptyLabel = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyLabel:SetPoint("TOP", sc, "TOP", 0, -PADDING)
    emptyLabel:SetText("No NPCs in whitelist yet. Add one below.")
    emptyLabel:SetTextColor(0.45, 0.45, 0.45)
    emptyLabel:Hide()

    f._scrollChild = sc
    f._emptyLabel  = emptyLabel

    _frame = f
end

-- ──────────────────────────────────────────────────────────────────────────────
-- Public API attached to CLN namespace
-- ──────────────────────────────────────────────────────────────────────────────

---@class WhitelistWindow
local WhitelistWindow = {}
CLN.WhitelistWindow = WhitelistWindow

--- Open (or bring to front) the whitelist management window.
function WhitelistWindow:Open()
    buildFrame()
    refreshRows()
    _frame:Show()
    _frame:Raise()
end

--- Close the window if it is open.
function WhitelistWindow:Close()
    if _frame then _frame:Hide() end
end

--- Toggle visibility.
function WhitelistWindow:Toggle()
    if _frame and _frame:IsShown() then
        self:Close()
    else
        self:Open()
    end
end

--- Refresh the row list without toggling visibility (called externally after
--- whitelist changes made elsewhere, e.g. the native VO popup).
function WhitelistWindow:Refresh()
    if _frame and _frame:IsShown() then
        refreshRows()
    end
end
