---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- PlayerModel renderer presets. We approximate via zoom/position/rotation APIs.
-- Exposes: ReplayFrame.PlayerPresets with functions(host) -> ()

ReplayFrame = ReplayFrame or {}
ReplayFrame.PlayerPresets = {}
local P = ReplayFrame.PlayerPresets

-- Utility: safe call
local function sc(frame, method, ...)
    if not (frame and method and frame[method]) then return end
    pcall(frame[method], frame, ...)
end

-- Full Body
function P.FullBody(host)
    local f = host and host._backend and host._backend.frame
    if not f then return end
    -- Use a conservative zoom for full body
    if host.SetPortraitZoom then host:SetPortraitZoom(0.3) end
    -- Reset position and rotation
    sc(f, "SetPosition", 0, 0, 0)
    sc(f, "SetRotation", 0)
end

-- Upper Body
function P.UpperBody(host)
    local f = host and host._backend and host._backend.frame
    if not f then return end
    -- Closer zoom for upper body
    if host.SetPortraitZoom then host:SetPortraitZoom(0.75) end
    sc(f, "SetPosition", 0, 0, 0.15)
    sc(f, "SetRotation", 0)
end

-- Wave (slight zoom-out, more verticality)
function P.Wave(host)
    local f = host and host._backend and host._backend.frame
    if not f then return end
    if host.SetPortraitZoom then host:SetPortraitZoom(0.5) end
    sc(f, "SetPosition", 0, 0, 0.05)
    sc(f, "SetRotation", 0)
end

return P
