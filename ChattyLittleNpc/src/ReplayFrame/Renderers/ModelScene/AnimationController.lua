local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")
local ReplayFrame = CLN.ReplayFrame
ReplayFrame.ModelScene = ReplayFrame.ModelScene or {}
local NS = ReplayFrame.ModelScene

NS.AnimationController = NS.AnimationController or {}

function NS.AnimationController.new()
    return { desiredAnimId = nil }
end

function NS.AnimationController:setDesired(id)
    self.desiredAnimId = id
end

function NS.AnimationController:getDesired()
    return self.desiredAnimId
end

function NS.AnimationController:apply(actor)
    if not (actor and actor.SetAnimation) then return end
    local desired = self.desiredAnimId
    if desired ~= nil then
        pcall(actor.SetAnimation, actor, desired)
        if NS.Diagnostics and NS.Diagnostics.log then
            NS.Diagnostics.log("anim", "Applied desired animation %s", tostring(desired))
        end
    end
end
