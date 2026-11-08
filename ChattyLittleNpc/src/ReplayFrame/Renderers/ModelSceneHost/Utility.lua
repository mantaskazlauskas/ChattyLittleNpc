-- ModelSceneHost/Utility.lua - Utility, compatibility and diagnostic methods on the ModelScene host.

---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame
local M = ReplayFrame.ModelSceneHost
local _frameName = M._helpers._frameName

function M.AttachUtility(host, backend, MS)
    -- Utility methods
    function host:GetBounds()
    if not backend.actor then return nil end
        local minX, minY, minZ, maxX, maxY, maxZ
        
        if backend.actor.GetActiveBoundingBox then
            local ok, a, b, c, d, e, f = pcall(backend.actor.GetActiveBoundingBox, backend.actor)
            if ok and type(a) == "table" and type(b) == "table" then
                minX, minY, minZ = tonumber(a.x) or 0, tonumber(a.y) or 0, tonumber(a.z) or 0
                maxX, maxY, maxZ = tonumber(b.x) or 0, tonumber(b.y) or 0, tonumber(b.z) or 0
            elseif ok and type(a) == "number" then
                minX, minY, minZ, maxX, maxY, maxZ = tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0, tonumber(d) or 0, tonumber(e) or 0, tonumber(f) or 0
            end
        end

        -- Fallback: GetMaxBoundingBox when active bbox is unavailable
        if not minX and backend.actor.GetMaxBoundingBox then
            local ok, a, b, c, d, e, f = pcall(backend.actor.GetMaxBoundingBox, backend.actor)
            if ok and type(a) == "table" and type(b) == "table" then
                minX, minY, minZ = tonumber(a.x) or 0, tonumber(a.y) or 0, tonumber(a.z) or 0
                maxX, maxY, maxZ = tonumber(b.x) or 0, tonumber(b.y) or 0, tonumber(b.z) or 0
            elseif ok and type(a) == "number" then
                minX, minY, minZ, maxX, maxY, maxZ = tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0, tonumber(d) or 0, tonumber(e) or 0, tonumber(f) or 0
            end
        end
        
    if not minX then return nil end
        -- Validate bounds: reject NaN or infinite values
        local function isFinite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
        if not (isFinite(minX) and isFinite(minY) and isFinite(minZ) and isFinite(maxX) and isFinite(maxY) and isFinite(maxZ)) then return nil end
        if minX > maxX then minX, maxX = maxX, minX end
        if minY > maxY then minY, maxY = maxY, minY end
        if minZ > maxZ then minZ, maxZ = maxZ, minZ end
        local cx, cy, cz = (minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5
        local sx, sy, sz = math.abs(maxX - minX), math.abs(maxY - minY), math.abs(maxZ - minZ)
        local eps = 1e-3
        if sx < eps then sx = eps end
        if sy < eps then sy = eps end
        if sz < eps then sz = eps end
    local out = { 
            center = { x = cx, y = cy, z = cz }, 
            size = { x = sx, y = sy, z = sz },
            min = { x = minX, y = minY, z = minZ },
            max = { x = maxX, y = maxY, z = maxZ }
    }
    self._lastBounds = out
    return out
    end
    
    function host:GetFovV()
        local f
        if backend.frame and backend.frame.GetCameraFieldOfView then
            local ok, v = pcall(backend.frame.GetCameraFieldOfView, backend.frame)
            if ok and type(v) == "number" then f = v end
        end
        if not f or f <= 0 then f = 0.8 end
        -- If value looks like degrees, convert to radians
        if f > 3.5 then f = f * math.pi / 180 end
        -- Clamp to a sane range in radians
        if f < 0.1 then f = 0.1 elseif f > 2.8 then f = 2.8 end
        return f
    end
    
    function host:GetAspect()
        local w, h = self:GetSize()
        if not (w and h) or h == 0 then return 1.0 end
        return w / h
    end
    
    -- Additional compatibility methods
    function host:SetSheathed(b) end -- Not supported on ModelScene
    function host:SetPaused(b)
        if backend.actor and backend.actor.SetPaused then 
            pcall(backend.actor.SetPaused, backend.actor, b and true or false) 
        end
    end
    
    function host:SetActorYaw(yaw)
        self._frontYaw = tonumber(yaw) or 0
        if backend.actor and backend.actor.SetYaw then
            pcall(backend.actor.SetYaw, backend.actor, self._frontYaw)
        end
    end
    
    function host:GetActorYaw()
        if backend.actor and backend.actor.GetYaw then
            local ok, yaw = pcall(backend.actor.GetYaw, backend.actor)
            if ok and type(yaw) == "number" then return yaw end
        end
        return self._frontYaw or math.pi
    end

    --- Position the model so that the named anchor point appears at viewport
    --- coordinates (xPct, yPct).  Delegates to the Positioning module.
    --- @param anchor string one of "BOTTOM","CENTER","TOP", etc. (9 standard)
    --- @param xPct number 0.0 = left … 0.5 = center … 1.0 = right
    --- @param yPct number 0.0 = bottom … 0.5 = center … 1.0 = top
    --- @return boolean success
    function host:SetModelPosition(anchor, xPct, yPct)
        if MS and MS.Positioning and MS.Positioning.SetModelPosition then
            return MS.Positioning.SetModelPosition(self, anchor, xPct, yPct)
        end
        return false
    end

    --- Reapply stored positioning after resize / re-frame.
    function host:ReapplyModelPosition()
        if MS and MS.Positioning and MS.Positioning.ReapplyPosition then
            return MS.Positioning.ReapplyPosition(self)
        end
        return false
    end

    --- Clear positioning state, allowing auto-framing to resume.
    function host:ClearModelPosition()
        if MS and MS.Positioning and MS.Positioning.ClearPosition then
            MS.Positioning.ClearPosition(self)
        end
    end

    -- Load monitoring
    function host:OnModelLoadedOnce(cb)
        if type(cb) ~= "function" then return end
        if not (backend.actor and backend.actor.IsLoaded) then return end
        
        local a = backend.actor
        local ok, loaded = pcall(a.IsLoaded, a)
        if ok and loaded then cb(self); return end
        
        local attempts = 0
        local maxAttempts = 60 -- ~3s at 50ms intervals
        local function tryOnce()
            attempts = attempts + 1
            if attempts > maxAttempts then return true end -- give up, stop polling
            local ok2, loaded2 = pcall(a.IsLoaded, a)
            if ok2 and loaded2 then cb(self); return true end
            return false
        end
        
        if C_Timer and C_Timer.NewTicker then
            local ticker
            ticker = C_Timer.NewTicker(0.05, function()
                if tryOnce() and ticker and ticker.Cancel then ticker:Cancel() end
            end)
        elseif C_Timer and C_Timer.After then
            local function loop()
                if not tryOnce() then C_Timer.After(0.05, loop) end
            end
            C_Timer.After(0.05, loop)
        end
    end
    
    -- Keep scene visibility in sync with host
    if host.HookScript then
        host:HookScript("OnShow", function()
            -- Hooks outlive a switch to the PlayerModel backend; don't re-show this scene over it
            if host._backend ~= backend then return end
            local f, a = backend.frame, backend.actor
            host:_DebugLog("host", "OnShow (frame+actor shown)")
            if f and f.Show then pcall(f.Show, f) end
            if a and a.Show then pcall(a.Show, a) end
            if host.GetSize then
                local w, h = host:GetSize(); host:_DebugLog("host", "size on show = %.1fx%.1f", tonumber(w) or -1, tonumber(h) or -1)
                -- [Trigger] and [Size] snapshot at show time
                local sF = host.GetEffectiveScale and host:GetEffectiveScale() or 1
                local sU = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
                local aspect = (h and h > 0) and ((tonumber(w) or 0) / (tonumber(h) or 1)) or 1
                host:_DebugLog("framing", "[Trigger] OnShow (autoFace=%s userControlled=%s)", tostring(host._autoFaceCamera ~= false), tostring(host._userControlledCamera or false))
                host:_DebugLog("framing", string.format("[Size] frame=%.1fx%.1f aspect=%.6f scale(frame)=%.4f scale(UI)=%.4f", tonumber(w) or -1, tonumber(h) or -1, aspect or -1, tonumber(sF) or 1, tonumber(sU) or 1))
            end
            if a and a.IsLoaded then
                local okL, v = pcall(a.IsLoaded, a)
                if okL and v then
                    if host._positioning then
                        host:FitDistanceForCurrentTarget(0.12)
                        host:ReapplyModelPosition()
                    elseif host._userControlledCamera then
                        host:FitDistanceForCurrentTarget(0.12)
                    else
                        host:FrameFullBodyFront(0.12)
                    end
                end
            end
            if host._DumpState then host:_DumpState("OnShow") end
        end)
        host:HookScript("OnHide", function()
            local f, a = backend.frame, backend.actor
            host:_DebugLog("host", "OnHide (frame+actor hidden)")
            host:_HideFrameDiagOverlay()
            if a and a.Hide then pcall(a.Hide, a) end
            if f and f.Hide then pcall(f.Hide, f) end
        end)
        host:HookScript("OnSizeChanged", function(_, w, h)
            if host._backend ~= backend then return end
            host:_DebugLog("host", "OnSizeChanged -> %.1fx%.1f", tonumber(w) or -1, tonumber(h) or -1)
            -- [Trigger] and [Size] details for live viewport & scales
            local sF = host.GetEffectiveScale and host:GetEffectiveScale() or 1
            local sU = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
            local aspect = (h and h > 0) and ((tonumber(w) or 0) / (tonumber(h) or 1)) or 1
            host:_DebugLog("framing", "[Trigger] OnSizeChanged (autoFace=%s userControlled=%s)", tostring(host._autoFaceCamera ~= false), tostring(host._userControlledCamera or false))
            host:_DebugLog("framing", string.format("[Size] frame=%.1fx%.1f aspect=%.6f scale(frame)=%.4f scale(UI)=%.4f", tonumber(w) or -1, tonumber(h) or -1, aspect or -1, tonumber(sF) or 1, tonumber(sU) or 1))
            -- If something is loaded, re-frame to fit
            if backend.actor and backend.actor.IsLoaded then
                local okL, v = pcall(backend.actor.IsLoaded, backend.actor)
                if okL and v then
                    if host._positioning then
                        -- Refit distance first (preserves scale), then reapply position
                        host:FitDistanceForCurrentTarget(0.12)
                        host:ReapplyModelPosition()
                    elseif host._userControlledCamera then
                        host:FitDistanceForCurrentTarget(0.12)
                    else
                        host:FrameFullBodyFront(0.12)
                    end
                end
            end
            if host._DumpState then host:_DumpState("OnSizeChanged") end
        end)
    end

    -- Rich state dump for troubleshooting
    function host:_DumpState(label)
        label = label or "dump"
        local f, a = backend.frame, backend.actor
    local w, h = -1, -1
    if self.GetSize then w, h = self:GetSize() end
        local sStrata = f and f.GetFrameStrata and f:GetFrameStrata() or "?"
        local sLevel = f and f.GetFrameLevel and f:GetFrameLevel() or "?"
        local sShown = f and f.IsShown and f:IsShown() or false
        local sVisible = f and f.IsVisible and f:IsVisible() or false
        local sAlpha = f and f.GetAlpha and f:GetAlpha() or "?"
        local aShown = a and a.IsShown and a:IsShown() or false
        local aAlpha = a and a.GetAlpha and a:GetAlpha() or "?"
        local aLoaded = false; if a and a.IsLoaded then local okL, v = pcall(a.IsLoaded, a); aLoaded = okL and v or false end
        local yaw, pitch, roll = "?", "?", "?"
        if a then
            if a.GetYaw then local ok, v = pcall(a.GetYaw, a); if ok then yaw = v end end
            if a.GetPitch then local ok, v = pcall(a.GetPitch, a); if ok then pitch = v end end
            if a.GetRoll then local ok, v = pcall(a.GetRoll, a); if ok then roll = v end end
        end
        local posX, posY, posZ = "?","?","?"
        if a and a.GetPosition then local okP, x, y, z = pcall(a.GetPosition, a); if okP then posX, posY, posZ = x, y, z end end
        local scale = "?"
        if a and a.GetModelScale then local okS, s = pcall(a.GetModelScale, a); if okS then scale = s end end
        local b = self:GetBounds()
        local cam = self._lastCam or {}
    self:_DebugLog("host", "DUMP[%s] size=%.1fx%.1f scene(shown=%s vis=%s strata=%s lvl=%s alpha=%s) actor(loaded=%s shown=%s alpha=%s pos=(%s,%s,%s) scale=%s yaw=%s pitch=%s roll=%s)", label, tonumber(w) or -1, tonumber(h) or -1, tostring(sShown), tostring(sVisible), tostring(sStrata), tostring(sLevel), tostring(sAlpha), tostring(aLoaded), tostring(aShown), tostring(aAlpha), tostring(posX), tostring(posY), tostring(posZ), tostring(scale), tostring(yaw), tostring(pitch), tostring(roll))
        if b then
            self:_DebugLog("host", "DUMP[%s] bounds c=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f) min=(%.2f,%.2f,%.2f) max=(%.2f,%.2f,%.2f)", label, b.center.x or 0, b.center.y or 0, b.center.z or 0, b.size.x or 0, b.size.y or 0, b.size.z or 0, b.min.x or 0, b.min.y or 0, b.min.z or 0, b.max.x or 0, b.max.y or 0, b.max.z or 0)
        else
            self:_DebugLog("host", "DUMP[%s] bounds=nil", label)
        end
        if next(cam) then
            self:_DebugLog("camera", "DUMP[%s] cam pos=(%.2f,%.2f,%.2f) tgt=(%.2f,%.2f,%.2f) f=(%.2f,%.2f,%.2f) r=(%.2f,%.2f,%.2f) u=(%.2f,%.2f,%.2f)", label, cam.px or 0, cam.py or 0, cam.pz or 0, cam.tx or 0, cam.ty or 0, cam.tz or 0, cam.fx or 0, cam.fy or 0, cam.fz or 0, cam.rx or 0, cam.ry or 0, cam.rz or 0, cam.ux or 0, cam.uy or 0, cam.uz or 0)
        end
        -- Parent info
    local p = nil
    if self.GetParent then p = self:GetParent() end
        if p then
            local pStrata = p.GetFrameStrata and p:GetFrameStrata() or "?"
            local pLevel = p.GetFrameLevel and p:GetFrameLevel() or "?"
            local pShown = p.IsShown and p:IsShown() or false
            local pVisible = p.IsVisible and p:IsVisible() or false
            self:_DebugLog("host", "DUMP[%s] parent=%s strata=%s lvl=%s shown=%s vis=%s", label, _frameName(p), tostring(pStrata), tostring(pLevel), tostring(pShown), tostring(pVisible))
        end
        -- Profile flags of interest
        local adv = CLN.db.profile.advancedCameraFitting
    self:_DebugLog("host", "DUMP[%s] advancedCameraFitting=%s", label, tostring(adv))
    end
end
