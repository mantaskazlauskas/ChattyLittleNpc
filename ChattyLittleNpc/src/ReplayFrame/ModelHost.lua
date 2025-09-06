---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- Refactored ModelHost: delegates renderer-specific logic to Renderers/{ModelSceneHost,PlayerModelRenderer}

-- Public factory: create a host frame inside parent and choose backend
function ReplayFrame:CreateModelHost(parent)
    local host = CreateFrame("Frame", "ChattyLittleNpcModelHost", parent)
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    host:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    host:SetHeight(140)

    local pref = (CLN and CLN.db and CLN.db.profile and CLN.db.profile.renderBackend) or "auto"
    local sceneR = ReplayFrame.ModelSceneHost
    local playerR = ReplayFrame.PlayerModelRenderer

    local backend, attach
    local function tryScene()
        if not sceneR then return nil end
        local b = sceneR.Create(host)
        if b then attach = function() sceneR.Attach(host, b) end end
        return b
    end
    local function tryPlayer()
        local b = playerR and playerR.Create and playerR.Create(host) or nil
        if b then attach = function() playerR.Attach(host, b) end end
        return b
    end

    if pref == "player" then
        backend = tryPlayer()
    elseif pref == "scene" then
        backend = tryScene() or tryPlayer()
    else -- auto
        backend = tryScene() or tryPlayer()
    end

    if not backend then
        -- Extremely defensive: last resort simple PlayerModel
        local pm = CreateFrame("PlayerModel", nil, host)
        pm:SetAllPoints(host)
        backend = { kind = "player", frame = pm }
        -- minimal attach: only expose a few methods
    host.ClearModel = function() pcall(pm.ClearModel, pm) end
        host.SetDisplayInfo = function(_, id) pcall(pm.SetDisplayInfo, pm, id) end
        host.SetPortraitZoom = function(_, v) pcall(pm.SetPortraitZoom, pm, tonumber(v) or 0.65) end
        host.GetPortraitZoom = function() return 0.65 end
        host.SetPosition = function(_, x, y, z) pcall(pm.SetPosition, pm, x, y, z) end
        host.SetRotation = function(_, r) pcall(pm.SetRotation, pm, r) end
        host.SetAnimation = function(_, a) pcall(pm.SetAnimation, pm, a) end
        host.GetAnimation = function() return nil end
        host.SetSheathed = function(_, b) pcall(pm.SetSheathed, pm, b and true or false) end
        host.SetPaused = function(_, b) pcall(pm.SetPaused, pm, b and true or false) end
        host.SetUnit = function(_, unit) pcall(pm.SetUnit, pm, unit) end
        -- Framing API (fallback emulation)
        host.GetBounds = function() return nil end
        host.GetActorScale = function() return 1.0 end
        host.SetActorScale = function(_, s)
            local base = 0.65
            local scale = tonumber(s) or 1.0
            local zoom = math.max(0.0, math.min(1.5, base / math.max(0.1, scale)))
            pcall(pm.SetPortraitZoom, pm, zoom)
        end
        host.GetActorYaw = function() return 0 end
        host.SetActorYaw = function(_, yaw) pcall(pm.SetRotation, pm, tonumber(yaw) or 0) end
        host.SetCamera = function(_, distance, yaw, pitch)
            local d = tonumber(distance) or 2.5
            local zoom = math.max(0.0, math.min(1.5, 3.2 - 0.4 * d))
            pcall(pm.SetPortraitZoom, pm, zoom)
            pcall(pm.SetRotation, pm, tonumber(yaw) or 0)
        end
        host.GetFovV = function() return math.rad(60) end
        host.GetAspect = function(self)
            local w, h = self:GetSize(); if not (w and h) or h == 0 then return 1.0 end; return w / h
        end
        host.SetTarget = function(_, vec3)
            vec3 = vec3 or {}; local z = tonumber(vec3.z) or 0; pcall(pm.SetPosition, pm, 0, 0, z)
        end
        host.ProjectFit = function(self, scale, targetCenter)
            if scale ~= nil then self:SetActorScale(scale) end
            if targetCenter ~= nil then self:SetTarget(targetCenter) end
            self:SetCamera(2.5, 0, 0)
        end
    else
        if attach then attach() end
    end

    -- Normalize camera API across backends
    if ReplayFrame and ReplayFrame.HostCamera and ReplayFrame.HostCamera.Attach then
        ReplayFrame.HostCamera.Attach(host)
    end

    -- Provide a helper for renderer fallback when scene actor can't handle displayIDs
    function host:_SwitchToPlayerBackendAndApplyDisplay(displayID)
        local current = self._backend
        -- Hide current scene to avoid double render
        if current and current.kind == "scene" and current.frame and current.frame.Hide then
            pcall(current.frame.Hide, current.frame)
        end
        local playerR2 = ReplayFrame.PlayerModelRenderer
        if not (playerR2 and playerR2.Create and playerR2.Attach) then return end
        local b = playerR2.Create(self)
        if not b then return end
        playerR2.Attach(self, b)
        self._backend = b
        -- Best-effort: carry over zoom feel
        if self.SetPortraitZoom then self:SetPortraitZoom(self._zoom or 0.65) end
        if self.SetDisplayInfo then self:SetDisplayInfo(displayID) end
        local U = CLN and CLN.Utils
        if U and U.ShouldLogAnimDebug and U:ShouldLogAnimDebug("host") and U.LogAnimDebug then
            U:LogAnimDebug("host", "ModelHost: switched backend to 'player' due to scene missing SetModelByCreatureDisplayID")
        end
    end

    local U = CLN and CLN.Utils
    if U and U.ShouldLogAnimDebug and U:ShouldLogAnimDebug("host") and U.LogAnimDebug then
        U:LogAnimDebug("host", "ModelHost: using backend kind='" .. tostring(backend and backend.kind or "nil") .. "'")
    end
    host:Hide()
    return host
end

function ReplayFrame:IsModelSceneAvailable()
    if self._modelSceneAvail ~= nil then return self._modelSceneAvail end
    local ok, scene = pcall(CreateFrame, "ModelScene", nil, UIParent)
    if ok and scene then
        pcall(scene.Hide, scene)
        self._modelSceneAvail = true
        return true
    end
    self._modelSceneAvail = false
    return false
end
