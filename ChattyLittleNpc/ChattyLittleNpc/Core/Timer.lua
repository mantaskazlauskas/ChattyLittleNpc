-- Timer.lua - Timer utility to replace AceTimer
-- Provides C_Timer wrappers for delayed and repeating timers

---@class TimerUtil
local TimerUtil = {}

-- Active repeating timers
TimerUtil.activeTimers = {}

-- Schedule a one-time delayed callback
---@param delay number Delay in seconds
---@param callback function Function to call
function TimerUtil:ScheduleTimer(delay, callback)
    C_Timer.After(delay, callback)
end

-- Schedule a repeating timer
---@param interval number Interval in seconds
---@param callback function Function to call repeatedly
---@return table timer Timer handle (can be used to cancel)
function TimerUtil:ScheduleRepeatingTimer(interval, callback)
    local timer = {
        cancelled = false,
        interval = interval,
        callback = callback
    }
    
    local function tick()
        if timer.cancelled then return end
        callback()
        C_Timer.After(interval, tick)
    end
    
    C_Timer.After(interval, tick)
    table.insert(self.activeTimers, timer)
    
    return timer
end

-- Cancel a repeating timer
---@param timer table Timer handle returned from ScheduleRepeatingTimer
function TimerUtil:CancelTimer(timer)
    if timer then
        timer.cancelled = true
    end
end

-- Cancel all timers
function TimerUtil:CancelAllTimers()
    for _, timer in ipairs(self.activeTimers) do
        timer.cancelled = true
    end
    wipe(self.activeTimers)
end

-- Export globally for the addon
_G.ChattyLittleNpc = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc.TimerUtil = TimerUtil

return TimerUtil
