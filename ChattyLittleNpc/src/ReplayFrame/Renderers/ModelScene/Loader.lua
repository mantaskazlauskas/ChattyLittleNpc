local CLN = _G.ChattyLittleNpc
local ReplayFrame = CLN.ReplayFrame
ReplayFrame.ModelScene = ReplayFrame.ModelScene or {}
local NS = ReplayFrame.ModelScene

local function capabilities(actor)
    return {
        hasUseTransmogChoices = actor and actor.SetUseTransmogChoices ~= nil,
        hasUseTransmogSkin = actor and actor.SetUseTransmogSkin ~= nil,
        hasAutoDress = actor and actor.SetAutoDress ~= nil,
        hasClear = actor and actor.ClearModel ~= nil,
        hasIsLoaded = actor and actor.IsLoaded ~= nil,
    }
end

local function prepare(actor)
    if not actor then return end
    if actor.ClearModel then pcall(actor.ClearModel, actor) end
    if actor.SetUseTransmogChoices then pcall(actor.SetUseTransmogChoices, actor, false) end
    if actor.SetUseTransmogSkin then pcall(actor.SetUseTransmogSkin, actor, false) end
    if actor.SetAutoDress then pcall(actor.SetAutoDress, actor, false) end
    if actor.SetDesaturated then pcall(actor.SetDesaturated, actor, false) end
    if actor.SetAlpha then pcall(actor.SetAlpha, actor, 1.0) end
    if actor.SetAnimation then pcall(actor.SetAnimation, actor, 0) end
end

local function startTicker(interval, onTick)
    if C_Timer and C_Timer.NewTicker then
        local t
        t = C_Timer.NewTicker(interval, function()
            if onTick(t) and t and t.Cancel then t:Cancel() end
        end)
        return t
    end
    if C_Timer and C_Timer.After then
        local alive = true
        local function loop()
            if not alive then return end
            if not onTick(nil) then C_Timer.After(interval, loop) end
        end
        C_Timer.After(interval, loop)
        return { Cancel = function() alive = false end }
    end
    return nil
end

local function loadInternal(actor, callFn, arg, opts)
    opts = opts or {}
    -- Normalize timing: options are in milliseconds; C_Timer expects seconds
    local intervalMs = tonumber(opts.intervalMs) or 50
    if intervalMs < 5 then intervalMs = 5 end -- clamp to avoid 0/too-fast
    local timeoutMs = tonumber(opts.timeoutMs) or 3000
    if timeoutMs < intervalMs then timeoutMs = intervalMs * 2 end
    local intervalSec = intervalMs / 1000.0
    local timeoutTicks = math.max(1, math.floor(timeoutMs / intervalMs))
    local cap = capabilities(actor)
    if NS.Diagnostics and NS.Diagnostics.log then
        NS.Diagnostics.log("load", "loadInternal arg=%s hasIsLoaded=%s", tostring(arg), tostring(cap.hasIsLoaded))
    end
    local session = {
        state = "Preparing",
        attempts = 0,
        loaded = false,
        start = GetTime and GetTime() or 0,
        cap = cap,
        cancel = function() end,
    }

    prepare(actor)
    if NS.Stabilizer then
        NS.Stabilizer.stabilize(actor, { respectAnimationIntent = opts.respectAnimationIntent ~= false })
    end

    local function tryLoad()
        session.attempts = session.attempts + 1
        if NS.Diagnostics and NS.Diagnostics.log then
            NS.Diagnostics.log("load", "tryLoad attempt %d for %s", session.attempts, tostring(arg))
        end
        local ok = pcall(callFn, actor, arg, false)
        if not ok then 
            if NS.Diagnostics and NS.Diagnostics.log then
                NS.Diagnostics.log("load", "first call failed, retry without flag")
            end
            ok = pcall(callFn, actor, arg) 
        end
        if NS.Diagnostics and NS.Diagnostics.log then
            NS.Diagnostics.log("load", "tryLoad final result=%s", tostring(ok))
        end
        if NS.Diagnostics and NS.Diagnostics.log then
            NS.Diagnostics.log("load", "Attempt %d for %s", session.attempts, tostring(arg))
        end
    end

    session.state = "Loading"
    tryLoad()

    local retried = false
    local maxAttempts = (opts.maxAttempts or 2)
    local ticks = 0

    session.cancel = startTicker(intervalSec, function(tk)
        ticks = ticks + 1
        local loaded = false
        if cap.hasIsLoaded then
            local okL, l = pcall(actor.IsLoaded, actor)
            loaded = okL and l or false
        end
        if loaded then
            session.state = "Stabilizing"
            if NS.Stabilizer then
                NS.Stabilizer.stabilize(actor, { respectAnimationIntent = opts.respectAnimationIntent ~= false })
            end
            session.state = "Loaded"
            session.loaded = true
            if NS.Diagnostics and NS.Diagnostics.log then
                NS.Diagnostics.log("load", "Loaded %s in %.0fms (attempts=%d)", tostring(arg), ((GetTime() or 0) - session.start) * 1000, session.attempts)
            end
            return true
        end
        if (ticks >= 20) and (not retried) and (session.attempts < maxAttempts) then
            retried = true
            prepare(actor)
            tryLoad()
        end
        if ticks > timeoutTicks then
            session.state = "Failed"
            if NS.Diagnostics and NS.Diagnostics.log then
                NS.Diagnostics.log("load", "Timeout loading %s after %d attempts", tostring(arg), session.attempts)
            end
            return true
        end
        return false
    end)

    return session
end

function NS.loadByDisplayID(actor, displayID, opts)
    if NS.Diagnostics and NS.Diagnostics.log then
        NS.Diagnostics.log("load", "loadByDisplayID actor=%s displayID=%s", tostring(actor), tostring(displayID))
    end
    return loadInternal(actor, function(a, id, flag)
        return a.SetModelByCreatureDisplayID(a, id, flag)
    end, displayID, opts)
end

function NS.loadByUnit(actor, unit, opts)
    return loadInternal(actor, function(a, u, flag)
        return a.SetModelByUnit(a, u, flag)
    end, unit, opts)
end
