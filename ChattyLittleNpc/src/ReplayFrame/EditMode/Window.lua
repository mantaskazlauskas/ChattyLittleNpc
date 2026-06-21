---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- ============================================================================
-- EditMode Window Utilities
-- ============================================================================
-- Shared utility functions for the two-window Edit Mode system.
-- Used by ConversationWindow.lua and ModelWindow.lua adapters.
-- ============================================================================

local Window = {}
CLN.ReplayFrame = CLN.ReplayFrame or {}
CLN.ReplayFrame.EditMode = CLN.ReplayFrame.EditMode or {}
CLN.ReplayFrame.EditMode.Window = Window

--- Compute frame rect in UIParent-space pixels (scale-normalized).
--- All snap math must use these coordinates — never mix with frame-local coords.
---@param frame Frame
---@return table {left, right, top, bottom}
function Window.GetRect(frame)
    if not frame or not frame.GetLeft then return nil end
    local left = frame:GetLeft()
    local right = frame:GetRight()
    local top = frame:GetTop()
    local bottom = frame:GetBottom()
    if not (left and right and top and bottom) then return nil end

    local scale = frame:GetEffectiveScale() or 1
    local uiScale = UIParent:GetEffectiveScale() or 1
    local ratio = scale / uiScale

    return {
        left   = left * ratio,
        right  = right * ratio,
        top    = top * ratio,
        bottom = bottom * ratio,
    }
end

--- Compute center of a rect table.
---@param rect table {left, right, top, bottom}
---@return number cx, number cy
function Window.GetCenter(rect)
    if not rect then return 0, 0 end
    return (rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2
end

--- Serialize frame position for persistence.
--- Uses GetPoint() to capture the exact anchor WoW stores internally, avoiding
--- the GetCenter()+scale-math rounding loop that caused slow drift on reload.
--- Percentage fallbacks (x_pct/y_pct) are computed from GetLeft/GetBottom in
--- UIParent-space for cross-resolution import support.
---@param frame Frame
---@return table|nil pos {point, relativePoint, x, y, x_pct, y_pct}
function Window.SerializePosition(frame)
    if not frame or not frame.GetPoint then return nil end
    local point, _, relPoint, x, y = frame:GetPoint()
    if not (point and x and y) then return nil end

    -- Percentage fallback: convert left/bottom to UIParent-space for import
    local uiW = UIParent:GetWidth()
    local uiH = UIParent:GetHeight()
    local x_pct, y_pct = 0, 0
    if uiW > 0 and uiH > 0 then
        local scale = frame:GetEffectiveScale() or 1
        local uiScale = UIParent:GetEffectiveScale() or 1
        local ratio = scale / uiScale  -- frame-local → UIParent-space
        local left   = frame:GetLeft()
        local bottom = frame:GetBottom()
        if left and bottom then
            x_pct = (left * ratio) / uiW
            y_pct = (bottom * ratio) / uiH
        end
    end

    return {
        point         = point,
        relativePoint = relPoint,
        x             = x,
        y             = y,
        x_pct         = x_pct,
        y_pct         = y_pct,
    }
end

--- Apply a position descriptor to a frame.
--- If opts.usePercentage is true and x_pct/y_pct exist, recalculates from percentages
--- (used for cross-resolution import).
---@param frame Frame
---@param pos table {point, relativePoint, x, y, x_pct?, y_pct?}
---@param opts? table {usePercentage: boolean}
function Window.ApplyPosition(frame, pos, opts)
    if not frame or not pos then return end
    local x = pos.x or pos.xOfs or 0
    local y = pos.y or pos.yOfs or 0
    if opts and opts.usePercentage and pos.x_pct and pos.y_pct then
        local uiW = UIParent:GetWidth()
        local uiH = UIParent:GetHeight()
        x = pos.x_pct * uiW
        y = pos.y_pct * uiH
    end
    frame:ClearAllPoints()
    frame:SetPoint(
        pos.point or "CENTER",
        UIParent,
        pos.relativePoint or "BOTTOMLEFT",
        x, y
    )
end

--- Clamp frame so it remains fully on-screen.
--- Uses UIParent-space coordinates to handle non-1 frame scale correctly.
---@param frame Frame
function Window.ClampToScreen(frame)
    if not frame then return end
    local rect = Window.GetRect(frame)
    if not rect then return end

    local sw = UIParent:GetWidth()
    local sh = UIParent:GetHeight()
    local dx, dy = 0, 0

    if rect.left < 0 then dx = -rect.left
    elseif rect.right > sw then dx = sw - rect.right end
    if rect.bottom < 0 then dy = -rect.bottom
    elseif rect.top > sh then dy = sh - rect.top end

    if dx ~= 0 or dy ~= 0 then
        local p, _, r, x, y2 = frame:GetPoint(1)
        if p then
            -- Convert UIParent-space correction to frame-space offset
            local scale = frame:GetEffectiveScale() or 1
            local uiScale = UIParent:GetEffectiveScale() or 1
            local ratio = uiScale / scale
            frame:ClearAllPoints()
            frame:SetPoint(p, UIParent, r, (x or 0) + dx * ratio, (y2 or 0) + dy * ratio)
        end
    end
end

--- Serialize frame size.
---@param frame Frame
---@return table|nil {width, height}
function Window.SerializeSize(frame)
    if not frame or not frame.GetSize then return nil end
    local w, h = frame:GetSize()
    if not (w and h) then return nil end
    return { width = math.floor(w + 0.5), height = math.floor(h + 0.5) }
end

return Window
