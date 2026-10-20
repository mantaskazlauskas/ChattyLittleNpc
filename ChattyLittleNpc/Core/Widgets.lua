-- Widgets.lua - Custom-skinned UI widgets
-- Flat dark controls (switch, checkbox, slider, dropdown, button, edit box,
-- scroll frame) shared by the settings window and other addon panels.
-- Built from colour textures plus a few stock textures present on every
-- supported client, so they look the same from Classic Era to Retail.
--
-- Widgets set their own OnEnter/OnLeave scripts for hover visuals; callers
-- that need extra hover behaviour must use HookScript, not SetScript.

---@class Widgets
local Widgets = {}

local WHITE  = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local ARROW  = "Interface\\ChatFrame\\ChatFrameExpandArrow"
local CHECK  = "Interface\\Buttons\\UI-CheckBox-Check"

-- Shared palette as { r, g, b, a }.
local C = {
    windowBg     = { 0.055, 0.055, 0.070, 0.97 },
    windowBorder = { 0.20,  0.20,  0.24,  1 },
    titleBg      = { 1, 1, 1, 0.03 },
    cardBg       = { 1, 1, 1, 0.025 },
    cardBorder   = { 1, 1, 1, 0.07 },
    rowHover     = { 1, 1, 1, 0.04 },
    controlBg    = { 0.11, 0.11, 0.14, 1 },
    controlHover = { 0.15, 0.15, 0.19, 1 },
    menuBg       = { 0.08, 0.08, 0.10, 0.98 },
    border       = { 0.26, 0.26, 0.31, 1 },
    borderHover  = { 0.45, 0.45, 0.52, 1 },
    track        = { 0.22, 0.22, 0.27, 1 },
    knobOff      = { 0.72, 0.72, 0.76, 1 },
    knobOn       = { 0.08, 0.08, 0.10, 1 },
    scrollTrack  = { 1, 1, 1, 0.04 },
    scrollThumb  = { 1, 1, 1, 0.22 },
    accent       = { 1.00, 0.78, 0.20, 1 },
    accentSoft   = { 1.00, 0.78, 0.20, 0.25 },
    text         = { 0.92, 0.92, 0.94, 1 },
    textMuted    = { 0.60, 0.60, 0.65, 1 },
    textHeader   = { 1.00, 0.82, 0.00, 1 },
}
Widgets.Colors = C

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end
Widgets.rgba = rgba

local function mix(a, b, t)
    return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t,
           a[3] + (b[3] - a[3]) * t, (a[4] or 1) + ((b[4] or 1) - (a[4] or 1)) * t
end

local FLAT_BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

--- Give a BackdropTemplate frame a flat fill and a 1px border.
function Widgets.ApplyBackdrop(frame, bg, border)
    frame:SetBackdrop(FLAT_BACKDROP)
    frame:SetBackdropColor(rgba(bg or C.controlBg))
    frame:SetBackdropBorderColor(rgba(border or C.border))
end

--- Texture tinted to a palette colour (WHITE by default, or a mask file such as CIRCLE).
local function solid(parent, layer, color, file, sublevel)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetTexture(file or WHITE)
    t:SetVertexColor(rgba(color))
    return t
end
Widgets.Solid = solid

--- Draw a 1px border around an existing region using four textures on its parent.
--- layer defaults to BORDER; use HIGHLIGHT for a hover-only border on buttons.
function Widgets.AddBorder(parent, region, color, layer)
    local function line()
        local t = parent:CreateTexture(nil, layer or "BORDER")
        t:SetColorTexture(rgba(color or C.cardBorder))
        return t
    end
    local top, bottom, left, right = line(), line(), line(), line()
    top:SetHeight(1)
    top:SetPoint("TOPLEFT", region, "TOPLEFT")
    top:SetPoint("TOPRIGHT", region, "TOPRIGHT")
    bottom:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT")
    left:SetWidth(1)
    left:SetPoint("TOPLEFT", region, "TOPLEFT")
    left:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT")
    right:SetWidth(1)
    right:SetPoint("TOPRIGHT", region, "TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT")
end

function Widgets.PlayClick(on)
    if PlaySound and SOUNDKIT then
        PlaySound(on == false and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end
end

-- 8-value tex coords (UL, LL, UR, LR) that point the stock right-arrow another way.
local ARROW_COORDS = {
    right = { 0, 0, 0, 1, 1, 0, 1, 1 },
    left  = { 1, 0, 1, 1, 0, 0, 0, 1 },
    down  = { 0, 1, 1, 1, 0, 0, 1, 0 },
}

local function createArrow(parent, direction, size)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(ARROW)
    t:SetDesaturated(true)
    t:SetTexCoord(unpack(ARROW_COORDS[direction]))
    t:SetSize(size or 12, size or 12)
    t:SetVertexColor(rgba(C.textMuted))
    return t
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hover / focus state for boxed controls (button, dropdown, edit box)
-- ─────────────────────────────────────────────────────────────────────────────

local function refreshBox(f)
    local active = f._focus or f._open
    local hot = f._hover or active
    f:SetBackdropColor(rgba(hot and C.controlHover or C.controlBg))
    f:SetBackdropBorderColor(rgba(active and C.accent or f._hover and C.borderHover or C.border))
    if f._arrow then f._arrow:SetVertexColor(rgba(hot and C.accent or C.textMuted)) end
end

local function hookBoxHover(f)
    f:SetScript("OnEnter", function(self) self._hover = true;  refreshBox(self) end)
    f:SetScript("OnLeave", function(self) self._hover = false; refreshBox(self) end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Button
-- ─────────────────────────────────────────────────────────────────────────────

local function buttonFitToText(self, minWidth)
    self:SetWidth(math.max(minWidth or 0, math.ceil(self.Text:GetStringWidth()) + 28))
end

local function buttonSetActive(self, active)
    self._focus = active and true or false
    refreshBox(self)
end

--- Flat button with a centred label.
--- Hover, press and disabled looks use native button states (no scripts), so
--- callers are free to SetScript OnEnter/OnLeave/OnClick.
---@return table
function Widgets.CreateButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(width or 120, height or 22)
    Widgets.ApplyBackdrop(b)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("CENTER")
    b:SetFontString(fs)
    b:SetNormalFontObject(GameFontHighlight)
    b:SetHighlightFontObject(GameFontHighlight)
    b:SetDisabledFontObject(GameFontDisable)
    b:SetPushedTextOffset(1, -1)
    b.Text = fs
    b:SetText(text or "")

    local hover = b:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("TOPLEFT", 1, -1)
    hover:SetPoint("BOTTOMRIGHT", -1, 1)
    hover:SetColorTexture(1, 1, 1, 0.05)
    Widgets.AddBorder(b, b, C.borderHover, "HIGHLIGHT")

    b.FitToText = buttonFitToText
    b.SetActive = buttonSetActive
    return b
end

--- Small square button showing an arrow (used as slider steppers).
function Widgets.CreateArrowButton(parent, direction, size)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(size or 18, size or 18)
    Widgets.ApplyBackdrop(b)
    b._arrow = createArrow(b, direction, 10)
    b._arrow:SetPoint("CENTER")
    hookBoxHover(b)
    return b
end

--- Title bar across the top of a window: tinted strip, addon icon, title,
--- optional subtitle and a close button. Dragging the bar moves the window
--- (when it is movable).
--- opts = { height = 36, subtitle = string?, onClose = fn?, onDragStop = fn? }
---@return table bar  bar.title, bar.subtitle and bar.close are exposed
function Widgets.CreateTitleBar(f, titleText, opts)
    opts = opts or {}
    local height = opts.height or 36

    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    bar:SetHeight(height - 1)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() if f:IsMovable() then f:StartMoving() end end)
    bar:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if opts.onDragStop then opts.onDragStop() end
    end)

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(rgba(C.titleBg))

    local sep = bar:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
    sep:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT")
    sep:SetColorTexture(rgba(C.cardBorder))

    local iconSize = math.max(16, height - 18)
    local icon = bar:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("LEFT", bar, "LEFT", 10, 0)
    icon:SetTexture("Interface\\AddOns\\ChattyLittleNpc\\Icons\\ChattyLittleNpc.png")

    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    title:SetText(titleText or "")
    title:SetTextColor(rgba(C.textHeader))
    bar.title = title

    local subtitle = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
    subtitle:SetTextColor(rgba(C.textMuted))
    subtitle:SetText(opts.subtitle or "")
    bar.subtitle = subtitle

    local close = Widgets.CreateCloseButton(bar)
    close:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
    close:SetScript("OnClick", function()
        if opts.onClose then opts.onClose() else f:Hide() end
    end)
    bar.close = close

    return bar
end

--- Borderless close "X" drawn from two rotated bars.
function Widgets.CreateCloseButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.75, 0.18, 0.18, 0)
    local bars = {}
    for i, angle in ipairs({ 45, -45 }) do
        local bar = solid(b, "ARTWORK", C.textMuted)
        bar:SetSize(12, 2)
        bar:SetPoint("CENTER")
        bar:SetRotation(math.rad(angle))
        bars[i] = bar
    end
    local function paint(hover)
        bg:SetColorTexture(0.75, 0.18, 0.18, hover and 0.7 or 0)
        for _, bar in ipairs(bars) do bar:SetVertexColor(rgba(hover and C.text or C.textMuted)) end
    end
    b:SetScript("OnEnter", function() paint(true) end)
    b:SetScript("OnLeave", function() paint(false) end)
    return b
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Toggle switch
-- ─────────────────────────────────────────────────────────────────────────────

local SWITCH_W, SWITCH_H, KNOB = 32, 16, 12

local function drawSwitch(sw)
    local p = sw._pos
    for _, t in ipairs(sw._track) do t:SetVertexColor(mix(C.track, C.accent, p)) end
    sw._knob:SetVertexColor(mix(C.knobOff, C.knobOn, p))
    sw._knob:SetPoint("LEFT", sw, "LEFT", 2 + p * (SWITCH_W - KNOB - 4), 0)
end

local function animateSwitch(sw, elapsed)
    local target = sw._checked and 1 or 0
    local step = elapsed * 8
    if math.abs(target - sw._pos) <= step then
        sw._pos = target
        sw:SetScript("OnUpdate", nil)
    else
        sw._pos = sw._pos + (target > sw._pos and step or -step)
    end
    drawSwitch(sw)
end

local function switchSetChecked(self, checked)
    self._checked = checked and true or false
    local target = self._checked and 1 or 0
    if self._pos == target then return end
    if self:IsVisible() then
        self:SetScript("OnUpdate", animateSwitch)
    else
        self._pos = target
        drawSwitch(self)
    end
end

--- Pill-shaped on/off switch. Set an OnClick script to handle toggling.
function Widgets.CreateSwitch(parent)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(SWITCH_W, SWITCH_H)
    -- Track: two round caps joined by a bar.
    local capL = solid(sw, "BACKGROUND", C.track, CIRCLE)
    capL:SetSize(SWITCH_H, SWITCH_H)
    capL:SetPoint("LEFT")
    local capR = solid(sw, "BACKGROUND", C.track, CIRCLE)
    capR:SetSize(SWITCH_H, SWITCH_H)
    capR:SetPoint("RIGHT")
    local bar = solid(sw, "BACKGROUND", C.track)
    bar:SetPoint("TOPLEFT", sw, "TOPLEFT", SWITCH_H / 2, 0)
    bar:SetPoint("BOTTOMRIGHT", sw, "BOTTOMRIGHT", -SWITCH_H / 2, 0)
    sw._track = { capL, capR, bar }
    sw._knob = solid(sw, "ARTWORK", C.knobOff, CIRCLE)
    sw._knob:SetSize(KNOB, KNOB)
    sw._pos, sw._checked = 0, false
    drawSwitch(sw)
    sw.SetChecked = switchSetChecked
    sw.GetChecked = function(self) return self._checked end
    return sw
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Checkbox
-- ─────────────────────────────────────────────────────────────────────────────

local function checkButtonSetLabel(self, text)
    self.Text:SetText(text or "")
    -- Let clicks on the label toggle too.
    self:SetHitRectInsets(0, -(math.ceil(self.Text:GetStringWidth()) + 8), 0, 0)
end

--- Square checkbox (a real CheckButton, so it toggles itself before OnClick
--- runs and GetChecked/SetChecked behave natively) with a label to its right.
--- font defaults to GameFontHighlight.
---@return table
function Widgets.CreateCheckButton(parent, text, font)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(20, 20)

    local box = solid(cb, "BACKGROUND", C.border)
    box:SetSize(16, 16)
    box:SetPoint("CENTER")
    local fill = solid(cb, "BORDER", C.controlBg)
    fill:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
    Widgets.AddBorder(cb, box, C.accent, "HIGHLIGHT")

    cb:SetCheckedTexture(CHECK)
    local check = cb:GetCheckedTexture()
    check:ClearAllPoints()
    check:SetSize(20, 20)
    check:SetPoint("CENTER", box, "CENTER", 1, 0)
    cb:SetDisabledCheckedTexture(CHECK)
    local disabledCheck = cb:GetDisabledCheckedTexture()
    disabledCheck:ClearAllPoints()
    disabledCheck:SetSize(20, 20)
    disabledCheck:SetPoint("CENTER", box, "CENTER", 1, 0)
    disabledCheck:SetDesaturated(true)

    local label = cb:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetTextColor(rgba(C.text))
    cb.Text = label
    cb.text = label  -- name used by older call sites
    cb.SetLabel = checkButtonSetLabel
    cb:SetLabel(text)
    return cb
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Slider
-- ─────────────────────────────────────────────────────────────────────────────

--- Horizontal slider: thin track, accent fill up to a round thumb.
--- Width comes from SetWidth or from left/right anchors.
---@return table
function Widgets.CreateSlider(parent)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(16)
    s:SetHitRectInsets(0, 0, -6, -6)

    local track = solid(s, "BACKGROUND", C.track)
    track:SetHeight(4)
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)

    s:SetThumbTexture(CIRCLE)
    local thumb = s:GetThumbTexture()
    thumb:SetDrawLayer("OVERLAY")
    thumb:SetSize(14, 14)
    thumb:SetVertexColor(rgba(C.accent))

    local fill = solid(s, "BORDER", C.accent)
    fill:SetHeight(4)
    fill:SetPoint("LEFT", track, "LEFT", 0, 0)
    fill:SetPoint("RIGHT", thumb, "CENTER", 0, 0)

    local glow = solid(s, "ARTWORK", C.accentSoft, CIRCLE)
    glow:SetSize(24, 24)
    glow:SetPoint("CENTER", thumb, "CENTER", 0, 0)
    glow:Hide()

    s:SetScript("OnEnter", function(self) if self:IsEnabled() then glow:Show() end end)
    s:SetScript("OnLeave", function() glow:Hide() end)
    return s
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Dropdown + shared popup menu
-- ─────────────────────────────────────────────────────────────────────────────

local MENU_ROW_H    = 20
local MENU_MAX_ROWS = 12
local menu, catcher

local function closeMenu()
    if not menu or not menu:IsShown() then return end
    local owner = menu.owner
    menu:Hide()
    catcher:Hide()
    menu.owner = nil
    if owner then
        owner._open = false
        refreshBox(owner)
    end
end
Widgets.CloseMenu = closeMenu

local function renderMenu()
    local items, offset = menu.items, menu.offset
    for i, row in ipairs(menu.rows) do
        local item = items[i + offset]
        if item and i <= menu.visible then
            local selected = item.value == menu.current
            row.value = item.value
            row.Text:SetText(item.text)
            row.Text:SetTextColor(rgba(selected and C.accent or C.text))
            row.selBar:SetShown(selected)
            row:Show()
        else
            row:Hide()
        end
    end
    local overflow = #items - menu.visible
    if overflow > 0 then
        local trackH = menu.visible * MENU_ROW_H
        local thumbH = math.max(12, trackH * menu.visible / #items)
        menu.scrollThumb:SetHeight(thumbH)
        menu.scrollThumb:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -2, -2 - (trackH - thumbH) * offset / overflow)
        menu.scrollThumb:Show()
    else
        menu.scrollThumb:Hide()
    end
end

local function buildMenu()
    -- Invisible full-screen layer under the menu: any click outside closes it.
    catcher = CreateFrame("Frame", nil, UIParent)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata("FULLSCREEN_DIALOG")
    catcher:EnableMouse(true)
    catcher:SetScript("OnMouseDown", closeMenu)
    catcher:Hide()

    menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
    menu:SetClampedToScreen(true)
    Widgets.ApplyBackdrop(menu, C.menuBg, C.border)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    menu:SetScript("OnMouseWheel", function(self, delta)
        local maxOffset = math.max(0, #self.items - self.visible)
        self.offset = math.min(maxOffset, math.max(0, self.offset - delta))
        renderMenu()
    end)
    menu:Hide()

    menu.measure = menu:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    menu.scrollThumb = solid(menu, "OVERLAY", C.scrollThumb)
    menu.scrollThumb:SetWidth(3)

    menu.rows = {}
    for i = 1, MENU_MAX_ROWS do
        local row = CreateFrame("Button", nil, menu)
        row:SetHeight(MENU_ROW_H)
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -2 - (i - 1) * MENU_ROW_H)
        row:SetPoint("RIGHT", menu, "RIGHT", -1, 0)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.07)
        local selBar = solid(row, "ARTWORK", C.accent)
        selBar:SetWidth(2)
        selBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -2)
        selBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 2)
        row.selBar = selBar
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("LEFT", row, "LEFT", 10, 0)
        fs:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(false)
        row.Text = fs
        row:SetScript("OnClick", function(self)
            local owner, value = menu.owner, self.value
            closeMenu()
            Widgets.PlayClick(true)
            if owner then owner:Select(value) end
        end)
        menu.rows[i] = row
    end
end

local function resolveValues(values)
    if type(values) == "function" then values = values() end
    return values or {}
end

--- Ordered { value, text } list: info.sorting order if given, else by text.
local function menuItems(values, sorting)
    local items = {}
    if sorting then
        for _, value in ipairs(sorting) do
            if values[value] ~= nil then items[#items + 1] = { value = value, text = tostring(values[value]) } end
        end
    else
        for value, text in pairs(values) do items[#items + 1] = { value = value, text = tostring(text) } end
        table.sort(items, function(a, b)
            if a.text == b.text then return tostring(a.value) < tostring(b.value) end
            return a.text < b.text
        end)
    end
    return items
end

local function openMenu(owner)
    if not menu then buildMenu() end
    local items = menuItems(resolveValues(owner.opts.values), owner.opts.sorting)
    if #items == 0 then return end
    local current = owner.opts.get()

    menu.owner, menu.items, menu.current = owner, items, current
    menu.visible = math.min(#items, MENU_MAX_ROWS)

    -- Start scrolled so the current value is visible.
    menu.offset = 0
    for i, item in ipairs(items) do
        if item.value == current and i > menu.visible then menu.offset = i - menu.visible end
    end

    -- Widen past the owner when a label would otherwise be cut off.
    local width = owner:GetWidth()
    for _, item in ipairs(items) do
        menu.measure:SetText(item.text)
        width = math.max(width, menu.measure:GetStringWidth() + 28)
    end
    menu.measure:SetText("")

    local height = menu.visible * MENU_ROW_H + 4
    menu:SetSize(width, height)
    menu:ClearAllPoints()
    local bottom = owner:GetBottom()
    if bottom and bottom * owner:GetEffectiveScale() < (height + 8) * menu:GetEffectiveScale() then
        menu:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", 0, 2)
    else
        menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    end

    renderMenu()
    catcher:Show()
    menu:Show()
    owner._open = true
    refreshBox(owner)
end

local function dropdownRefresh(self)
    local values = resolveValues(self.opts.values)
    local current = self.opts.get()
    self.Text:SetText(current ~= nil and tostring(values[current] or current) or "")
end

local function dropdownSelect(self, value)
    self.opts.set(value)
    self:Refresh()
end

--- Dropdown box. opts = { values = table|fn, sorting = array?, get = fn(), set = fn(value) }.
--- Call :Refresh() to redraw the current value.
---@return table
function Widgets.CreateDropdown(parent, width, opts)
    local dd = CreateFrame("Button", nil, parent, "BackdropTemplate")
    dd:SetSize(width or 200, 24)
    Widgets.ApplyBackdrop(dd)
    dd.opts = opts

    local fs = dd:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", dd, "LEFT", 8, 0)
    fs:SetPoint("RIGHT", dd, "RIGHT", -24, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetTextColor(rgba(C.text))
    dd.Text = fs

    dd._arrow = createArrow(dd, "down", 12)
    dd._arrow:SetPoint("RIGHT", dd, "RIGHT", -7, 0)

    hookBoxHover(dd)
    dd:SetScript("OnClick", function(self)
        if menu and menu:IsShown() and menu.owner == self then
            closeMenu()
        else
            closeMenu()
            Widgets.PlayClick(true)
            openMenu(self)
        end
    end)
    dd:SetScript("OnHide", function(self)
        if menu and menu.owner == self then closeMenu() end
    end)
    dd:SetScript("OnDisable", function(self)
        if menu and menu.owner == self then closeMenu() end
    end)

    dd.Refresh = dropdownRefresh
    dd.Select = dropdownSelect
    return dd
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Edit box
-- ─────────────────────────────────────────────────────────────────────────────

--- Single-line edit box with focus highlight.
---@return table
function Widgets.CreateEditBox(parent, width, height)
    local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    eb:SetSize(width or 200, height or 24)
    Widgets.ApplyBackdrop(eb)
    eb:SetFontObject("GameFontHighlight")
    eb:SetTextColor(rgba(C.text))
    eb:SetTextInsets(8, 8, 0, 0)
    eb:SetAutoFocus(false)
    hookBoxHover(eb)
    eb:SetScript("OnEditFocusGained", function(self) self._focus = true;  refreshBox(self) end)
    eb:SetScript("OnEditFocusLost",   function(self) self._focus = false; refreshBox(self) end)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    return eb
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Scroll frame
-- ─────────────────────────────────────────────────────────────────────────────

local SCROLL_STEP = 40

--- Scroll frame with a slim scrollbar just outside its right edge (14px incl. gap).
--- Set the returned content frame's width; its height drives the scroll range.
---@return ScrollFrame sf, Frame content
function Widgets.CreateScrollFrame(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)

    local bar = CreateFrame("Slider", nil, sf)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPLEFT", sf, "TOPRIGHT", 8, 0)
    bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 8, 0)
    local track = solid(bar, "BACKGROUND", C.scrollTrack)
    track:SetAllPoints()
    bar:SetThumbTexture(WHITE)
    local thumb = bar:GetThumbTexture()
    thumb:SetSize(6, 40)
    thumb:SetVertexColor(rgba(C.scrollThumb))
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:SetScript("OnValueChanged", function(_, value) sf:SetVerticalScroll(value) end)
    bar:SetScript("OnEnter", function() thumb:SetVertexColor(rgba(C.accent)) end)
    bar:SetScript("OnLeave", function() thumb:SetVertexColor(rgba(C.scrollThumb)) end)
    bar:Hide()

    local function update()
        local range = sf:GetVerticalScrollRange()
        if range < 1 then
            bar:SetMinMaxValues(0, 0)
            bar:Hide()
            sf:SetVerticalScroll(0)
            return
        end
        local viewH = sf:GetHeight()
        thumb:SetHeight(math.max(24, viewH * viewH / (viewH + range)))
        bar:SetMinMaxValues(0, range)
        bar:SetValue(math.min(sf:GetVerticalScroll(), range))
        bar:Show()
    end
    sf:SetScript("OnScrollRangeChanged", update)
    sf:SetScript("OnSizeChanged", update)

    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta)
        local range = sf:GetVerticalScrollRange()
        bar:SetValue(math.min(range, math.max(0, sf:GetVerticalScroll() - delta * SCROLL_STEP)))
    end)

    sf.ScrollBar = bar
    return sf, content
end

-- Export globally for the addon
_G.ChattyLittleNpc = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc.Widgets = Widgets

return Widgets
