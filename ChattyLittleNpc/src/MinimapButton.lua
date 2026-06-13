---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- ============================================================================
-- Minimap Button
-- A circular icon button docked to the minimap edge, matching the style used
-- by addons like DBM, WeakAuras, etc.
--
-- Left-click  → toggle Settings window
-- Right-click → toggle the Voiceover replay frame
-- Drag        → reposition around the minimap edge (angle saved to profile)
-- ============================================================================

local ICON_SIZE     = 31          -- diameter of the button (px) — standard minimap addon size
local RING_SIZE     = 56          -- border ring rendered larger than button (standard addon style)
local ICON_RADIUS_PAD = 5         -- extra gap between minimap edge and button centre
local DEFAULT_ANGLE = math.pi     -- 180° = left side of minimap

-- ─────────────────────────────────────────────────────────────────────────────
-- Angle → screen position helpers
-- ─────────────────────────────────────────────────────────────────────────────

--- Return the radius used for positioning (minimap half-width + padding + icon half).
local function getRadius()
    local mm = Minimap
    if mm then
        return (mm:GetWidth() / 2) + ICON_RADIUS_PAD + (ICON_SIZE / 2)
    end
    return 85  -- sensible fallback if Minimap not yet available
end

--- Apply an angle (radians) to the button's position around the minimap.
local function applyAngle(btn, angle)
    local r = getRadius()
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

--- Compute angle from cursor position relative to the minimap centre.
local function angleFromCursor()
    local mx, my = Minimap:GetCenter()
    -- GetCursorPosition returns scaled UI coords on Retail; divide by UIParent scale.
    local scale  = UIParent:GetScale()
    local cx, cy = GetCursorPosition()
    cx = cx / scale
    cy = cy / scale
    return math.atan2(cy - my, cx - mx)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Module
-- ─────────────────────────────────────────────────────────────────────────────

---@class MinimapButton
local MinimapButton = {}
CLN.MinimapButton = MinimapButton

local _btn = nil  ---@type Button|nil

--- Build and show the minimap button.  Idempotent.
function MinimapButton:Create()
    if _btn then return end

    local btn = CreateFrame("Button", "CLN_MinimapButton", Minimap)
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetClampedToScreen(true)

    -- ── Icon texture ──────────────────────────────────────────────────────────
    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetSize(ICON_SIZE - 8, ICON_SIZE - 8)
    tex:SetPoint("CENTER", btn, "CENTER", 0, 0)
    tex:SetTexture("Interface\\AddOns\\ChattyLittleNpc\\Icons\\ChattyLittleNpc.png")
    btn.tex = tex

    -- Circular mask so the square icon is clipped into a circle.
    local mask = btn:CreateMaskTexture(nil, "ARTWORK")
    mask:SetTexture("Interface/CHARACTERFRAME/TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(tex)
    tex:AddMaskTexture(mask)

    -- ── Border ring — TOPLEFT-anchored to compensate for texture's internal offset ──
    local ring = btn:CreateTexture(nil, "OVERLAY")
    ring:SetSize(RING_SIZE, RING_SIZE)
    ring:SetPoint("TOPLEFT", btn, "TOPLEFT", -2, 2)
    ring:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
    btn.ring = ring

    -- ── Highlight overlay ─────────────────────────────────────────────────────
    local hi = btn:CreateTexture(nil, "HIGHLIGHT")
    hi:SetAllPoints()
    hi:SetTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")
    hi:SetBlendMode("ADD")

    -- ── Tooltip ───────────────────────────────────────────────────────────────
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Chatty Little NPC", 1, 0.82, 0)
        GameTooltip:AddLine("Left-click: Open Settings", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Right-click: Toggle Voiceover Frame", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Drag: Reposition", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- ── Click handling ────────────────────────────────────────────────────────
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if CLN.SettingsWindow then
                CLN.SettingsWindow:Toggle()
            elseif CLN.Options and CLN.Options.OpenSettings then
                CLN.Options:OpenSettings()
            end
        elseif button == "RightButton" then
            if CLN.ReplayFrame and CLN.ReplayFrame.ToggleUserHidden then
                CLN.ReplayFrame:ToggleUserHidden()
            elseif CLN.ReplayFrame and CLN.ReplayFrame.DisplayFrame then
                local df = CLN.ReplayFrame.DisplayFrame
                if df:IsShown() then
                    df:Hide()
                else
                    df:Show()
                end
            end
        end
    end)

    -- ── Dragging around the minimap edge ─────────────────────────────────────
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        self._dragging = true
        self:SetScript("OnUpdate", function(b)
            if not b._dragging then return end
            local angle = angleFromCursor()
            applyAngle(b, angle)
            b._angle = angle
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self._dragging = false
        self:SetScript("OnUpdate", nil)
        -- Persist the new angle.
        if CLN.db and CLN.db.profile then
            CLN.db.profile.minimapButtonAngle = self._angle or DEFAULT_ANGLE
        end
    end)

    -- ── Initial position ──────────────────────────────────────────────────────
    local angle = (CLN.db and CLN.db.profile and CLN.db.profile.minimapButtonAngle) or DEFAULT_ANGLE
    btn._angle = angle
    applyAngle(btn, angle)

    btn:Show()
    _btn = btn
end

--- Show the button (create if needed).
function MinimapButton:Show()
    if not _btn then self:Create() end
    _btn:Show()
end

--- Hide the button.
function MinimapButton:Hide()
    if _btn then _btn:Hide() end
end
