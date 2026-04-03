-- Timer.lua - Timer utility
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
    local ticker = C_Timer.NewTicker(interval, callback)
    table.insert(self.activeTimers, ticker)
    return ticker
end

-- Cancel a repeating timer
---@param timer table Timer handle returned from ScheduleRepeatingTimer
function TimerUtil:CancelTimer(timer)
    if timer then
        if timer.Cancel then
            timer:Cancel()
        elseif timer.cancelled ~= nil then
            timer.cancelled = true
        end
        for i = #self.activeTimers, 1, -1 do
            if self.activeTimers[i] == timer then
                table.remove(self.activeTimers, i)
                break
            end
        end
    end
end

-- Cancel all timers
function TimerUtil:CancelAllTimers()
    for _, timer in ipairs(self.activeTimers) do
        if timer.Cancel then
            timer:Cancel()
        elseif timer.cancelled ~= nil then
            timer.cancelled = true
        end
    end
    wipe(self.activeTimers)
end

-- Export globally for the addon
_G.ChattyLittleNpc = _G.ChattyLittleNpc or {}
_G.ChattyLittleNpc.TimerUtil = TimerUtil

return TimerUtil
