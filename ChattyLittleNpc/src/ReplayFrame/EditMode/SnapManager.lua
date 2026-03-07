---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame
local EditMode = ReplayFrame.EditMode
local Window = EditMode.Window

local floor = math.floor
local abs = math.abs
local min = math.min
local max = math.max

local SNAP_COLOR = { 0.3, 0.7, 1.0, 0.6 }
local SCREEN_CENTER_COLOR = { 0.5, 0.5, 0.5, 0.4 }
local DOCK_COLOR = { 0.82, 0.69, 0.35, 0.7 }

local SnapManager = {
    EDGE_THRESHOLD = 10,
    CENTER_THRESHOLD = 14,
    DOCK_THRESHOLD = 12,
    HYSTERESIS = 3,
    _gridSettings = nil,
    _currentSnap = {
        h = nil,
        v = nil,
    },
}

EditMode.SnapManager = SnapManager

local function SelectBetterSnap(current, candidate)
    if not candidate then
        return current
    end

    if not current or candidate.dist < current.dist then
        return candidate
    end

    return current
end

local function CloneColor(color)
    return { color[1], color[2], color[3], color[4] }
end

local function AddGuide(guides, snap)
    if not (guides and snap and snap.guideType and snap.guidePos) then
        return
    end

    guides[#guides + 1] = {
        type = snap.guideType,
        pos = snap.guidePos,
        color = CloneColor(snap.color or SNAP_COLOR),
    }
end

local function OffsetRect(rect, dx, dy)
    if not rect then
        return nil
    end

    return {
        left = rect.left + dx,
        right = rect.right + dx,
        top = rect.top + dy,
        bottom = rect.bottom + dy,
    }
end

local function MakeAxisSnap(axis, key, delta, threshold, guidePos, color)
    return {
        axis = axis,
        key = key,
        delta = delta,
        dist = abs(delta),
        threshold = threshold,
        guideType = (axis == "h") and "v" or "h",
        guidePos = guidePos,
        color = color or SNAP_COLOR,
    }
end

local function NormalizeSettingValue(value)
    if type(value) == "boolean" then
        return value and 1 or 0
    end

    if type(value) == "number" then
        return value
    end

    if type(value) == "string" then
        local numberValue = tonumber(value)
        if numberValue ~= nil then
            return numberValue
        end

        local lowered = value:lower()
        if lowered == "true" or lowered == "on" or lowered == "enabled" then
            return 1
        end
    end

    return nil
end

function SnapManager:ReadGridSettings()
    local settings = {
        gridEnabled = false,
        gridSpacing = 0,
    }

    if not (C_EditMode and C_EditMode.GetAccountSettings) then
        self._gridSettings = settings
        return settings
    end

    local ok, accountSettings = pcall(C_EditMode.GetAccountSettings)
    if not ok or type(accountSettings) ~= "table" then
        self._gridSettings = settings
        return settings
    end

    local enumSettings = Enum and Enum.EditModeAccountSetting
    local enableSnapId = enumSettings and enumSettings.EnableSnap or 2
    local gridSpacingId = enumSettings and enumSettings.GridSpacing or 1

    for _, info in ipairs(accountSettings) do
        if type(info) == "table" then
            local settingId = info.setting or info.id
            local value = NormalizeSettingValue(info.value)

            if settingId == enableSnapId and value ~= nil then
                settings.gridEnabled = value > 0
            elseif settingId == gridSpacingId and value ~= nil then
                settings.gridSpacing = value
            end
        end
    end

    if settings.gridSpacing < 0 then
        settings.gridSpacing = 0
    end

    self._gridSettings = settings
    return settings
end

function SnapManager:GetGridThreshold()
    local settings = self._gridSettings or self:ReadGridSettings()
    local spacing = settings and settings.gridSpacing or 0
    if spacing <= 0 then
        return self.EDGE_THRESHOLD
    end

    return min(12, max(6, floor(spacing * 0.35)))
end

function SnapManager:FindGridSnap(rect)
    local settings = self._gridSettings or self:ReadGridSettings()
    if not rect or not settings or not settings.gridEnabled then
        return nil, nil
    end

    local spacing = settings.gridSpacing or 0
    if spacing <= 0 then
        return nil, nil
    end

    local threshold = self:GetGridThreshold()
    local bestH, bestV

    local function CheckGridPoint(axis, key, pos)
        local line = floor((pos / spacing) + 0.5) * spacing
        local candidate = MakeAxisSnap(axis, key, line - pos, threshold, line, SNAP_COLOR)
        if candidate.dist <= threshold then
            if axis == "h" then
                bestH = SelectBetterSnap(bestH, candidate)
            else
                bestV = SelectBetterSnap(bestV, candidate)
            end
        end
    end

    CheckGridPoint("h", "grid:left", rect.left)
    CheckGridPoint("h", "grid:right", rect.right)
    CheckGridPoint("v", "grid:top", rect.top)
    CheckGridPoint("v", "grid:bottom", rect.bottom)

    return bestH, bestV
end

function SnapManager:FindPairwiseSnap(draggedRect, targetRect)
    if not draggedRect or not targetRect then
        return nil, nil
    end

    local draggedCenterX, draggedCenterY = Window.GetCenter(draggedRect)
    local targetCenterX, targetCenterY = Window.GetCenter(targetRect)
    local bestH, bestV

    local horizontalCandidates = {
        MakeAxisSnap("h", "left-left", targetRect.left - draggedRect.left, self.EDGE_THRESHOLD, targetRect.left, SNAP_COLOR),
        MakeAxisSnap("h", "left-right", targetRect.right - draggedRect.left, self.EDGE_THRESHOLD, targetRect.right, SNAP_COLOR),
        MakeAxisSnap("h", "right-left", targetRect.left - draggedRect.right, self.EDGE_THRESHOLD, targetRect.left, SNAP_COLOR),
        MakeAxisSnap("h", "right-right", targetRect.right - draggedRect.right, self.EDGE_THRESHOLD, targetRect.right, SNAP_COLOR),
        MakeAxisSnap("h", "center-center", targetCenterX - draggedCenterX, self.CENTER_THRESHOLD, targetCenterX, SNAP_COLOR),
    }

    local verticalCandidates = {
        MakeAxisSnap("v", "top-top", targetRect.top - draggedRect.top, self.EDGE_THRESHOLD, targetRect.top, SNAP_COLOR),
        MakeAxisSnap("v", "top-bottom", targetRect.bottom - draggedRect.top, self.EDGE_THRESHOLD, targetRect.bottom, SNAP_COLOR),
        MakeAxisSnap("v", "bottom-top", targetRect.top - draggedRect.bottom, self.EDGE_THRESHOLD, targetRect.top, SNAP_COLOR),
        MakeAxisSnap("v", "bottom-bottom", targetRect.bottom - draggedRect.bottom, self.EDGE_THRESHOLD, targetRect.bottom, SNAP_COLOR),
        MakeAxisSnap("v", "center-center", targetCenterY - draggedCenterY, self.CENTER_THRESHOLD, targetCenterY, SNAP_COLOR),
    }

    for _, candidate in ipairs(horizontalCandidates) do
        if candidate.dist <= candidate.threshold then
            bestH = SelectBetterSnap(bestH, candidate)
        end
    end

    for _, candidate in ipairs(verticalCandidates) do
        if candidate.dist <= candidate.threshold then
            bestV = SelectBetterSnap(bestV, candidate)
        end
    end

    return bestH, bestV
end

function SnapManager:ApplyHysteresis(axis, newSnap)
    local current = self._currentSnap[axis]
    if not newSnap then
        self._currentSnap[axis] = nil
        return nil
    end

    if not current then
        self._currentSnap[axis] = newSnap
        return newSnap
    end

    if current.key == newSnap.key then
        self._currentSnap[axis] = newSnap
        return newSnap
    end

    if newSnap.dist <= (current.dist - self.HYSTERESIS) then
        self._currentSnap[axis] = newSnap
        return newSnap
    end

    return current
end

function SnapManager:ClearHysteresis()
    self._currentSnap.h = nil
    self._currentSnap.v = nil
end

function SnapManager:CheckDockEligibility(modelRect, convRect)
    if not modelRect or not convRect then
        return false, "missing-rect"
    end

    local verticalDistance = abs(modelRect.bottom - convRect.top)
    if verticalDistance > self.DOCK_THRESHOLD then
        return false, "vertical-distance"
    end

    local overlapLeft = max(modelRect.left, convRect.left)
    local overlapRight = min(modelRect.right, convRect.right)
    local overlapWidth = max(0, overlapRight - overlapLeft)
    local modelWidth = max(0, modelRect.right - modelRect.left)
    local convWidth = max(0, convRect.right - convRect.left)
    local smallerWidth = min(modelWidth, convWidth)

    if smallerWidth <= 0 or overlapWidth < (smallerWidth * 0.70) then
        return false, "horizontal-overlap"
    end

    if abs(modelWidth - convWidth) > 16 then
        return false, "width-delta"
    end

    return true, "ok"
end

function SnapManager:Evaluate(draggedId)
    local result = {
        dx = nil,
        dy = nil,
        snappedX = false,
        snappedY = false,
        dockEligible = false,
        dockReason = nil,
        guides = {},
    }

    local Registry = EditMode.Registry
    if not (draggedId and Registry and Registry.Get) then
        return result
    end

    local dragged = Registry:Get(draggedId)
    if not (dragged and dragged.EnsureFrame) then
        return result
    end

    local draggedFrame = dragged:EnsureFrame()
    local draggedRect = Window.GetRect(draggedFrame)
    if not draggedRect then
        return result
    end

    self:ReadGridSettings()

    local pairwiseH, pairwiseV
    local others = Registry.GetOthers and Registry:GetOthers(draggedId) or nil
    if others then
        for _, controller in ipairs(others) do
            if controller and controller.EnsureFrame then
                local targetFrame = controller:EnsureFrame()
                local targetRect = Window.GetRect(targetFrame)
                if targetRect then
                    local snapH, snapV = self:FindPairwiseSnap(draggedRect, targetRect)
                    if snapH then
                        snapH.key = (controller.id or "target") .. ":" .. snapH.key
                        pairwiseH = SelectBetterSnap(pairwiseH, snapH)
                    end
                    if snapV then
                        snapV.key = (controller.id or "target") .. ":" .. snapV.key
                        pairwiseV = SelectBetterSnap(pairwiseV, snapV)
                    end
                end
            end
        end
    end

    local screenRect = {
        left = 0,
        right = UIParent:GetWidth() or 0,
        top = UIParent:GetHeight() or 0,
        bottom = 0,
    }
    local screenH, screenV = self:FindPairwiseSnap(draggedRect, screenRect)
    if screenH and screenH.key == "center-center" then
        screenH.key = "screen:center-x"
        screenH.color = SCREEN_CENTER_COLOR
        pairwiseH = SelectBetterSnap(pairwiseH, screenH)
    end
    if screenV and screenV.key == "center-center" then
        screenV.key = "screen:center-y"
        screenV.color = SCREEN_CENTER_COLOR
        pairwiseV = SelectBetterSnap(pairwiseV, screenV)
    end

    local winningH = self:ApplyHysteresis("h", pairwiseH)
    local winningV = self:ApplyHysteresis("v", pairwiseV)
    local gridH, gridV = self:FindGridSnap(draggedRect)

    if not winningH then
        winningH = gridH
    end
    if not winningV then
        winningV = gridV
    end

    if winningH then
        result.dx = winningH.delta
        result.snappedX = true
        AddGuide(result.guides, winningH)
    end
    if winningV then
        result.dy = winningV.delta
        result.snappedY = true
        AddGuide(result.guides, winningV)
    end

    if draggedId == "model" then
        local conv = Registry:Get("conversation")
        local convRect = conv and conv.EnsureFrame and Window.GetRect(conv:EnsureFrame()) or nil
        local previewRect = OffsetRect(draggedRect, result.dx or 0, result.dy or 0)
        local dockEligible, reason = self:CheckDockEligibility(previewRect, convRect)
        result.dockEligible = dockEligible
        result.dockReason = reason

        if dockEligible and convRect then
            result.guides[#result.guides + 1] = {
                type = "dock",
                pos = convRect.top,
                left = convRect.left,
                right = convRect.right,
                color = CloneColor(DOCK_COLOR),
            }
        end
    end

    return result
end

function SnapManager:Commit(draggedId, snapResult)
    if InCombatLockdown and InCombatLockdown() then
        return false
    end

    if not (draggedId and type(snapResult) == "table") then
        return false
    end

    local Registry = EditMode.Registry
    if not (Registry and Registry.Get) then
        return false
    end

    local controller = Registry:Get(draggedId)
    if not (controller and controller.EnsureFrame) then
        return false
    end

    if draggedId == "model" and snapResult.dockEligible then
        local ModelWindow = EditMode.ModelWindow
        if ModelWindow and ModelWindow.Dock then
            ModelWindow:Dock()
            return true
        end
    end

    local frame = controller:EnsureFrame()
    if not frame then
        return false
    end

    local dx = snapResult.dx or 0
    local dy = snapResult.dy or 0
    if dx == 0 and dy == 0 then
        return false
    end

    if draggedId == "model" then
        local ModelWindow = EditMode.ModelWindow
        if ModelWindow and ModelWindow.IsDocked and ModelWindow:IsDocked()
            and ModelWindow.Undock then
            ModelWindow:Undock()
            frame = ModelWindow:EnsureFrame() or frame
        end
    end

    local point, _, relativePoint, xOfs, yOfs = frame:GetPoint(1)
    if not point then
        return false
    end

    local scale = frame:GetEffectiveScale() or 1
    local uiScale = UIParent:GetEffectiveScale() or 1
    local ratio = uiScale / scale

    frame:ClearAllPoints()
    frame:SetPoint(
        point,
        UIParent,
        relativePoint or "BOTTOMLEFT",
        (xOfs or 0) + dx * ratio,
        (yOfs or 0) + dy * ratio
    )

    Window.ClampToScreen(frame)
    return true
end

return SnapManager
