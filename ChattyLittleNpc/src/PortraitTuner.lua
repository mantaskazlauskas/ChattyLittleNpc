-- PortraitTuner.lua - Window (Display settings) for tuning the portrait camera per shot
-- (the framing a frame style and dock side use: bust, side, portrait, ...).
-- Previews a model with the real portrait renderer at the portrait's size;
-- the camera height, side offset, zoom, angle and model facing can be tweaked,
-- emotes tried, and the result saved per shot (optionally per body type). Saved
-- tuning is read by ReplayFrame:GetShotTuning; the Lua line can be pasted into
-- ReplayFrame.ShotTuningDefaults (FrameStyles.lua) to make it the default.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local Widgets = CLN.Widgets

---@class PortraitTuner
local PortraitTuner = {}
CLN.PortraitTuner = PortraitTuner

PortraitTuner.shot = "bust"
PortraitTuner.perBodyType = false
PortraitTuner.values = {}

local PREVIEW_W, PREVIEW_H = 400, 330 -- largest preview; the portrait's aspect is kept inside it
local CONTROLS_X = PREVIEW_W + 28
local WINDOW_W, WINDOW_H = CONTROLS_X + 340, 640

local SHOTS = {
    bust       = "Bust (waist up)",
    side       = "Side (head to waist, narrow)",
    portrait   = "Portrait (head and shoulders)",
    head       = "Head",
    upper_body = "Upper body",
    full_body  = "Full body",
}
local SHOT_ORDER = { "bust", "side", "portrait", "head", "upper_body", "full_body" }

-- Field, label, min, max, step, neutral value
local SLIDERS = {
    { "height", "Height", -0.5, 0.5, 0.01, 0 },
    { "side",   "Side",   -0.5, 0.5, 0.01, 0 },
    { "zoom",   "Zoom",   0.5, 2.5, 0.05, 1 },
    { "pitch",  "Cam pitch", -45, 45, 1, 0 },
    { "orbit",  "Cam orbit", -90, 90, 1, 0 },
    { "facing", "Facing", -180, 180, 1, 0 },
}

local EMOTES = {
    { "Idle", 0 }, { "Talk", 60 }, { "Ask", 65 }, { "Exclaim", 64 }, { "Wave", 67 },
    { "Bow", 66 }, { "Nod", 185 }, { "No", 186 }, { "Point", 25 }, { "Salute", 113 },
}

local function round(v, step)
    return math.floor((tonumber(v) or 0) / step + 0.5) * step
end

local function neutralValues()
    local v = {}
    for _, s in ipairs(SLIDERS) do v[s[1]] = s[6] end
    return v
end

--- Which styles / dock sides use a shot, for the label under the dropdown.
local function shotUsers(shot)
    local RF = CLN.ReplayFrame
    local users = {}
    for _, key in ipairs(RF.FrameStyleOrder or {}) do
        local style = RF.FrameStyles[key]
        local region = style.portraitRegion or "bust"
        local sideRegion = region == "bust" and "side" or region
        local where = {}
        if region == shot then where[#where + 1] = "above/below" end
        if sideRegion == shot then where[#where + 1] = "left/right" end
        if #where > 0 then users[#users + 1] = style.label .. " (" .. table.concat(where, ", ") .. ")" end
    end
    return #users > 0 and ("Used by: " .. table.concat(users, ", ")) or "Not used by any frame style"
end

local function createSlider(f, anchor, spec)
    local field, label, minV, maxV, step = spec[1], spec[2], spec[3], spec[4], spec[5]
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
    text:SetWidth(70)
    text:SetJustifyH("LEFT")
    text:SetText(label)

    local s = Widgets.CreateSlider(f)
    s:SetPoint("LEFT", text, "RIGHT", 6, 0)
    s:SetWidth(200)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.step = step
    s.valueText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.valueText:SetPoint("LEFT", s, "RIGHT", 10, 0)
    s:SetScript("OnValueChanged", function(self, value)
        value = round(value, step)
        self.valueText:SetText(step < 1 and string.format("%.2f", value) or tostring(value))
        if self._silent then return end
        PortraitTuner.values[field] = value
        PortraitTuner:Reframe()
    end)
    s.label = text
    return s
end

local function createFrame()
    local f = CreateFrame("Frame", "CLN_PortraitTuner", UIParent, "BackdropTemplate")
    f:SetSize(WINDOW_W, WINDOW_H)
    Widgets.ApplyBackdrop(f, Widgets.Colors.windowBg, Widgets.Colors.windowBorder)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:Hide()
    tinsert(UISpecialFrames, "CLN_PortraitTuner") -- close with Escape

    Widgets.CreateTitleBar(f, "Chatty Little NPC", { subtitle = "Portrait Tuner" })

    -- Preview area; the model host is sized to the live portrait's aspect inside it
    local previewBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    previewBg:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -50)
    previewBg:SetSize(PREVIEW_W, PREVIEW_H)
    Widgets.ApplyBackdrop(previewBg, { 0, 0, 0, 0.35 }, Widgets.Colors.border)
    f.previewBg = previewBg

    local box = CreateFrame("Frame", nil, previewBg, "BackdropTemplate")
    box:SetPoint("CENTER")
    Widgets.ApplyBackdrop(box, { 0.03, 0.03, 0.045, 1 }, Widgets.Colors.cardBorder)
    box:SetClipsChildren(true)
    f.box = box

    local host = CLN.ReplayFrame:CreateModelHost(box, "CLN_PortraitTunerHost")
    host._isPreview = true -- renderers skip portrait-only state for it
    f.host = host

    -- Mouse layer over the model: drag orbits / tilts the camera, wheel zooms
    local mouse = CreateFrame("Frame", nil, box)
    mouse:SetAllPoints(box)
    mouse:SetFrameLevel(host:GetFrameLevel() + 20)
    mouse:EnableMouse(true)
    mouse:EnableMouseWheel(true)
    mouse:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self.dragX, self.dragY = GetCursorPosition() end
    end)
    mouse:SetScript("OnMouseUp", function(self) self.dragX, self.dragY = nil, nil end)
    mouse:SetScript("OnHide", function(self) self.dragX, self.dragY = nil, nil end)
    mouse:SetScript("OnUpdate", function(self)
        if not self.dragX then return end
        local x, y = GetCursorPosition()
        if x == self.dragX and y == self.dragY then return end
        local v = PortraitTuner.values
        v.orbit = math.max(-90, math.min(90, round(v.orbit + (x - self.dragX) * 0.4, 1)))
        v.pitch = math.max(-45, math.min(45, round(v.pitch + (y - self.dragY) * 0.4, 1)))
        self.dragX, self.dragY = x, y
        PortraitTuner:SyncSliders()
        PortraitTuner:Reframe()
    end)
    mouse:SetScript("OnMouseWheel", function(_, delta)
        local v = PortraitTuner.values
        v.zoom = math.max(0.5, math.min(2.5, round(v.zoom + delta * 0.05, 0.05)))
        PortraitTuner:SyncSliders()
        PortraitTuner:Reframe()
    end)

    f.sizeNote = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.sizeNote:SetPoint("TOPLEFT", previewBg, "BOTTOMLEFT", 2, -6)
    f.sizeNote:SetWidth(PREVIEW_W)
    f.sizeNote:SetJustifyH("LEFT")

    -- Model source
    local function button(text, width, onClick)
        local b = Widgets.CreateButton(f, text, width, 22)
        b:SetScript("OnClick", onClick)
        return b
    end
    f.modelLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.modelLabel:SetPoint("TOPLEFT", f.sizeNote, "BOTTOMLEFT", 0, -14)
    f.modelLabel:SetText("Model:")
    f.targetButton = button("Target", 70, function() PortraitTuner:LoadUnit("target") end)
    f.targetButton:SetPoint("LEFT", f.modelLabel, "RIGHT", 8, 0)
    f.playerButton = button("Me", 50, function() PortraitTuner:LoadUnit("player") end)
    f.playerButton:SetPoint("LEFT", f.targetButton, "RIGHT", 6, 0)
    f.displayInput = Widgets.CreateEditBox(f, 90, 22)
    f.displayInput:SetPoint("LEFT", f.playerButton, "RIGHT", 12, 0)
    f.displayInput:SetNumeric(true)
    f.displayInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        PortraitTuner:LoadDisplay(tonumber(self:GetText()))
    end)
    f.displayLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.displayLabel:SetPoint("LEFT", f.displayInput, "RIGHT", 6, 0)
    f.displayLabel:SetText("display ID, Enter")
    f.modelName = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.modelName:SetPoint("TOPLEFT", f.modelLabel, "BOTTOMLEFT", 0, -10)
    f.modelName:SetWidth(PREVIEW_W)
    f.modelName:SetJustifyH("LEFT")

    -- Emotes
    f.emoteLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.emoteLabel:SetPoint("TOPLEFT", f.modelName, "BOTTOMLEFT", 0, -14)
    f.emoteLabel:SetText("Emotes:")
    local prev
    for i, e in ipairs(EMOTES) do
        local b = button(e[1], 64, function() PortraitTuner:PlayAnim(e[2]) end)
        if i == 1 then
            b:SetPoint("TOPLEFT", f.emoteLabel, "BOTTOMLEFT", 0, -6)
        elseif i == 6 then
            b:SetPoint("TOPLEFT", f.emoteLabel, "BOTTOMLEFT", 0, -34)
        else
            b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        end
        prev = b
    end
    f.animInput = Widgets.CreateEditBox(f, 70, 22)
    f.animInput:SetPoint("TOPLEFT", f.emoteLabel, "BOTTOMLEFT", 0, -62)
    f.animInput:SetNumeric(true)
    f.animInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        PortraitTuner:PlayAnim(tonumber(self:GetText()))
    end)
    f.animLabel = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.animLabel:SetPoint("LEFT", f.animInput, "RIGHT", 6, 0)
    f.animLabel:SetText("any animation ID, Enter")

    -- Controls column
    f.shotLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.shotLabel:SetPoint("TOPLEFT", f, "TOPLEFT", CONTROLS_X, -54)
    f.shotLabel:SetText("Shot:")
    f.shot = Widgets.CreateDropdown(f, 250, {
        values = SHOTS,
        sorting = SHOT_ORDER,
        get = function() return PortraitTuner.shot end,
        set = function(value) PortraitTuner:SetShot(value) end,
    })
    f.shot:SetPoint("LEFT", f.shotLabel, "RIGHT", 10, 0)
    f.shotUsers = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.shotUsers:SetPoint("TOPLEFT", f.shotLabel, "BOTTOMLEFT", 0, -12)
    f.shotUsers:SetWidth(310)
    f.shotUsers:SetJustifyH("LEFT")

    f.bodyType = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.bodyType:SetPoint("TOPLEFT", f.shotUsers, "BOTTOMLEFT", 0, -10)
    f.perBodyType = Widgets.CreateCheckButton(f, "Save for this body type only", "GameFontHighlightSmall")
    f.perBodyType:SetPoint("TOPLEFT", f.bodyType, "BOTTOMLEFT", -2, -6)
    f.perBodyType:SetScript("OnClick", function(self)
        PortraitTuner.perBodyType = self:GetChecked() and true or false
        PortraitTuner:LoadSaved()
    end)
    f.state = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.state:SetPoint("TOPLEFT", f.perBodyType, "BOTTOMLEFT", 2, -6)

    f.sliders = {}
    local anchor = f.state
    for i, spec in ipairs(SLIDERS) do
        local s = createSlider(f, anchor, spec)
        if i == 1 then s.label:SetPoint("TOPLEFT", f.state, "BOTTOMLEFT", 0, -16) end
        f.sliders[spec[1]] = s
        anchor = s.label
    end

    f.saveButton = button("Save", 90, function() PortraitTuner:Save() end)
    f.saveButton:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -20)
    f.resetButton = button("Reset", 70, function() PortraitTuner:ResetSaved() end)
    f.resetButton:SetPoint("LEFT", f.saveButton, "RIGHT", 8, 0)
    f.resetAllButton = button("Reset all", 80, function() StaticPopup_Show("CLN_RESET_PORTRAIT_TUNING") end)
    f.resetAllButton:SetPoint("LEFT", f.resetButton, "RIGHT", 8, 0)
    f.neutralButton = button("Zero", 60, function()
        PortraitTuner.values = neutralValues()
        PortraitTuner:SyncSliders()
        PortraitTuner:Reframe()
    end)
    f.neutralButton:SetPoint("LEFT", f.resetAllButton, "RIGHT", 8, 0)

    -- Lua line for ReplayFrame.ShotTuningDefaults (click, Ctrl+C)
    f.luaLine = Widgets.CreateEditBox(f, 310, 22)
    f.luaLine:SetPoint("TOPLEFT", f.saveButton, "BOTTOMLEFT", 0, -12)
    f.luaLine:SetFontObject("GameFontHighlightSmall")
    f.luaLine:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    f.luaLine:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(PortraitTuner:LuaLine()) self:HighlightText() end
    end)

    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
    f.hint:SetText("Drag the model to orbit and tilt the camera, scroll to zoom. Save applies to the live portrait.")
    return f
end

--- Size the preview like the live portrait (same aspect), scaled to fit.
function PortraitTuner:MatchPortraitSize()
    local f = self.frame
    local RF = CLN.ReplayFrame
    local w, h
    if RF.ModelContainer and RF.ModelContainer.GetSize then w, h = RF.ModelContainer:GetSize() end
    local measured = w and h and w > 10 and h > 10
    if not measured then w, h = 320, 184 end
    local scale = math.min(1, PREVIEW_W / w, PREVIEW_H / h)
    self._previewScale = scale
    f.box:SetSize(w * scale, h * scale)
    f.sizeNote:SetText(string.format("Preview: %dx%d%s (%s portrait)", w, h,
        scale < 1 and string.format(", shown at %d%%", scale * 100) or "",
        measured and "current" or "default"))
    self:LayoutHost()
end

--- Place the model in the box as the live portrait does (ReplayFrame layout):
--- the bust shot sits 10% lower, extended below so the shift doesn't shrink it.
function PortraitTuner:LayoutHost()
    local f = self.frame
    -- Same base as the live layout: the saved model height, not the container's
    local liveH = CLN.ReplayFrame.npcModelFrameHeight or math.floor(140 * 1.15)
    local drop = (self.shot == "bust") and math.floor(liveH * 0.10 * (self._previewScale or 1)) or 0
    f.host:ClearAllPoints()
    f.host:SetPoint("TOPLEFT", f.box, "TOPLEFT", 0, -drop)
    f.host:SetPoint("BOTTOMRIGHT", f.box, "BOTTOMRIGHT", 0, -2 * drop)
end

--- Key the current tuning saves to: the shot, or shot:bodyType.
function PortraitTuner:SaveKey()
    local class = self.frame and self.frame.host and self.frame.host._lastFrameClass
    if self.perBodyType and class then return self.shot .. ":" .. class end
    return self.shot
end

function PortraitTuner:LuaLine()
    local parts = {}
    for _, s in ipairs(SLIDERS) do
        local v = self.values[s[1]]
        if v and v ~= s[6] then
            parts[#parts + 1] = s[1] .. " = " .. (s[5] < 1 and string.format("%.2f", v) or tostring(v))
        end
    end
    return string.format('["%s"] = { %s },', self:SaveKey(), table.concat(parts, ", "))
end

function PortraitTuner:SyncSliders()
    local f = self.frame
    for field, s in pairs(f.sliders) do
        s._silent = true
        s:SetValue(self.values[field])
        s._silent = false
        s.valueText:SetText(s.step < 1 and string.format("%.2f", self.values[field]) or tostring(self.values[field]))
    end
    f.luaLine:SetText(self:LuaLine())
    f.luaLine:SetCursorPosition(0)
end

--- Re-frame the preview with the current (unsaved) tuning.
function PortraitTuner:Reframe()
    local f = self.frame
    if not f then return end
    local host = f.host
    host._portraitRegion = self.shot
    host._tuningPreview = self.values
    host._userControlledCamera = false
    if host.FrameFullBodyFront_Immediate then
        host:FrameFullBodyFront_Immediate(0.12)
    elseif host.FitDefault then
        host:FitDefault()
    end
    local class = host._lastFrameClass
    f.bodyType:SetText("Body type: " .. (class or "unknown (PlayerModel renderer)"))
    f.perBodyType:SetEnabled(class ~= nil)
    f.luaLine:SetText(self:LuaLine())
    f.luaLine:SetCursorPosition(0)
end

--- Load the saved (or default) tuning for the current key into the sliders.
function PortraitTuner:LoadSaved()
    local f = self.frame
    local key = self:SaveKey()
    local saved = CLN.db.profile.portraitShotTuning or {}
    local t = saved[key] or CLN.ReplayFrame.ShotTuningDefaults[key]
    self.values = neutralValues()
    if t then
        for k, v in pairs(t) do self.values[k] = v end
    end
    f.state:SetText(saved[key] and ("|cff80ff80saved|r as " .. key)
        or (CLN.ReplayFrame.ShotTuningDefaults[key] and ("built-in default for " .. key))
        or ("nothing saved for " .. key))
    f.resetButton:SetEnabled(saved[key] ~= nil)
    f.resetAllButton:SetEnabled(next(saved) ~= nil)
    self:SyncSliders()
    self:Reframe()
end

function PortraitTuner:SetShot(shot)
    self.shot = shot
    self.frame.shotUsers:SetText(shotUsers(shot))
    self:LayoutHost()
    self:LoadSaved()
end

--- Re-frame once the model has loaded (loads are asynchronous).
function PortraitTuner:AfterLoad()
    local host = self.frame.host
    self._loadToken = (self._loadToken or 0) + 1
    local token, tries = self._loadToken, 0
    local function poll()
        if self._loadToken ~= token then return end
        tries = tries + 1
        local be = host._backend
        local loaded
        if be and be.actor and be.actor.IsLoaded then
            loaded = be.actor:IsLoaded()
        elseif be and be.frame and be.frame.GetModelFileID then
            local fid = be.frame:GetModelFileID()
            loaded = fid and fid > 0
        end
        if loaded then
            self:Reframe()
            -- Body type is known after the first framing; re-read saved tuning for it
            if self.perBodyType then self:LoadSaved() end
        elseif tries < 60 then
            C_Timer.After(0.05, poll)
        end
    end
    C_Timer.After(0.05, poll)
end

function PortraitTuner:LoadUnit(unit)
    local f = self.frame
    if not UnitExists(unit) then
        f.modelName:SetText("|cffff8080No " .. unit .. "|r")
        return
    end
    f.host:ClearModel()
    f.host:Show()
    f.host:SetUnit(unit)
    f.modelName:SetText((UnitName(unit) or "?") .. "  (" .. unit .. ")")
    self:AfterLoad()
end

function PortraitTuner:LoadDisplay(displayID)
    local f = self.frame
    if not displayID then return end
    f.host:ClearModel()
    f.host:Show()
    f.host:SetDisplayInfo(displayID)
    f.modelName:SetText("Display ID " .. displayID)
    self:AfterLoad()
end

function PortraitTuner:PlayAnim(animId)
    local host = self.frame.host
    if animId and host.SetAnimation then host:SetAnimation(animId) end
end

--- Refit the live portrait so a saved change shows right away.
local function refitLivePortrait()
    local RF = CLN.ReplayFrame
    if RF.NpcModelFrame and RF.NpcModelFrame:IsShown() and RF.ApplyDefaultFit then
        RF:ApplyDefaultFit(nil)
    end
end

function PortraitTuner:Save()
    local key = self:SaveKey()
    local t = {}
    for _, s in ipairs(SLIDERS) do
        local v = self.values[s[1]]
        if v and v ~= s[6] then t[s[1]] = v end
    end
    CLN.db.profile.portraitShotTuning = CLN.db.profile.portraitShotTuning or {}
    CLN.db.profile.portraitShotTuning[key] = t
    if CLN.Logger then
        CLN.Logger:info("Portrait shot " .. self:LuaLine(), true, CLN.Utils.LogCategories.ui)
    end
    self:LoadSaved()
    refitLivePortrait()
end

function PortraitTuner:ResetSaved()
    local saved = CLN.db.profile.portraitShotTuning
    if saved then saved[self:SaveKey()] = nil end
    self:LoadSaved()
    refitLivePortrait()
end

--- Drop every saved shot tuning, back to the built-in defaults.
function PortraitTuner:ResetAll()
    CLN.db.profile.portraitShotTuning = {}
    if self.frame and self.frame:IsShown() then self:LoadSaved() end
    refitLivePortrait()
end

StaticPopupDialogs["CLN_RESET_PORTRAIT_TUNING"] = {
    text = "Reset the portrait camera for all shots to the defaults?",
    button1 = "Reset",
    button2 = "Cancel",
    OnAccept = function() PortraitTuner:ResetAll() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function PortraitTuner:Show()
    self.frame = self.frame or createFrame()
    self.frame:Show()
    self.frame:Raise()
    -- Start on the shot the current style and dock side use
    local current = CLN.ReplayFrame.GetPortraitRegion and CLN.ReplayFrame:GetPortraitRegion()
    self.shot = SHOTS[current] and current or self.shot
    self:MatchPortraitSize()
    self.frame.shot:Refresh()
    self.frame.perBodyType:SetChecked(self.perBodyType)
    self.frame.shotUsers:SetText(shotUsers(self.shot))
    self:LoadSaved()
    if UnitExists("target") then self:LoadUnit("target") else self:LoadUnit("player") end
end

function PortraitTuner:Hide()
    if self.frame then self.frame:Hide() end
end

function PortraitTuner:Toggle()
    if self.frame and self.frame:IsShown() then self:Hide() else self:Show() end
end
