local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")
local ReplayFrame = CLN.ReplayFrame
ReplayFrame.ModelScene = ReplayFrame.ModelScene or {}
local NS = ReplayFrame.ModelScene

NS.Utils = NS.Utils or {}

function NS.Utils.safeCall(tag, fn, ...)
    if type(fn) ~= "function" then return false end
    local ok, res1, res2, res3 = pcall(fn, ...)
    return ok, res1, res2, res3
end

function NS.Utils.finite(x, fallback)
    x = tonumber(x)
    if not x or x ~= x or x == math.huge or x == -math.huge then return fallback end
    return x
end
