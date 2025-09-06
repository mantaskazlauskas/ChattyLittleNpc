local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")
local ReplayFrame = CLN.ReplayFrame
ReplayFrame.ModelScene = ReplayFrame.ModelScene or {}
local NS = ReplayFrame.ModelScene

NS.Stabilizer = NS.Stabilizer or {}

local function hasEnumBlend()
    return _G and _G.Enum and _G.Enum.ModelBlendOperation
end

function NS.Stabilizer.stabilize(actor, opts)
    opts = opts or {}
    if not actor then return end
    if actor.SetAnimationBlendOperation and hasEnumBlend() then
        pcall(actor.SetAnimationBlendOperation, actor, _G.Enum.ModelBlendOperation.None)
    end
    if actor.SetDesaturated then pcall(actor.SetDesaturated, actor, false) end
    if actor.SetAlpha then pcall(actor.SetAlpha, actor, 1.0) end
    if not opts.respectAnimationIntent and actor.SetAnimation then
        -- force idle only if caller doesn't want to respect intent
        pcall(actor.SetAnimation, actor, 0)
    end
    if NS.Diagnostics and NS.Diagnostics.log then
        NS.Diagnostics.log("stabilize", "Applied stabilization (respectAnim=%s)", tostring(opts.respectAnimationIntent))
    end
end
