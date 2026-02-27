---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- PlayerModel renderer presets. We approximate via zoom/position/rotation APIs.
-- Exposes: ReplayFrame.PlayerPresets with functions(host) -> ()

ReplayFrame = ReplayFrame or {}
ReplayFrame.PlayerPresets = {}
local P = ReplayFrame.PlayerPresets

-- Full Body
function P.FullBody(host)
    if not host then return end
    if host.SetPortraitZoom then host:SetPortraitZoom(0.3) end
    if host.SetPosition then host:SetPosition(0, 0, 0) end
    if host.SetRotation then host:SetRotation(0) end
end

-- Upper Body (bust portrait — head + shoulders)
function P.UpperBody(host)
    if not host then return end
    if host.SetPortraitZoom then host:SetPortraitZoom(0.70) end
    if host.SetPosition then host:SetPosition(0, 0, 0.08) end
    if host.SetRotation then host:SetRotation(0) end
end

-- Wave (slight zoom-out for arm gesture)
function P.Wave(host)
    if not host then return end
    if host.SetPortraitZoom then host:SetPortraitZoom(0.55) end
    if host.SetPosition then host:SetPosition(0, 0, 0.02) end
    if host.SetRotation then host:SetRotation(0) end
end

return P
