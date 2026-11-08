-- ModelSceneHost/ModelLoading.lua - Loading models into the ModelScene host.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local M = ReplayFrame.ModelSceneHost
local now = M._helpers.now

function M.AttachModelLoading(host, backend, MS)
    -- Basic model operations
    ---Clear current model from the actor
    function host:ClearModel()
        self:_HideFrameDiagOverlay()
        -- Clear positioning/camera state so stale values don't block future auto-framing
        self._positioning = nil
        self._userControlledCamera = false
        if backend.actor and backend.actor.ClearModel then 
            pcall(backend.actor.ClearModel, backend.actor) 
        end
    end
    
    ---Load a model by creature display ID
    ---@param displayID number
    ---@param creatureTypeHint string|nil UnitCreatureType result for morphology
    function host:SetDisplayInfo(displayID, creatureTypeHint)
        if not (backend.actor and backend.actor.SetModelByCreatureDisplayID) then
            CLN.Logger:error("ModelSceneHost: actor lacks SetModelByCreatureDisplayID", false, CLN.Utils.LogCategories.host)
            return
        end
        
    self:_DebugLog("host", "SetDisplayInfo called with displayID=%s", tostring(displayID))
        local hasTicker = (C_Timer and C_Timer.NewTicker) and true or false
        local hasAfter = (C_Timer and C_Timer.After) and true or false
        local hasIsLoaded = backend.actor and backend.actor.IsLoaded and true or false
    self:_DebugLog("host", "SetDisplayInfo env ticker=%s after=%s isLoadedFn=%s", tostring(hasTicker), tostring(hasAfter), tostring(hasIsLoaded))
        -- Duplicate-call detection (log-only)
        if self._lastRequestKind == "displayID" and self._lastRequestArg == displayID then
            local dt = now() - (self._lastRequestAt or 0)
            if dt < 1.0 then
                self:_DebugLog("host", "SetDisplayInfo duplicate within %.2fs for id=%s", dt, tostring(displayID))
            end
        end
        self._lastRequestKind, self._lastRequestArg, self._lastRequestAt = "displayID", displayID, now()
        
    -- Cancel previous load session
        if self._lastLoadSession and self._lastLoadSession.cancel then 
            self:_DebugLog("host", "Cancel previous session kind=%s arg=%s", tostring(self._lastLoadSession.kind), tostring(self._lastLoadSession.arg))
            if self._lastLoadSession.cancel.Cancel then
                pcall(self._lastLoadSession.cancel.Cancel, self._lastLoadSession.cancel)
            end
        end
    -- Reset camera state for fresh model
    self._lastCamSnapshot = nil
    self._userControlledCamera = false
        self:_HideFrameDiagOverlay()
        self._sessionId = string.format("displayID:%s@%.3f", tostring(displayID), now())
        self:_BumpModelVersion()
        -- Invalidate canonical bbox cache when displayID changes
        if MS and MS.CanonicalBbox and MS.CanonicalBbox.Invalidate then
            local prevID = self._currentDisplayID
            -- The cache is shared by display ID; a preview host (Portrait Tuner)
            -- must not drop the live portrait's entry
            if prevID and prevID ~= displayID and not self._isPreview then
                MS.CanonicalBbox.Invalidate(prevID)
            end
        end
        self._currentDisplayID = displayID
        self._creatureTypeHint = creatureTypeHint
        
        -- Delegate to Loader module
        if MS and MS.Loader and MS.Loader.loadByDisplayID then
            self:_DebugLog("loader", "Using Loader.loadByDisplayID for id=%s", tostring(displayID))
            local session = MS.Loader.loadByDisplayID(backend.actor, displayID, {
                intervalMs = 50, 
                timeoutMs = 3000, 
                maxAttempts = 2, 
                respectAnimationIntent = true 
            })
            self._lastLoadSession = session
            if session then
                session.kind = "displayID"
                session.arg = displayID
                self:_DebugLog("loader", "Loader session created; has cancel=%s", tostring(session.cancel ~= nil))
            else
                self:_DebugLog("loader", "Failed to create loader session")
            end
        elseif MS and type(MS.loadByDisplayID) == "function" then
            self:_DebugLog("loader", "Using ModelScene.loadByDisplayID for id=%s", tostring(displayID))
            local session = MS.loadByDisplayID(backend.actor, displayID, {
                intervalMs = 50,
                timeoutMs = 3000,
                maxAttempts = 2,
                respectAnimationIntent = true,
            })
            self._lastLoadSession = session
            if session then
                session.kind = "displayID"
                session.arg = displayID
                self:_DebugLog("loader", "Loader session created (direct fn); has cancel=%s", tostring(session.cancel ~= nil))
            else
                self:_DebugLog("loader", "Failed to create loader session (direct fn)")
            end
        else
            self:_DebugLog("loader", "Loader module not available; using fallback")
            -- Fallback: direct call
            local ok = pcall(backend.actor.SetModelByCreatureDisplayID, backend.actor, displayID, false)
            if not ok then 
                ok = pcall(backend.actor.SetModelByCreatureDisplayID, backend.actor, displayID) 
            end
            self:_DebugLog("loader", "Direct fallback call success=%s", tostring(ok))
            if MS and MS.Stabilizer then
                MS.Stabilizer.stabilize(backend.actor, { respectAnimationIntent = true })
            end
        end
        -- Watchdog: after timeout window, report if still not loaded
        if C_Timer and C_Timer.After then
            local token = {}
            self._loadWatchdogToken = token
            local arg = displayID
            C_Timer.After(3.2, function()
                if self._loadWatchdogToken ~= token then return end
                local loadedFlag = "err"
                if backend.actor and backend.actor.IsLoaded then
                    local okL, v = pcall(backend.actor.IsLoaded, backend.actor)
                    loadedFlag = okL and v or "err"
                end
                local sk = self._lastLoadSession and self._lastLoadSession.kind or "?"
                local sa = self._lastLoadSession and self._lastLoadSession.arg or "?"
                self:_DebugLog("host", "watchdog[displayID] 3.2s loaded=%s session=%s %s", tostring(loadedFlag), tostring(sk), tostring(sa))
                if self._DumpState then self:_DumpState("watchdog/displayID") end
            end)
        end
        
    -- Schedule auto-frame (debounced/stable)
        self:_RequestAutoFrame(0.12, { reason = "setDisplay" })
        
        -- Post-load callback (guarded by model version to ignore stale loads)
        if self.OnModelLoadedOnce then
            local vAtReg = self._modelVersion or 0
            self:OnModelLoadedOnce(function(h)
                if (h._modelVersion or 0) ~= vAtReg then return end
                self:_DebugLog("host", "OnModelLoadedOnce fired (displayID)")
                -- Sample canonical bbox before framing (idle pose, stable AABB)
                if MS and MS.CanonicalBbox and MS.CanonicalBbox.SampleCanonical then
                    local getVer = function() return h._modelVersion or 0 end
                    MS.CanonicalBbox.SampleCanonical(backend.actor, displayID, vAtReg, getVer, h._animCtrl, function(bbox)
                        if (h._modelVersion or 0) ~= vAtReg then return end
                        h:_DebugLog("canonical", "Canonical bbox ready for displayID=%s", tostring(displayID))
                        h:_RequestAutoFrame(0.12, { reason = "canonicalReady" })
                    end, h._creatureTypeHint)
                end
                if h and h._animCtrl and h._animCtrl.apply then
                    h._animCtrl:apply(backend.actor)
                end
                h:_RequestAutoFrame(0.12, { reason = "onLoad" })
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.15, function()
                        if h._DumpState then h:_DumpState("post-load/displayID") end
                    end)
                end
            end)
        end
    end
    
    function host:SetUnit(unit)
        if not (backend.actor and backend.actor.SetModelByUnit) then return end
        
        -- Cancel previous load session
        if self._lastLoadSession and self._lastLoadSession.cancel then 
            self:_DebugLog("host", "Cancel previous session kind=%s arg=%s", tostring(self._lastLoadSession.kind), tostring(self._lastLoadSession.arg))
            if self._lastLoadSession.cancel.Cancel then
                pcall(self._lastLoadSession.cancel.Cancel, self._lastLoadSession.cancel)
            end
        end
    -- Reset camera state for fresh unit
    self._lastCamSnapshot = nil
    self._userControlledCamera = false
    self._creatureTypeHint = nil  -- clear stale hint from prior displayID load
    self._currentDisplayID = nil  -- clear stale displayID; resolved in OnModelLoadedOnce
        self:_HideFrameDiagOverlay()
        self._sessionId = string.format("unit:%s@%.3f", tostring(unit), now())
        self:_BumpModelVersion()
        
        local isPlayer = UnitIsPlayer and UnitIsPlayer(unit) or false
    self:_DebugLog("host", "SetUnit called unit=%s isPlayer=%s", tostring(unit), tostring(isPlayer))
        local hasTicker = (C_Timer and C_Timer.NewTicker) and true or false
        local hasAfter = (C_Timer and C_Timer.After) and true or false
        local hasIsLoaded = backend.actor and backend.actor.IsLoaded and true or false
    self:_DebugLog("host", "SetUnit env ticker=%s after=%s isLoadedFn=%s", tostring(hasTicker), tostring(hasAfter), tostring(hasIsLoaded))
        -- Duplicate-call detection (log-only)
        if self._lastRequestKind == "unit" and self._lastRequestArg == unit then
            local dt = now() - (self._lastRequestAt or 0)
            if dt < 1.0 then
                self:_DebugLog("host", "SetUnit duplicate within %.2fs for unit=%s", dt, tostring(unit))
            end
        end
        self._lastRequestKind, self._lastRequestArg, self._lastRequestAt = "unit", unit, now()
        
        if isPlayer then
            -- Enable transmog for players
            if backend.actor.SetUseTransmogChoices then 
                pcall(backend.actor.SetUseTransmogChoices, backend.actor, true) 
            end
            if backend.actor.SetUseTransmogSkin then 
                pcall(backend.actor.SetUseTransmogSkin, backend.actor, true) 
            end
            if backend.actor.SetAutoDress then 
                pcall(backend.actor.SetAutoDress, backend.actor, true) 
            end
        end
        
        -- Delegate to Loader module
        if MS then
            local session
            if not isPlayer and UnitCreatureDisplayID then
                -- Try displayID path for NPCs
                local ok, displayID = pcall(UnitCreatureDisplayID, unit)
                if ok and type(displayID) == "number" and displayID > 0 then
                    if MS.Loader and MS.Loader.loadByDisplayID then
                        self:_DebugLog("loader", "SetUnit using Loader.loadByDisplayID for NPC unit=%s id=%s", tostring(unit), tostring(displayID))
                        session = MS.Loader.loadByDisplayID(backend.actor, displayID, {
                            intervalMs = 50, timeoutMs = 3000, maxAttempts = 2, respectAnimationIntent = true
                        })
                    elseif type(MS.loadByDisplayID) == "function" then
                        self:_DebugLog("loader", "SetUnit using ModelScene.loadByDisplayID for NPC unit=%s id=%s", tostring(unit), tostring(displayID))
                        session = MS.loadByDisplayID(backend.actor, displayID, {
                            intervalMs = 50, timeoutMs = 3000, maxAttempts = 2, respectAnimationIntent = true
                        })
                    end
                end
            end
            if not session then
                if MS.Loader and MS.Loader.loadByUnit then
                    self:_DebugLog("loader", "SetUnit using Loader.loadByUnit for unit=%s", tostring(unit))
                    session = MS.Loader.loadByUnit(backend.actor, unit, {
                        intervalMs = 50, timeoutMs = 3000, maxAttempts = 2, respectAnimationIntent = true
                    })
                elseif type(MS.loadByUnit) == "function" then
                    self:_DebugLog("loader", "SetUnit using ModelScene.loadByUnit for unit=%s", tostring(unit))
                    session = MS.loadByUnit(backend.actor, unit, {
                        intervalMs = 50, timeoutMs = 3000, maxAttempts = 2, respectAnimationIntent = true
                    })
                end
            end
            self._lastLoadSession = session
            if session then
                session.kind = "unit"
                session.arg = unit
                self:_DebugLog("loader", "Loader session created (unit); has cancel=%s", tostring(session.cancel ~= nil))
            end
        end
        -- Watchdog: after timeout window, report if still not loaded
        if C_Timer and C_Timer.After then
            local token = {}
            self._loadWatchdogToken = token
            local arg = unit
            C_Timer.After(3.2, function()
                if self._loadWatchdogToken ~= token then return end
                local loadedFlag = "err"
                if backend.actor and backend.actor.IsLoaded then
                    local okL, v = pcall(backend.actor.IsLoaded, backend.actor)
                    loadedFlag = okL and v or "err"
                end
                local sk = self._lastLoadSession and self._lastLoadSession.kind or "?"
                local sa = self._lastLoadSession and self._lastLoadSession.arg or "?"
                self:_DebugLog("host", "watchdog[unit] 3.2s loaded=%s session=%s %s", tostring(loadedFlag), tostring(sk), tostring(sa))
                if self._DumpState then self:_DumpState("watchdog/unit") end
            end)
        end
        
    -- Schedule auto-frame; will coalesce with load callback
    self:_RequestAutoFrame(0.12, { reason = "setUnit" })
        
        -- Post-load: ensure animation controller and camera are applied once content is ready
        if self.OnModelLoadedOnce then
            local vAtReg = self._modelVersion or 0
            self:OnModelLoadedOnce(function(h)
                if (h._modelVersion or 0) ~= vAtReg then return end
                self:_DebugLog("host", "OnModelLoadedOnce fired (unit)")
                -- Sample canonical bbox for unit-based loads (use display ID if available)
                local unitDisplayID = h._currentDisplayID
                if not unitDisplayID and UnitCreatureDisplayID then
                    local okD, dID = pcall(UnitCreatureDisplayID, unit)
                    if okD and type(dID) == "number" and dID > 0 then unitDisplayID = dID end
                end
                -- Persist resolved displayID so canonical bbox lookup works
                if unitDisplayID and not h._currentDisplayID then
                    h._currentDisplayID = unitDisplayID
                end
                -- Resolve creature type: prefer stored hint, fall back to live query
                local ctHint = h._creatureTypeHint
                if not ctHint and UnitCreatureType and UnitExists and UnitExists(unit) then
                    -- pcall returns (ok, localized, unlocalizedID)
                    local okCT, locCT, unlocCT = pcall(UnitCreatureType, unit)
                    if okCT then ctHint = unlocCT or locCT end
                end
                if unitDisplayID and MS and MS.CanonicalBbox and MS.CanonicalBbox.SampleCanonical then
                    local getVer = function() return h._modelVersion or 0 end
                    MS.CanonicalBbox.SampleCanonical(backend.actor, unitDisplayID, vAtReg, getVer, h._animCtrl, function(bbox)
                        if (h._modelVersion or 0) ~= vAtReg then return end
                        h:_DebugLog("canonical", "Canonical bbox ready for unit=%s displayID=%s", tostring(unit), tostring(unitDisplayID))
                        h:_RequestAutoFrame(0.12, { reason = "canonicalReady" })
                    end, ctHint)
                end
                if h and h._animCtrl and h._animCtrl.apply then
                    h._animCtrl:apply(backend.actor)
                end
                if h and h.FaceCamera then h:FaceCamera() end
                h:_RequestAutoFrame(0.12, { reason = "onLoad" })
                if C_Timer and C_Timer.After then
                    C_Timer.After(0.15, function()
                        if h._DumpState then h:_DumpState("post-load/unit") end
                    end)
                end
            end)
        end
    end
end
