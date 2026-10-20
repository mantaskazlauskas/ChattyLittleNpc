---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local Widgets = CLN.Widgets

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- ============================================================================
-- FRAME STYLES
-- Visual themes for the conversation frame and the NPC portrait docked above
-- it. A style only changes looks (backgrounds, borders, nameplate, progress
-- bars, header colors); layout, behaviour and Edit Mode are shared by all.
-- Row text colors are left alone: they carry meaning (playing, entry type,
-- high-contrast mode).
-- ============================================================================

local WHITE  = "Interface\\Buttons\\WHITE8X8"
local CIRCLE = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local NAME_FONT = "Fonts\\MORPHEUS.TTF"

local GOLD = { 1.0, 0.82, 0.0, 1 }

local STYLES = {
    -- Frameless, like the objectives tracker (the original look).
    minimal = {
        label          = "Minimal",
        accent         = GOLD,
        frameBg        = nil,
        portraitBg     = nil,
        portraitBorder = nil,
        portraitShade  = false,  -- nothing behind the model: just the model
        letterbox      = false,
        nameplate      = nil,
        headerColor    = GOLD,
        divider        = { 1.0, 0.82, 0.0, 0.35 },
        buttons        = nil,
        subtitleBg     = { 0, 0, 0, 0.5 },
        subtitleBorder = nil,
        subtitleScale  = 1.0,
        rowTint        = nil,
        rowBar         = false,
        rowProgress    = 2,      -- px; 0 = none
        portraitProgress = false,
        portraitRegion = "bust", -- framing: "bust" (upper body), "portrait" (head and shoulders) or "head" (face)
        noCameraAnims  = false,  -- true keeps the framing still (no talk/emote camera moves)
    },
    -- Solid dark panel matching the settings window.
    panel = {
        label          = "Panel",
        accent         = { 1.0, 0.78, 0.20, 1 },
        frameBg        = { 0.055, 0.055, 0.07, 0.96 },
        frameBorder    = { 0.23, 0.23, 0.27, 1 },
        portraitBg     = { 0.03, 0.03, 0.045, 1 },
        portraitBorder = { 0.23, 0.23, 0.27, 1 },
        portraitShade  = false,
        letterbox      = false,
        nameplate      = "panel",
        headerColor    = { 1.0, 0.78, 0.20, 1 },
        divider        = { 1, 1, 1, 0.07 },
        buttons        = "box",
        subtitleBg     = { 0.09, 0.09, 0.115, 0.96 },
        subtitleBorder = { 0.23, 0.23, 0.27, 1 },
        subtitleScale  = 1.0,
        rowTint        = { 1.0, 0.78, 0.20, 0.08 },
        rowBar         = true,
        rowProgress    = 3,
        portraitProgress = false,
        portraitRegion = "bust",
        noCameraAnims  = false,
    },
    -- The portrait is the hero: face close-up, big name, film-style subtitles.
    -- Portrait and list share one translucent backing so they read as a column.
    cinematic = {
        label          = "Cinematic",
        accent         = GOLD,
        frameBg        = { 0, 0, 0, 0.45 },
        frameBorder    = nil,
        portraitBg     = { 0, 0, 0, 0.45 },
        portraitBorder = nil,
        portraitShade  = true,
        letterbox      = false,
        nameplate      = "cinematic",
        headerColor    = { 0.66, 0.66, 0.68, 1 },
        divider        = nil,
        buttons        = "round",
        subtitleBg     = { 0, 0, 0, 0.62 },
        subtitleBorder = nil,
        subtitleScale  = 1.25,
        rowTint        = nil,
        rowBar         = false,
        rowProgress    = 0,
        portraitProgress = true,
        portraitRegion = "portrait", -- head and shoulders
        noCameraAnims  = true,
        portraitMinAspect = 0.75,    -- above/below: at least 75% of the window width tall
    },
}
ReplayFrame.FrameStyles = STYLES
ReplayFrame.FrameStyleOrder = { "minimal", "panel", "cinematic" }

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

--- The active style definition (falls back to Minimal).
function ReplayFrame:GetFrameStyle()
    local key = CLN.db and CLN.db.profile and CLN.db.profile.frameStyle
    return STYLES[key] or STYLES.minimal
end

-- ----------------------------------------------------------------------------
-- Small drawing helpers
-- ----------------------------------------------------------------------------

--- Four 1px edge textures around `region`, returned so they can be toggled.
local function makeBorder(parent, region, layer)
    local lines = {}
    for i = 1, 4 do
        lines[i] = parent:CreateTexture(nil, layer or "BORDER")
    end
    lines[1]:SetPoint("TOPLEFT", region, "TOPLEFT");     lines[1]:SetPoint("TOPRIGHT", region, "TOPRIGHT");       lines[1]:SetHeight(1)
    lines[2]:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT"); lines[2]:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT"); lines[2]:SetHeight(1)
    lines[3]:SetPoint("TOPLEFT", region, "TOPLEFT");     lines[3]:SetPoint("BOTTOMLEFT", region, "BOTTOMLEFT");   lines[3]:SetWidth(1)
    lines[4]:SetPoint("TOPRIGHT", region, "TOPRIGHT");   lines[4]:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT"); lines[4]:SetWidth(1)
    return lines
end

local function showBorder(lines, color)
    for _, t in ipairs(lines) do
        if color then
            t:SetColorTexture(rgba(color))
            t:Show()
        else
            t:Hide()
        end
    end
end

--- Vertical gradient from `bottom` to `top` color; both client APIs, no-op if neither.
local function setVerticalGradient(tex, bottom, top)
    tex:SetTexture(WHITE)
    if CreateColor and tex.SetGradient then
        if pcall(tex.SetGradient, tex, "VERTICAL", CreateColor(rgba(bottom)), CreateColor(rgba(top))) then return end
    end
    if tex.SetGradientAlpha then
        pcall(tex.SetGradientAlpha, tex, "VERTICAL", bottom[1], bottom[2], bottom[3], bottom[4], top[1], top[2], top[3], top[4])
    end
end

--- 2px track + fill bar along the bottom of `parent`; returns { track, fill }.
local function makeProgressBar(parent, layer)
    local track = parent:CreateTexture(nil, layer or "OVERLAY", nil, 1)
    track:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT")
    track:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT")
    local fill = parent:CreateTexture(nil, layer or "OVERLAY", nil, 2)
    fill:SetPoint("BOTTOMLEFT", track, "BOTTOMLEFT")
    fill:SetPoint("TOPLEFT", track, "TOPLEFT")
    fill:SetWidth(1)
    track:Hide(); fill:Hide()
    return { track = track, fill = fill }
end

local function setProgress(bar, frac, height, accent)
    if not bar then return end
    if not frac or height <= 0 then
        bar.track:Hide(); bar.fill:Hide()
        return
    end
    frac = math.max(0, math.min(1, frac))
    bar.track:SetHeight(height)
    bar.track:SetColorTexture(1, 1, 1, 0.14)
    bar.fill:SetColorTexture(rgba(accent))
    local w = bar.track:GetWidth() or 0
    bar.fill:SetWidth(math.max(0.001, w * frac))
    bar.track:Show()
    bar.fill:Show()
end

-- ----------------------------------------------------------------------------
-- Decoration construction (lazy, once)
-- ----------------------------------------------------------------------------

function ReplayFrame:_EnsureStyleFrameBg()
    if self._styleFrameBg or not self.DisplayFrame then return self._styleFrameBg end
    local bg = CreateFrame("Frame", nil, self.DisplayFrame, "BackdropTemplate")
    bg:SetAllPoints(self.DisplayFrame)
    bg:SetFrameLevel(self.DisplayFrame:GetFrameLevel())
    bg:EnableMouse(false)
    self._styleFrameBg = bg
    return bg
end

function ReplayFrame:_EnsurePortraitDeco()
    local container = self.ModelContainer
    if self._portraitDeco or not container then return self._portraitDeco end

    local deco = {}
    -- Background behind the model (container's own texture draws under its children)
    deco.bg = container:CreateTexture(nil, "BACKGROUND", nil, -7)
    deco.bg:SetAllPoints(container)

    -- Overlay above the model for borders, bars, nameplate and progress
    local over = CreateFrame("Frame", nil, container)
    over:SetAllPoints(container)
    over:SetFrameLevel(container:GetFrameLevel() + 20)
    over:EnableMouse(false)
    -- Tells ModelFrame's stray-model-frame cleanup to leave this overlay alone
    over._clnStyleOverlay = true
    deco.over = over

    deco.border = makeBorder(over, over, "BORDER")

    deco.shade = over:CreateTexture(nil, "BACKGROUND")
    deco.shade:SetPoint("BOTTOMLEFT", over, "BOTTOMLEFT")
    deco.shade:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT")
    deco.shade:SetHeight(48)
    setVerticalGradient(deco.shade, { 0, 0, 0, 0.55 }, { 0, 0, 0, 0 })

    deco.barTop = over:CreateTexture(nil, "ARTWORK")
    deco.barTop:SetPoint("TOPLEFT", over, "TOPLEFT")
    deco.barTop:SetPoint("TOPRIGHT", over, "TOPRIGHT")
    deco.barTop:SetHeight(10)
    deco.barTop:SetColorTexture(0, 0, 0, 1)
    deco.barBottom = over:CreateTexture(nil, "ARTWORK")
    deco.barBottom:SetPoint("BOTTOMLEFT", over, "BOTTOMLEFT")
    deco.barBottom:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT")
    deco.barBottom:SetHeight(10)
    deco.barBottom:SetColorTexture(0, 0, 0, 1)

    -- Panel nameplate: dark strip along the bottom with accent tab, name, context
    local plate = CreateFrame("Frame", nil, over)
    plate:SetPoint("BOTTOMLEFT", over, "BOTTOMLEFT", 1, 1)
    plate:SetPoint("BOTTOMRIGHT", over, "BOTTOMRIGHT", -1, 1)
    plate:SetHeight(24)
    plate.bg = plate:CreateTexture(nil, "BACKGROUND")
    plate.bg:SetAllPoints()
    plate.bg:SetColorTexture(0.03, 0.03, 0.045, 0.78)
    plate.tab = plate:CreateTexture(nil, "ARTWORK")
    plate.tab:SetSize(3, 14)
    plate.tab:SetPoint("LEFT", plate, "LEFT", 8, 0)
    plate.name = plate:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    plate.name:SetPoint("LEFT", plate.tab, "RIGHT", 7, 0)
    plate.sub = plate:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    plate.sub:SetPoint("LEFT", plate.name, "RIGHT", 8, 0)
    plate.sub:SetPoint("RIGHT", plate, "RIGHT", -8, 0)
    plate.sub:SetJustifyH("LEFT")
    plate.sub:SetWordWrap(false)
    plate:Hide()
    deco.plate = plate

    -- Cinematic title: large display name with a small context line, bottom-left
    local title = CreateFrame("Frame", nil, over)
    title:SetPoint("BOTTOMLEFT", over, "BOTTOMLEFT", 12, 16)
    title:SetPoint("RIGHT", over, "RIGHT", -12, 0)
    title:SetHeight(40)
    title.name = title:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title.name:SetPoint("BOTTOMLEFT", title, "BOTTOMLEFT", 0, 14)
    -- WoW's display font; the font object above stays if it isn't available
    pcall(title.name.SetFont, title.name, NAME_FONT, 20, "OUTLINE")
    title.name:SetShadowOffset(1, -1)
    title.sub = title:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title.sub:SetPoint("BOTTOMLEFT", title, "BOTTOMLEFT", 1, 0)
    title.sub:SetPoint("RIGHT", title, "RIGHT")
    title.sub:SetJustifyH("LEFT")
    title.sub:SetWordWrap(false)
    title.sub:SetTextColor(0.82, 0.82, 0.85)
    title.sub:SetShadowOffset(1, -1)
    title:Hide()
    deco.title = title

    deco.progress = makeProgressBar(over, "OVERLAY")

    self._portraitDeco = deco
    -- Narrow side portraits need smaller/stacked name text
    container:HookScript("OnSizeChanged", function() self:_LayoutPortraitText() end)
    return deco
end

local NARROW_PLATE_W = 200 -- below this the panel nameplate stacks name over context

--- Fit the nameplate / cinematic title text to the portrait's current width.
function ReplayFrame:_LayoutPortraitText()
    local deco = self._portraitDeco
    local container = self.ModelContainer
    if not (deco and container) then return end
    local w = container:GetWidth() or 0
    if w <= 0 then return end

    -- Cinematic: name font scales with width (12-20px), both lines truncate
    local title = deco.title
    local size = math.max(12, math.min(20, math.floor(w / 12)))
    if title._fontSize ~= size then
        title._fontSize = size
        pcall(title.name.SetFont, title.name, NAME_FONT, size, "OUTLINE")
    end
    title.name:SetWidth(math.max(20, w - 24))
    title.name:SetWordWrap(false)
    title.name:SetJustifyH("LEFT")

    -- Panel: one line when wide; name over context when narrow
    local plate = deco.plate
    plate.name:SetWordWrap(false)
    plate.name:ClearAllPoints()
    plate.sub:ClearAllPoints()
    if w < NARROW_PLATE_W then
        plate:SetHeight(34)
        plate.name:SetPoint("TOPLEFT", plate.tab, "TOPRIGHT", 7, 1)
        plate.name:SetPoint("RIGHT", plate, "RIGHT", -6, 0)
        plate.sub:SetPoint("TOPLEFT", plate.name, "BOTTOMLEFT", 0, -2)
        plate.sub:SetPoint("RIGHT", plate, "RIGHT", -6, 0)
        plate.tab:SetHeight(26)
    else
        plate:SetHeight(24)
        plate.tab:SetHeight(14)
        plate.name:SetPoint("LEFT", plate.tab, "RIGHT", 7, 0)
        -- Natural width, capped so the context still fits beside it
        local natural = (plate.name.GetUnboundedStringWidth and plate.name:GetUnboundedStringWidth())
            or plate.name:GetStringWidth() or 0
        plate.name:SetWidth(math.max(20, math.min(natural + 2, w * 0.6)))
        plate.sub:SetPoint("LEFT", plate.name, "RIGHT", 8, 0)
        plate.sub:SetPoint("RIGHT", plate, "RIGHT", -8, 0)
    end
    plate.name:SetJustifyH("LEFT")
end

--- Background, border or round backing behind a header icon button.
local function styleHeaderButton(btn, mode)
    if not btn then return end
    if not btn._styleBox then
        btn._styleBox = btn:CreateTexture(nil, "BACKGROUND")
        btn._styleBox:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
        btn._styleBox:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -2)
        btn._styleBorder = makeBorder(btn, btn._styleBox, "BORDER")
        btn._styleRound = btn:CreateTexture(nil, "BACKGROUND")
        btn._styleRound:SetTexture(CIRCLE)
        btn._styleRound:SetPoint("CENTER")
        btn._styleRound:SetSize(24, 24)
        btn._styleRound:SetVertexColor(0, 0, 0, 0.55)
    end
    if mode == "box" then
        btn._styleBox:SetColorTexture(0.09, 0.09, 0.115, 1)
        btn._styleBox:Show()
        showBorder(btn._styleBorder, { 0.23, 0.23, 0.27, 1 })
        btn._styleRound:Hide()
    elseif mode == "round" then
        btn._styleBox:Hide()
        showBorder(btn._styleBorder, nil)
        btn._styleRound:Show()
    else
        btn._styleBox:Hide()
        showBorder(btn._styleBorder, nil)
        btn._styleRound:Hide()
    end
end

-- ----------------------------------------------------------------------------
-- Applying a style
-- ----------------------------------------------------------------------------

--- Apply the selected frame style to the conversation frame and portrait.
--- Safe to call repeatedly (on load, option change, profile switch).
function ReplayFrame:ApplyFrameStyle()
    if not self.DisplayFrame then return end
    local s = self:GetFrameStyle()

    -- Conversation frame background
    local bg = self:_EnsureStyleFrameBg()
    if bg then
        if s.frameBg then
            Widgets.ApplyBackdrop(bg, s.frameBg, s.frameBorder or { 0, 0, 0, 0 })
            bg:Show()
        else
            bg:Hide()
        end
    end

    -- Header title, divider and icon buttons
    if self.HeaderText then self.HeaderText:SetTextColor(rgba(s.headerColor)) end
    if self.HeaderDivider then
        -- No divider: keep the texture (the queue list anchors to it) but make
        -- it transparent; its alpha is animated by collapse/expand.
        self.HeaderDivider:SetColorTexture(rgba(s.divider or { 0, 0, 0, 0 }))
    end
    for _, btn in ipairs({ self.CollapseButton, self.ClearButton, self.OptionsButton, self.EditModeButton, self.LockButton }) do
        styleHeaderButton(btn, s.buttons)
    end

    -- Subtitle box
    if self.SubtitleFrame and self.SubtitleFrame.SetBackdrop then
        Widgets.ApplyBackdrop(self.SubtitleFrame, s.subtitleBg, s.subtitleBorder or { 0, 0, 0, 0 })
    end

    -- Portrait decoration
    local deco = self:_EnsurePortraitDeco()
    if deco then
        deco.over:Show()
        if s.portraitBg then
            deco.bg:SetColorTexture(rgba(s.portraitBg))
            deco.bg:Show()
        else
            deco.bg:Hide()
        end
        showBorder(deco.border, s.portraitBorder)
        deco.shade:SetShown(s.portraitShade and true or false)
        deco.barTop:SetShown(s.letterbox and true or false)
        deco.barBottom:SetShown(s.letterbox and true or false)
        deco.plate.tab:SetColorTexture(rgba(s.accent))
        deco.title.name:SetTextColor(rgba(s.accent))
        if not s.portraitProgress then setProgress(deco.progress, nil, 0) end
    end

    -- Re-lay out (close-ups drop the model offset) and re-frame the portrait
    if self.LayoutModelArea then self:LayoutModelArea(self.DisplayFrame) end
    if self._hasValidModel and self.ApplyDefaultFit then self:ApplyDefaultFit() end

    -- Queue rows: re-render so tint/bar/progress follow the new style
    -- (a hidden frame redraws its list when it is next shown)
    if self.DisplayFrame:IsShown() and self.RefreshQueueDataProvider then self:RefreshQueueDataProvider() end
    self:UpdateFrameStyleNameplate()
end

--- Fill the nameplate / cinematic title from what is playing now.
function ReplayFrame:UpdateFrameStyleNameplate()
    local deco = self._portraitDeco
    if not deco then return end
    local s = self:GetFrameStyle()
    local cur = CLN.VoiceoverPlayer and CLN.VoiceoverPlayer.currentlyPlaying
    local name = cur and cur.npcId and self.GetNpcNameById and self:GetNpcNameById(cur.npcId) or nil
    if (not name or name == "") and cur and cur.npcId and CLN.NpcMetadataCache then
        local cached = CLN.NpcMetadataCache:Lookup(cur.npcId)
        name = cached and cached.name
    end

    local context
    if cur and cur.questId then
        local questTitle = CLN.GetTitleForQuestID and CLN:GetTitleForQuestID(cur.questId) or nil
        context = questTitle and ("Quest · " .. questTitle) or "Quest"
    elseif cur and cur.entryType == "Gossip" then
        context = "Gossip"
    end

    local hasName = name and name ~= ""
    deco.plate:SetShown(s.nameplate == "panel" and hasName and true or false)
    deco.title:SetShown(s.nameplate == "cinematic" and hasName and true or false)
    if not hasName then return end

    deco.plate.name:SetText(name)
    deco.plate.sub:SetText(context or "")
    deco.title.name:SetText(name)
    deco.title.sub:SetText(context and string.upper(context) or "")
    self:_LayoutPortraitText()
end

--- Show/update style extras on one queue row (called from SetQueueData).
function ReplayFrame:ApplyFrameStyleToRow(row, element)
    local s = self:GetFrameStyle()
    if not row._styleTint then
        row._styleTint = row:CreateTexture(nil, "BACKGROUND")
        row._styleTint:SetAllPoints()
        row._styleBar = row:CreateTexture(nil, "ARTWORK")
        row._styleBar:SetPoint("TOPLEFT", row, "TOPLEFT")
        row._styleBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT")
        row._styleBar:SetWidth(3)
        row._styleProgress = makeProgressBar(row, "ARTWORK")
    end
    local playing = element and element.isPlaying and not element.isDivider
    if playing and s.rowTint then
        row._styleTint:SetColorTexture(rgba(s.rowTint))
        row._styleTint:Show()
    else
        row._styleTint:Hide()
    end
    if playing and s.rowBar then
        row._styleBar:SetColorTexture(rgba(s.accent))
        row._styleBar:Show()
    else
        row._styleBar:Hide()
    end
    -- The playing row's timer re-shows this when the line has a duration
    setProgress(row._styleProgress, nil, 0)
end

--- Playback progress (0..1) for the playing row; also drives the portrait bar.
--- frac = nil hides both.
function ReplayFrame:SetFrameStyleProgress(row, frac)
    local s = self:GetFrameStyle()
    if row and row._styleProgress then
        setProgress(row._styleProgress, frac, s.rowProgress or 0, s.accent)
    end
    local deco = self._portraitDeco
    if deco then
        setProgress(deco.progress, s.portraitProgress and frac or nil, 2, s.accent)
    end
end
