---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

local M = {}
ReplayFrame.ModelSceneHost = M

-- Small helpers
local function now()
    if type(GetTimePreciseSec) == "function" then return GetTimePreciseSec() end
    if type(GetTime) == "function" then return GetTime() end
    return 0
end

local function _frameName(f)
    if not f then return "<nil>" end
    local n = (f.GetName and f:GetName()) or nil
    return n or tostring(f)
end

-- Access to all ModelScene modules
local function getModules()
    local modules = CLN.ReplayFrame.ModelScene
    if modules then
    -- Diagnostics available; avoid printing to chat
    else
    -- No modules found; avoid chat prints
    end
    return modules
end

local function safeCall(obj, method, ...)
    if not (obj and method and obj[method]) then return nil end
    local ok, res = pcall(obj[method], obj, ...)
    if ok then return res end
    return nil
end

-- Create a ModelScene + Actor backend or return nil on failure
function M.Create(parent)
    local ok, scene = pcall(CreateFrame, "ModelScene", nil, parent, "ModelSceneFrameTemplate")
    if not (ok and scene) then return nil end
    
    -- Basic scene setup
    safeCall(scene, "SetAllPoints", parent)
    if scene.EnableMouse then pcall(scene.EnableMouse, scene, false) end
    if scene.SetFrameStrata then
        local strata = (parent and parent.GetFrameStrata and parent:GetFrameStrata()) or "HIGH"
        pcall(scene.SetFrameStrata, scene, strata)
    end
    if scene.SetFrameLevel and parent and parent.GetFrameLevel then
        pcall(scene.SetFrameLevel, scene, (parent:GetFrameLevel() or 0) + 1)
    end
    -- Log initial layering
    local pstrata = "?"
    local plevel = "?"
    if parent then
        if parent.GetFrameStrata then pstrata = parent:GetFrameStrata() or pstrata end
        if parent.GetFrameLevel then plevel = parent:GetFrameLevel() or plevel end
    end
    local sstrata = (scene.GetFrameStrata and scene:GetFrameStrata()) or "?"
    local slevel = (scene.GetFrameLevel and scene:GetFrameLevel()) or "?"
    
    -- Create actor
    local actor
    if scene.CreateActor then
        local okA, a = pcall(scene.CreateActor, scene, nil, "CLNModelSceneActorTemplate")
        if okA and a then actor = a end
        if not actor then
            local okB, b = pcall(scene.CreateActor, scene)
            if okB and b then actor = b end
        end
    end
    if not actor and scene.GetPlayerActor then
        local okP, a = pcall(scene.GetPlayerActor, scene)
        if okP and a then actor = a end
    end
    if not actor then return nil end
    
    -- Basic actor setup
    if scene.Show then pcall(scene.Show, scene) end
    if scene.SetAlpha then pcall(scene.SetAlpha, scene, 1) end
    if actor.Show then pcall(actor.Show, actor) end
    if actor.SetAlpha then pcall(actor.SetAlpha, actor, 1) end
    if actor.SetPosition then pcall(actor.SetPosition, actor, 0, 0, 0) end
    if actor.SetModelScale then pcall(actor.SetModelScale, actor, 1.0) end
    if actor.SetUseCenterForOrigin then pcall(actor.SetUseCenterForOrigin, actor, true) end
    if actor.SetDesaturated then pcall(actor.SetDesaturated, actor, false) end
    
    -- Wire up OnAnimFinished diagnostic callback (for testing)
    if actor.SetOnAnimFinishedCallback then
        actor:SetOnAnimFinishedCallback(function(a)
            CLN:Print("|cff00ff00[AnimFinished]|r actor animation completed")
        end)
    end
    
    -- Lighting setup
    if scene.SetCameraNearClip then pcall(scene.SetCameraNearClip, scene, 0.1) end
    if scene.SetCameraFarClip then pcall(scene.SetCameraFarClip, scene, 100) end
    if scene.SetCameraFieldOfView then pcall(scene.SetCameraFieldOfView, scene, 0.8) end
    -- No chat logging for camera init
    if scene.SetLightVisible then pcall(scene.SetLightVisible, scene, true) end
    if scene.SetLightDiffuseColor then pcall(scene.SetLightDiffuseColor, scene, 1, 1, 1) end
    if scene.SetLightAmbientColor then pcall(scene.SetLightAmbientColor, scene, 0.6, 0.6, 0.6) end
    if scene.SetLightType and _G.LE_MODEL_LIGHT_TYPE_DIRECTIONAL then
        pcall(scene.SetLightType, scene, _G.LE_MODEL_LIGHT_TYPE_DIRECTIONAL)
    end
    if scene.SetLightDirection then pcall(scene.SetLightDirection, scene, 0, -1, -0.5) end
    
    return { kind = "scene", frame = scene, actor = actor }
end

-- Shared with ModelSceneHost/*.lua, which load right after this file.
M._helpers = { now = now, _frameName = _frameName }

-- Attach a lean API that delegates to modules
function M.Attach(host, backend)
    host._backend = backend
    host._lastAnimId = nil
    host._zoom = host._zoom or 0.65
    host._camBaseZ = host._camBaseZ or 1.0
    host._camDist = host._camDist or 1.5
    host._frontYaw = host._frontYaw or math.pi
    host._autoFaceCamera = host._autoFaceCamera ~= false
    host._lastCamSnapshot = nil
    host._userControlledCamera = false
    host._sessionId = string.format("init@%.3f", now())
    
    local MS = getModules()
    
    -- Initialize animation controller
    if MS and MS.AnimationController and not host._animCtrl then
        host._animCtrl = MS.AnimationController.new()
    end
    
    -- Host logger using Diagnostics
    function host:_DebugLog(category, fmt, ...)
        if MS and MS.Diagnostics and MS.Diagnostics.log then
            MS.Diagnostics.log(category, fmt, ...)
        end
    end

    -- Centralized snapshot update to keep camera state coherent
    function host:_UpdateSnapshot(fields)
        local s = self._lastCamSnapshot or {}
        if type(fields) == "table" then
            for k, v in pairs(fields) do
                if type(v) == "number" then
                    if v == v and v ~= 1/0 and v ~= -1/0 then s[k] = v end
                else
                    s[k] = v
                end
            end
        end
        if not s.sessionId then s.sessionId = self._sessionId end
        self._lastCamSnapshot = s
    end

    local function shouldCaptureFrameDiagnostics()
        return CLN.db.profile.debugMode
    end

    function host:_EnsureFrameDiagOverlay()
        if self._frameDiagOverlay or not CreateFrame then return end

        -- Parent to UIParent at TOOLTIP strata so the overlay renders above
        -- the ModelScene 3D viewport (which occludes normal children/siblings
        -- regardless of frame level) and is not clipped by ModelContainer's
        -- SetClipsChildren(true).  Anchored to the host frame for positioning.
        local overlay = CreateFrame("Frame", "CLN_FrameDiagOverlay", UIParent)
        if not overlay then return end

        overlay:SetFrameStrata("TOOLTIP")
        if overlay.EnableMouse then pcall(overlay.EnableMouse, overlay, false) end
        overlay:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 4, 4)
        overlay:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -4, 4)
        overlay:SetHeight(52)

        local bg = overlay:CreateTexture(nil, "BACKGROUND")
        if bg then
            bg:SetAllPoints(overlay)
            if bg.SetColorTexture then
                bg:SetColorTexture(0, 0, 0, 0.6)
            end
        end

        local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if text then
            text:SetPoint("TOPLEFT", overlay, "TOPLEFT", 4, -4)
            text:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -4, -4)
            text:SetJustifyH("LEFT")
            text:SetJustifyV("TOP")
            if text.SetTextColor then
                text:SetTextColor(1.0, 0.95, 0.8, 1.0)
            end
        end

        overlay:Hide()
        self._frameDiagOverlay = overlay
        self._frameDiagText = text
    end

    function host:_HideFrameDiagOverlay()
        if self._frameDiagText and self._frameDiagText.SetText then
            self._frameDiagText:SetText("")
        end
        if self._frameDiagOverlay and self._frameDiagOverlay.Hide then
            self._frameDiagOverlay:Hide()
        end
    end

    function host:_SetFrameDiagOverlayText(text)
        if not shouldCaptureFrameDiagnostics() or type(text) ~= "string" or text == "" then
            self:_HideFrameDiagOverlay()
            return
        end

        self:_EnsureFrameDiagOverlay()
        if not (self._frameDiagOverlay and self._frameDiagText and self._frameDiagText.SetText) then return end

        self._frameDiagText:SetText(text)
        if self._frameDiagOverlay.Show then
            self._frameDiagOverlay:Show()
        end
        self:_DebugLog("diag", "DiagOverlay shown, strata=TOOLTIP, lines=%d", (select(2, text:gsub("\n","")) + 1))
    end

    function host:_RefreshFrameDiagnostics(regionName, source, distance, tx, ty, tz)
        if not shouldCaptureFrameDiagnostics() then
            self:_HideFrameDiagOverlay()
            return
        end

        local bbox = self:GetBounds()
        if not bbox then
            self:_HideFrameDiagOverlay()
            return
        end

        regionName = regionName or (self._lastRegionName or "bust")

        local world, class
        if MS and MS.BodyRegions and MS.BodyRegions.SolveWorldRegion then
            world, class = MS.BodyRegions.SolveWorldRegion(bbox, regionName)
        end

        world = world or {
            targetX = (bbox.center and bbox.center.x) or 0,
            targetY = (bbox.center and bbox.center.y) or 0,
            targetZ = (bbox.center and bbox.center.z) or 0,
            visibleH = (bbox.size and bbox.size.z) or 1,
            fitWidth = (bbox.size and bbox.size.x) or 1,
            visibleLo = (bbox.min and bbox.min.z) or 0,
            visibleHi = (bbox.max and bbox.max.z) or 1,
        }
        class = class or "live"

        world.boundsCenterX = world.boundsCenterX or (bbox.center and bbox.center.x) or world.targetX or 0
        world.targetX = tx or world.targetX or world.boundsCenterX
        world.cameraTargetX = tx or world.cameraTargetX or world.targetX or world.boundsCenterX
        world.targetY = ty or world.targetY or (bbox.center and bbox.center.y) or 0
        world.targetZ = tz or world.targetZ or world.focusZ or (bbox.center and bbox.center.z) or 0
        world.focusZ = world.focusZ or world.targetZ

        local fw, fh = 0, 0
        if self.GetSize then fw, fh = self:GetSize() end
        self:_LogFrameDiagnostics(regionName, source or "live", class, bbox, world, distance or self._camDist or 0, fw, fh)
    end

    function host:_LogFrameDiagnostics(regionName, source, class, bbox, worldRegion, distance, frameW, frameH)
        if not shouldCaptureFrameDiagnostics() then
            self:_HideFrameDiagOverlay()
            return
        end
        if not (worldRegion and MS and MS.ProjectionVerifier and MS.ProjectionVerifier.Measure and backend.frame) then
            self:_HideFrameDiagOverlay()
            return
        end

        local fw = tonumber(frameW) or -1
        local fh = tonumber(frameH) or -1
        local bboxCenter = (bbox and bbox.center) or {}
        local bboxSize = (bbox and bbox.size) or {}
        local targetZ = worldRegion.targetZ or worldRegion.focusZ or 0
        local focusZ = worldRegion.focusZ or targetZ
        local boundsCenterX = worldRegion.boundsCenterX or worldRegion.targetX or worldRegion.cameraTargetX or 0
        local cameraTargetX = worldRegion.cameraTargetX or worldRegion.targetX or boundsCenterX
        local shiftX = cameraTargetX - boundsCenterX
        local sourceLabel = tostring(source or "?")
        if sourceLabel == "canonical" then sourceLabel = "canon" end
        local headerLine = string.format(
            "did=%s %s %s %s",
            tostring(self._currentDisplayID or "?"),
            tostring(regionName or "?"),
            sourceLabel,
            tostring(class or "?")
        )
        local bboxLine = string.format(
            "bbox=%.2f/%.2f/%.2f frame=%.0fx%.0f",
            tonumber(bboxSize.x) or 0,
            tonumber(bboxSize.y) or 0,
            tonumber(bboxSize.z) or 0,
            fw,
            fh
        )
        local solveLine = string.format(
            "d=%.2f z=%.2f/%.2f x=%.2f->%.2f",
            tonumber(distance) or -1,
            tonumber(targetZ) or 0,
            tonumber(focusZ) or 0,
            tonumber(boundsCenterX) or 0,
            tonumber(cameraTargetX) or 0
        )

        self:_DebugLog(
            "framing",
            "FrameDiag[%s] session=%s did=%s source=%s class=%s frame=%.0fx%.0f bboxC=(%.2f,%.2f,%.2f) bboxS=(%.2f,%.2f,%.2f) dist=%.3f targetZ=%.3f focusZ=%.3f boundsCX=%.3f camTX=%.3f shiftX=%.3f visH=%.3f fitW=%.3f",
            tostring(regionName or "?"),
            tostring(self._sessionId or "?"),
            tostring(self._currentDisplayID or "?"),
            tostring(source or "?"),
            tostring(class or "?"),
            fw,
            fh,
            tonumber(bboxCenter.x) or 0,
            tonumber(bboxCenter.y) or 0,
            tonumber(bboxCenter.z) or 0,
            tonumber(bboxSize.x) or 0,
            tonumber(bboxSize.y) or 0,
            tonumber(bboxSize.z) or 0,
            tonumber(distance) or -1,
            tonumber(targetZ) or 0,
            tonumber(focusZ) or 0,
            tonumber(boundsCenterX) or 0,
            tonumber(cameraTargetX) or 0,
            tonumber(shiftX) or 0,
            tonumber(worldRegion.visibleH) or -1,
            tonumber(worldRegion.fitWidth) or -1
        )

        local ok, metrics = MS.ProjectionVerifier.Measure(backend.frame, worldRegion, fw, fh)
        if not ok then
            self:_DebugLog("framing", "FrameDiag[%s] proj=unavailable", tostring(regionName or "?"))
            self:_SetFrameDiagOverlayText(string.format("%s\n%s\n%s\nproj=unavailable", headerLine, bboxLine, solveLine))
            return
        end

        local focusErrorLabel = "na"
        local focusError = tonumber(metrics.focusErrorPY)
        if focusError then
            focusErrorLabel = string.format("%.0f", focusError)
        end
        local projLine = string.format(
            "box=%.0f,%.0f-%.0f,%.0f cov=%.2f/%.2f fe=%s",
            tonumber(metrics.minPX) or -1,
            tonumber(metrics.minPY) or -1,
            tonumber(metrics.maxPX) or -1,
            tonumber(metrics.maxPY) or -1,
            tonumber(metrics.coverageH) or -1,
            tonumber(metrics.coverageW) or -1,
            focusErrorLabel
        )

        self:_DebugLog(
            "framing",
            "FrameDiag[%s] proj box=(%.1f,%.1f)-(%.1f,%.1f) covH=%.3f covW=%.3f target=(%.1f,%.1f) top=%.1f bottom=%.1f focus=%.1f desired=%.1f err=%.1f",
            tostring(regionName or "?"),
            tonumber(metrics.minPX) or -1,
            tonumber(metrics.minPY) or -1,
            tonumber(metrics.maxPX) or -1,
            tonumber(metrics.maxPY) or -1,
            tonumber(metrics.coverageH) or -1,
            tonumber(metrics.coverageW) or -1,
            tonumber(metrics.targetPX) or -1,
            tonumber(metrics.targetPY) or -1,
            tonumber(metrics.topPY) or -1,
            tonumber(metrics.bottomPY) or -1,
            tonumber(metrics.focusPY) or -1,
            tonumber(metrics.desiredFocusPY) or -1,
            tonumber(metrics.focusErrorPY) or -1
        )
        self:_SetFrameDiagOverlayText(string.format("%s\n%s\n%s\n%s", headerLine, bboxLine, solveLine, projLine))
    end

    -- Model versioning to cancel stale pending frames/callbacks
    function host:_BumpModelVersion()
        self._modelVersion = (self._modelVersion or 0) + 1
        self:_DebugLog("framing", "model version -> %d (session=%s)", self._modelVersion, tostring(self._sessionId))
        if self._frameTimer and self._frameTimer.Cancel then pcall(self._frameTimer.Cancel, self._frameTimer) end
        self._frameTimer = nil
        self._framePendingPad = nil
        self._framePendingReason = nil
        -- Clear stale anchor/camera state from previous model
        self._anchorTop = nil
        self._anchorFactor = nil
        self._lastBounds = nil
        -- Clear stale positioning — old anchor percentages are invalid for new bbox
        self._positioning = nil
        self._userControlledCamera = false
    end

    -- Debounced/coalesced auto-framing coordinator
    function host:_RequestAutoFrame(paddingFrac, opts)
        opts = opts or {}
        local force = opts.force and true or false
        local reason = tostring(opts.reason or "auto")
        if (not force) and self._userControlledCamera then
            self:_DebugLog("framing", "skip auto-frame (user-controlled) reason=%s", reason)
            return
        end
        self._framePendingPad = tonumber(paddingFrac) or self._framePendingPad or 0.12
        self._framePendingReason = reason
        local versionAtRequest = self._modelVersion or 0
        if self._frameTimer then return end
        local tries, stable, lastSig = 0, 0, nil
        local step
        local function scheduleNext(delay)
            if not (C_Timer and (C_Timer.After or C_Timer.NewTimer)) then return false end
            if C_Timer.NewTimer then
                local t = C_Timer.NewTimer(delay, function() self._frameTimer = nil; step() end)
                self._frameTimer = t
                return true
            else
                -- C_Timer.After is not cancellable; version check in step() guards against stale callbacks
                self._frameTimer = true
                C_Timer.After(delay, function()
                    self._frameTimer = nil
                    step()
                end)
                return true
            end
        end
        step = function()
            if (self._modelVersion or 0) ~= versionAtRequest then
                self:_DebugLog("framing", "abort pending frame (version changed) reason=%s", reason)
                return
            end
            -- Re-check at fire time: if user took manual control (SetModelPosition,
            -- pan, etc.) between scheduling and firing, respect that and bail out.
            if (not force) and self._userControlledCamera then
                self:_DebugLog("framing", "abort pending frame (user took control) reason=%s", reason)
                return
            end
            local a = backend and backend.actor
            if not a then return end
            local isLoaded = true
            if a.IsLoaded then
                local okL, l = pcall(a.IsLoaded, a)
                isLoaded = okL and l or false
            end
            local b = self:GetBounds()
            local sig = b and string.format("%.3f|%.3f|%.3f|%.3f|%.3f|%.3f", b.center.x or 0, b.center.y or 0, b.center.z or 0, b.size.x or 0, b.size.y or 0, b.size.z or 0) or "nil"
            if not isLoaded or not b then
                tries = tries + 1
                if tries >= 20 and b then
                    self:_DebugLog("framing", "proceed without full stability (tries=%d) reason=%s", tries, reason)
                    self:FrameFullBodyFront_Immediate(self._framePendingPad)
                    return
                end
                if scheduleNext(0.05) then return end
                self:FrameFullBodyFront_Immediate(self._framePendingPad)
                return
            end
            if lastSig == sig then stable = stable + 1 else stable = 0; lastSig = sig end
            if stable >= 1 or tries >= 10 then
                self:_DebugLog("framing", "perform frame (stable=%d tries=%d) reason=%s", stable, tries, reason)
                self:FrameFullBodyFront_Immediate(self._framePendingPad)
                return
            end
            tries = tries + 1
            if scheduleNext(0.05) then return end
            self:FrameFullBodyFront_Immediate(self._framePendingPad)
        end
        if not scheduleNext(0) then step() end
    end
    
    -- The rest of the host API lives in ModelSceneHost/*.lua, attached in this order.
    M.AttachModelLoading(host, backend, MS)
    M.AttachCamera(host, backend, MS)
    M.AttachFraming(host, backend, MS)
    M.AttachUtility(host, backend, MS)
end

return M
