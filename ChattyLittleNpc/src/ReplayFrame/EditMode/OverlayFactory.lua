---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local EditMode = ReplayFrame.EditMode

-- ============================================================================
-- Overlay Factory
-- ============================================================================
-- Creates and manages visual overlays for each Edit Mode window controller.
-- Each controller (ConversationWindow, ModelWindow) gets one overlay that
-- provides visual state feedback, drag/resize interaction, keyboard nudging,
-- tooltips, and a layout badge.
-- ============================================================================

local OverlayFactory = {}
EditMode.OverlayFactory = OverlayFactory

-- ============================================================================
-- Visual State Definitions
-- ============================================================================

local STATES = {
    default = {
        fill   = { 0.30, 0.30, 0.30, 0.05 },
        border = { 0.50, 0.45, 0.35, 0.40 },
        showLabel = false,
        showHint  = false,
    },
    hovered = {
        fill   = { 0.30, 0.60, 0.90, 0.20 },
        border = { 0.40, 0.70, 1.00, 0.80 },
        showLabel = false,
        showHint  = "Click to Edit",
    },
    selected = {
        fill   = { 0.69, 0.57, 0.31, 0.35 },
        border = { 0.82, 0.69, 0.35, 0.90 },
        showLabel = true,
        showHint  = false,
    },
    dragging = {
        fill   = { 0.69, 0.57, 0.31, 0.25 },
        border = { 0.90, 0.75, 0.40, 1.00 },
        showLabel = true,
        showHint  = false,
    },
    resizing = {
        fill   = { 0.69, 0.57, 0.31, 0.30 },
        border = { 0.82, 0.69, 0.35, 0.90 },
        showLabel = true,
        showHint  = false,
    },
    locked = {
        fill   = { 0.40, 0.40, 0.40, 0.10 },
        border = { 0.50, 0.50, 0.50, 0.50 },
        showLabel = true,
        showHint  = "Locked",
    },
}

-- Private overlay storage keyed by controller.id
local overlays = {}

-- ============================================================================
-- Helpers
-- ============================================================================

local function logDebug(msg)
    if CLN and CLN.Logger then
        CLN.Logger:debug(msg, false, CLN.Utils.LogCategories.ui)
    end
end

--- Determine the correct idle visual state for a controller.
---@param controller table
---@return string stateName
local function resolveIdleState(controller)
    if controller.locked then return "locked" end
    if controller.hovered then return "hovered" end
    return "default"
end

--- Build the label text for a controller in a given state.
---@param controller table
---@param stateName string
---@return string
local function getLabelText(controller, stateName)
    if stateName == "resizing" then
        local f = controller.frame
        if f and f.GetSize then
            local w, h = f:GetSize()
            -- U+00D7 (×) in UTF-8
            return string.format("%d \195\151 %d", math.floor(w + 0.5), math.floor(h + 0.5))
        end
    end
    if stateName == "locked" then
        -- U+1F512 (🔒) in UTF-8
        return "\240\159\148\146 " .. (controller.label or controller.id)
    end
    return controller.label or controller.id
end

--- Save position to legacy profile keys and persist to the active layout.
---@param controller table
local function saveAndPersist(controller)
    if controller.id == "conversation" then
        if ReplayFrame.SaveFramePosition then
            ReplayFrame:SaveFramePosition()
        end
    elseif controller.id == "model" then
        if ReplayFrame.SaveModelPosition then
            ReplayFrame:SaveModelPosition()
        end
    end

    local Persistence = EditMode.Persistence
    if Persistence then
        Persistence:PersistAll()
        Persistence:SyncToLegacyProfile()
    end
end

--- Visually deselect the previously-selected controller (if any).
--- Call after Registry:Select() to sync the old selection's overlay.
---@param excludeId string|nil  The newly-selected id to skip
local function deselectPrevious(excludeId)
    local Registry = EditMode.Registry
    if not Registry then return end
    Registry:ForEach(function(id, ctrl)
        if id ~= excludeId and ctrl.overlay and overlays[id] then
            OverlayFactory:SetState(ctrl, resolveIdleState(ctrl))
        end
    end)
end

-- ============================================================================
-- Overlay Construction (local builders — defined before createOverlay)
-- ============================================================================

--- Create the layout badge (dark pill at TOPLEFT).
---@param ov Frame
local function createLayoutBadge(ov)
    local holder = CreateFrame("Frame", nil, ov, "BackdropTemplate")
    holder:SetPoint("TOPLEFT", 6, -6)
    holder:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    holder:SetBackdropColor(0.05, 0.05, 0.05, 0.70)
    holder:SetBackdropBorderColor(0.30, 0.30, 0.30, 0.50)
    holder:SetSize(10, 18)
    holder:Hide()

    local text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 5, 0)
    text:SetText("")

    ov._badgeHolder = holder
    ov._badgeText = text
end

--- Refresh layout badge text and visibility from Persistence.
---@param ov Frame
local function refreshLayoutBadge(ov)
    if not ov._badgeHolder then return end

    local Persistence = EditMode.Persistence
    if not Persistence then
        ov._badgeHolder:Hide()
        return
    end

    local name = Persistence:GetActiveLayoutName()
    if name and name ~= "" then
        ov._badgeText:SetText(name)
        local textWidth = ov._badgeText:GetStringWidth() or 0
        ov._badgeHolder:SetWidth(textWidth + 12)
        ov._badgeHolder:Show()
    else
        ov._badgeHolder:Hide()
    end
end

--- Create the resize grip (18×18, bottom-right).
---@param ov Frame
---@param controller table
local function createResizeGrip(ov, controller)
    local grip = CreateFrame("Frame", nil, ov)
    grip:SetPoint("BOTTOMRIGHT")
    grip:SetSize(18, 18)
    grip:EnableMouse(true)

    local tex = grip:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")

    local texDown = grip:CreateTexture(nil, "OVERLAY")
    texDown:SetAllPoints()
    texDown:SetTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
    texDown:Hide()

    grip:SetScript("OnMouseDown", function(_, btn)
        if btn ~= "LeftButton" then return end
        if controller.locked then return end
        if InCombatLockdown() then return end

        local parent = controller.frame
        if not parent then return end

        parent:StartSizing("BOTTOMRIGHT")
        texDown:Show()
        tex:Hide()
        OverlayFactory:SetState(controller, "resizing")
    end)

    grip:SetScript("OnMouseUp", function(_, btn)
        if btn ~= "LeftButton" then return end
        local parent = controller.frame
        if parent then
            parent:StopMovingOrSizing()
        end

        texDown:Hide()
        tex:Show()
        OverlayFactory:SetState(controller, "selected")
        saveAndPersist(controller)

        if controller.id == "conversation" and ReplayFrame.Relayout then
            ReplayFrame:Relayout()
        end
    end)

    ov._resizeGrip = grip
end

--- Wire all interaction scripts onto the overlay.
---@param ov Frame
---@param controller table
local function wireInteraction(ov, controller)
    local parent = controller.frame
    if not parent then return end

    parent:SetMovable(true)
    parent:SetClampedToScreen(true)

    ov:EnableMouse(true)
    ov:RegisterForDrag("LeftButton")
    ov:EnableKeyboard(true)
    ov:SetPropagateKeyboardInput(true)

    -- ====== OnEnter ======
    ov:SetScript("OnEnter", function(self)
        controller.hovered = true
        if not controller.selected
           and ov._state ~= "dragging"
           and ov._state ~= "resizing" then
            OverlayFactory:SetState(controller, "hovered")
        end

        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:ClearLines()
            if controller.locked then
                -- U+2014 (—) in UTF-8
                GameTooltip:AddLine("Locked \226\128\148 unlock to drag/resize", 0.85, 0.85, 0.85, true)
            else
                -- U+00B7 (·) in UTF-8
                GameTooltip:AddLine("Drag to move \194\183 Arrows to nudge", 0.85, 0.85, 0.85, true)
            end
            GameTooltip:Show()
        end
    end)

    -- ====== OnLeave ======
    ov:SetScript("OnLeave", function()
        controller.hovered = false
        if not controller.selected
           and ov._state ~= "dragging"
           and ov._state ~= "resizing" then
            OverlayFactory:SetState(controller, "default")
        end
        if GameTooltip_Hide then GameTooltip_Hide() end
    end)

    -- ====== Click detection (OnMouseDown + OnMouseUp) ======
    ov:SetScript("OnMouseDown", function(self, btn)
        if btn ~= "LeftButton" then return end
        self._clickStartTime = GetTime()
        local x, y = GetCursorPosition()
        self._clickStartX = x
        self._clickStartY = y
    end)

    ov:SetScript("OnMouseUp", function(self, btn)
        if btn ~= "LeftButton" then return end
        if ov._state == "dragging" or ov._state == "resizing" then return end

        local x, y = GetCursorPosition()
        local dx = (x or 0) - (self._clickStartX or 0)
        local dy = (y or 0) - (self._clickStartY or 0)
        local dist2 = dx * dx + dy * dy
        local elapsed = GetTime() - (self._clickStartTime or 0)

        if dist2 < 625 and elapsed < 0.75 then
            local Registry = EditMode.Registry
            if Registry then
                Registry:Select(controller.id, "overlay")
            end
            OverlayFactory:SetState(controller, "selected")
            deselectPrevious(controller.id)

            if ReplayFrame.ShowEditPanel then
                ReplayFrame:ShowEditPanel()
            end
        end
    end)

    -- ====== OnDragStart ======
    ov:SetScript("OnDragStart", function()
        if controller.locked then return end
        if InCombatLockdown() then return end

        -- Select on drag start
        local Registry = EditMode.Registry
        if Registry and Registry:GetSelected() ~= controller.id then
            Registry:Select(controller.id, "overlay")
            deselectPrevious(controller.id)
        end

        -- Undock model if docked before dragging
        if controller.id == "model" and controller.IsDocked and controller:IsDocked() then
            controller:Undock()
        end

        OverlayFactory:SetState(controller, "dragging")
        parent:StartMoving()
    end)

    -- ====== OnDragStop ======
    ov:SetScript("OnDragStop", function()
        parent:StopMovingOrSizing()
        OverlayFactory:SetState(controller, "selected")
        saveAndPersist(controller)
        -- TODO: SnapManager integration (Phase 3)
    end)

    -- ====== OnKeyDown (keyboard nudging + Tab cycling + Escape) ======
    ov:SetScript("OnKeyDown", function(self, key)
        if not controller.selected then
            self:SetPropagateKeyboardInput(true)
            return
        end

        -- Arrow keys: nudge position
        local isArrow = (key == "LEFT" or key == "RIGHT" or key == "UP" or key == "DOWN")
        if isArrow then
            self:SetPropagateKeyboardInput(false)
            if controller.locked then return end

            local px = 5
            if IsShiftKeyDown() then px = 1 end
            if IsControlKeyDown() then px = 20 end

            local dx, dy = 0, 0
            if key == "LEFT" then dx = -px
            elseif key == "RIGHT" then dx = px
            elseif key == "UP" then dy = px
            elseif key == "DOWN" then dy = -px
            end

            -- Undock model if docked before nudging
            if controller.id == "model" and controller.IsDocked and controller:IsDocked() then
                controller:Undock()
            end

            local f = controller.frame
            if f then
                local p, _, r, x, y = f:GetPoint(1)
                f:ClearAllPoints()
                f:SetPoint(p or "CENTER", UIParent, r or "BOTTOMLEFT", (x or 0) + dx, (y or 0) + dy)
                saveAndPersist(controller)
            end
            return
        end

        -- Tab / Shift+Tab: cycle selection
        if key == "TAB" then
            self:SetPropagateKeyboardInput(false)
            local Registry = EditMode.Registry
            if Registry then
                if IsShiftKeyDown() then
                    Registry:CycleSelection(true)
                else
                    Registry:CycleSelection()
                end
                -- Update all overlay visuals after cycling
                local newId = Registry:GetSelected()
                Registry:ForEach(function(id, ctrl)
                    if overlays[id] then
                        if id == newId then
                            OverlayFactory:SetState(ctrl, "selected")
                        else
                            OverlayFactory:SetState(ctrl, resolveIdleState(ctrl))
                        end
                    end
                end)
            end
            return
        end

        -- Escape: deselect all
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            local Registry = EditMode.Registry
            if Registry then
                Registry:Select(nil)
                deselectPrevious(nil)
            end
            return
        end

        -- All other keys: pass through
        self:SetPropagateKeyboardInput(true)
    end)
end

--- Create the full overlay frame for a controller.
---@param controller table CLNWindowController
---@return Frame|nil
local function createOverlay(controller)
    local parent = controller:EnsureFrame()
    if not parent then return nil end

    -- Main overlay frame (child of the controller's managed frame)
    local ov = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ov:SetAllPoints(parent)
    ov:Hide()
    ov:SetFrameStrata("FULLSCREEN_DIALOG")
    ov:SetFrameLevel(parent:GetFrameLevel() + 50)

    -- Backdrop border (12px edge)
    ov:SetBackdrop({
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })

    -- Background fill texture
    local bgFill = ov:CreateTexture(nil, "BACKGROUND")
    bgFill:SetAllPoints()
    bgFill:SetColorTexture(0.30, 0.30, 0.30, 0.05)
    ov._bgFill = bgFill

    -- Text holder frame (higher level for font strings above background)
    local textHolder = CreateFrame("Frame", nil, ov)
    textHolder:SetAllPoints(ov)
    textHolder:SetFrameLevel(ov:GetFrameLevel() + 20)
    ov._textHolder = textHolder

    -- Center label (shows controller name or size during resize)
    local centerLabel = textHolder:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    centerLabel:SetPoint("CENTER")
    centerLabel:SetTextColor(1.0, 0.82, 0.0, 0.90)
    centerLabel:Hide()
    ov._centerLabel = centerLabel

    -- Hint text (shows contextual hints below center)
    local hintText = textHolder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hintText:SetPoint("CENTER")
    hintText:SetTextColor(1, 1, 1, 0.70)
    hintText:Hide()
    ov._hintText = hintText

    -- Track current visual state name
    ov._state = "default"

    -- Create sub-elements
    createLayoutBadge(ov)

    if controller.CanResize and controller:CanResize() then
        createResizeGrip(ov, controller)
    end

    -- Wire interaction scripts
    wireInteraction(ov, controller)

    return ov
end

-- ============================================================================
-- Public API
-- ============================================================================

--- Create overlay if needed, return it.
---@param controller table CLNWindowController
---@return Frame|nil overlay
function OverlayFactory:EnsureOverlay(controller)
    if not controller then return nil end
    local id = controller.id
    if not id then return nil end

    if overlays[id] then return overlays[id] end

    local ov = createOverlay(controller)
    if ov then
        overlays[id] = ov
        controller.overlay = ov
        logDebug("Created overlay for " .. id)
    end

    return ov
end

--- Make overlay visible and set initial state.
---@param controller table CLNWindowController
function OverlayFactory:Show(controller)
    if not controller then return end
    local ov = self:EnsureOverlay(controller)
    if not ov then return end

    -- Prepare parent frame for interaction
    local parent = controller.frame
    if parent then
        parent:SetMovable(true)
        if parent.SetResizable then parent:SetResizable(true) end

        if controller.CanResize and controller:CanResize() then
            local bounds = controller:GetResizeBounds()
            if bounds and parent.SetResizeBounds then
                parent:SetResizeBounds(
                    bounds.minW, bounds.minH,
                    bounds.maxW, bounds.maxH
                )
            end
        end
    end

    -- Refresh badge with current layout name
    refreshLayoutBadge(ov)

    -- Determine lock state and set initial visuals
    local locked = ReplayFrame.IsFrameLocked and ReplayFrame:IsFrameLocked()
    controller.locked = locked and true or false

    if controller.locked then
        self:SetState(controller, "locked")
    else
        self:SetState(controller, "default")
    end

    ov:Show()
end

--- Hide overlay and disable interaction properties.
---@param controller table CLNWindowController
function OverlayFactory:Hide(controller)
    if not controller then return end
    local ov = overlays[controller.id]
    if not ov then return end

    ov:Hide()
    -- Clear any active OnUpdate (from resizing)
    ov:SetScript("OnUpdate", nil)

    local parent = controller.frame
    if parent then
        if parent.SetResizable then parent:SetResizable(false) end
    end
end

--- Set visual state for a controller's overlay.
---@param controller table CLNWindowController
---@param stateName string "default"|"hovered"|"selected"|"dragging"|"resizing"|"locked"
function OverlayFactory:SetState(controller, stateName)
    if not controller then return end
    local ov = overlays[controller.id]
    if not ov then return end

    local state = STATES[stateName]
    if not state then return end

    ov._state = stateName

    -- Apply fill color
    if ov._bgFill then
        local f = state.fill
        ov._bgFill:SetColorTexture(f[1], f[2], f[3], f[4])
    end

    -- Apply border color
    local b = state.border
    ov:SetBackdropBorderColor(b[1], b[2], b[3], b[4])

    -- Determine what to show
    local hasLabel = state.showLabel
    local hasHint = state.showHint

    -- Center label
    if hasLabel and ov._centerLabel then
        ov._centerLabel:SetText(getLabelText(controller, stateName))
        -- Use muted color for locked, gold for active states
        if stateName == "locked" then
            ov._centerLabel:SetTextColor(0.70, 0.70, 0.70, 0.70)
        else
            ov._centerLabel:SetTextColor(1.0, 0.82, 0.0, 0.90)
        end
        ov._centerLabel:ClearAllPoints()
        if hasHint then
            ov._centerLabel:SetPoint("CENTER", 0, 8)
        else
            ov._centerLabel:SetPoint("CENTER")
        end
        ov._centerLabel:Show()
    elseif ov._centerLabel then
        ov._centerLabel:Hide()
    end

    -- Hint text
    if hasHint and ov._hintText then
        ov._hintText:SetText(state.showHint)
        ov._hintText:ClearAllPoints()
        if hasLabel then
            ov._hintText:SetPoint("CENTER", 0, -10)
        else
            ov._hintText:SetPoint("CENTER")
        end
        ov._hintText:Show()
    elseif ov._hintText then
        ov._hintText:Hide()
    end

    -- Live size ticker during resize
    if stateName == "resizing" then
        ov:SetScript("OnUpdate", function(self)
            local f = controller.frame
            if f and f.GetSize and self._centerLabel then
                local w, h = f:GetSize()
                if w and h then
                    self._centerLabel:SetText(
                        string.format("%d \195\151 %d", math.floor(w + 0.5), math.floor(h + 0.5))
                    )
                end
            end
        end)
    else
        ov:SetScript("OnUpdate", nil)
    end

    -- Resize grip visibility (hide when locked)
    if ov._resizeGrip then
        if stateName == "locked" then
            ov._resizeGrip:Hide()
        else
            ov._resizeGrip:Show()
        end
    end
end

--- Reapply colors and layout for the current state.
---@param controller table CLNWindowController
function OverlayFactory:RefreshVisuals(controller)
    if not controller then return end
    local ov = overlays[controller.id]
    if not ov then return end

    self:SetState(controller, ov._state or "default")

    -- Also refresh the layout badge
    refreshLayoutBadge(ov)
end

return OverlayFactory
