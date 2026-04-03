--- Mixin for CLNModelSceneActorTemplate.
--- Provides OnAnimFinished bridging from XML script to Lua callbacks.
CLNModelSceneActorMixin = {}

function CLNModelSceneActorMixin:OnAnimFinished()
    if self.onAnimFinishedCallback then
        self:onAnimFinishedCallback()
    end
end

--- Set a callback that fires when the actor's model animation finishes.
---@param callback fun(actor: any)|nil
function CLNModelSceneActorMixin:SetOnAnimFinishedCallback(callback)
    self.onAnimFinishedCallback = callback
end
