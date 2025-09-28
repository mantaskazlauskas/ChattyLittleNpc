---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- Refactored ModelHost: delegates renderer-specific logic to Renderers/{ModelSceneHost,PlayerModelRenderer}

-- Public factory: create a host frame inside parent and choose backend
function ReplayFrame:CreateModelHost(parent, opts)
    opts = opts or {}
    local frameName = opts.name -- allow anonymous frame if nil
    local host = CreateFrame("Frame", frameName or "ChattyLittleNpcModelHost", parent)
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

    if backend and attach then
        attach()
    end

    -- Normalize camera API across backends
    if ReplayFrame and ReplayFrame.HostCamera and ReplayFrame.HostCamera.Attach then
        ReplayFrame.HostCamera.Attach(host)
    end

    -- Provide a helper for renderer fallback when scene actor can't handle displayIDs
    function host:FallbackToPlayer(reason, replay)
        if self._backend and self._backend.kind == "player" then return end
        local current = self._backend
        if current and current.kind == "scene" and current.frame and current.frame.Hide then
            pcall(current.frame.Hide, current.frame)
        end
        local playerR2 = ReplayFrame.PlayerModelRenderer
        if not (playerR2 and playerR2.Create and playerR2.Attach) then
            if CLN and CLN.Logger then
                CLN.Logger:error("ModelHost fallback failed: PlayerModelRenderer unavailable", true, CLN.Utils.LogCategories.host)
            end
            return
        end
        local ok, b = pcall(playerR2.Create, self)
        if not (ok and b) then
            if CLN and CLN.Logger then
                CLN.Logger:error("ModelHost fallback creation failed", true, CLN.Utils.LogCategories.host)
            end
            return
        end
        playerR2.Attach(self, b)
        self._backend = b
        if CLN and CLN.Logger then
            CLN.Logger:warn("ModelHost: switched to PlayerModel backend (reason="..tostring(reason)..")", false, CLN.Utils.LogCategories.host)
        end
        -- Persist user preference so future hosts start directly with player backend
        if CLN and CLN.db and CLN.db.profile then
            if CLN.db.profile.renderBackend ~= "player" then
                CLN.db.profile.renderBackend = "player"
                if CLN.Logger then
                    CLN.Logger:info("Render backend preference updated to 'player' due to fallback ("..tostring(reason)..")", true, CLN.Utils.LogCategories.host)
                end
            end
        end
        if replay then
            if replay.displayID and self.SetDisplayInfo then
                self:SetDisplayInfo(replay.displayID)
            elseif replay.unit and self.SetUnit then
                self:SetUnit(replay.unit)
            end
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
