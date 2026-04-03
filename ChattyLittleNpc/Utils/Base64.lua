---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

-- Base64 Encoding in Pure Lua
---@class Base64
local Base64 = {}
CLN.Base64 = Base64

local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

-- Function to encode a string to Base64
function Base64:Encode(data)
    return ((data:gsub('.', function(x)
        local r, b = '', x:byte()
        for i = 8, 1, -1 do
            r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0')
        end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if (#x < 6) then return '' end
        local c = 0
        for i = 1, 6 do
            c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0)
        end
        return b:sub(c + 1, c + 1)
    end) .. ({
        '',
        '==',
        '='
    })[#data % 3 + 1])
end

-- Function to decode a Base64 string
function Base64:Decode(data)
    data = string.gsub(data, '[^'..b..'=]', '') -- Remove any characters not in the Base64 character set
    local padding = 0

    -- Remove padding characters if any
    if (string.sub(data, -2) == '==') then
        padding = 2
        data = string.sub(data, 1, -3)
    elseif (string.sub(data, -1) == '=') then
        padding = 1
        data = string.sub(data, 1, -2)
    end

    -- Convert Base64 string back to binary string
    local binaryData = (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r, f = '', (b:find(x) - 1)
        for i = 6, 1, -1 do
            r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0')
        end
        return r
    end))

    -- Remove the extra padding in binary
    if (padding > 0) then
        binaryData = binaryData:sub(1, -(padding * 2 + 1))
    end

    -- Convert binary string back to the original string
    return (binaryData:gsub('%d%d%d%d%d%d%d%d', function(x)
        if (#x ~= 8) then return '' end
        local c = 0
        for i = 1, 8 do
            c = c + (x:sub(i, i) == '1' and 2 ^ (8 - i) or 0)
        end
        return string.char(c)
    end))
end

-- TestCases:
function CLN:RunBase64TestCases()
    local testCases = {
        "Hello, World!",           -- Basic test
        "1234567890",              -- Numbers only
        "!@#$%^&*()_+-=[]{};':\",.<>/?", -- Special characters
        "The quick brown fox jumps over the lazy dog!", -- Sentence with spaces and punctuation
        "🙂🚀✨",                 -- Unicode emojis
        "\n\t\r",                 -- Control characters (newline, tab, carriage return)
        "A very, very long string with lots of characters! 1234567890!@#$%^&*()_+-=[]{};':\",.<>/?" -- Long string
    }

    for _, text in ipairs(testCases) do
    if CLN and CLN.Logger then CLN.Logger:info("Original Text: " .. tostring(text), true, CLN.Utils.LogCategories.misc) end
        local encoded = self.Base64:Encode(text)
    if CLN and CLN.Logger then CLN.Logger:info("Encoded: " .. tostring(encoded), true, CLN.Utils.LogCategories.misc) end
        local decoded = self.Base64:Decode(encoded)
    if CLN and CLN.Logger then CLN.Logger:info("Decoded: " .. tostring(decoded), true, CLN.Utils.LogCategories.misc) end
    if CLN and CLN.Logger then CLN.Logger:info("Match: " .. tostring(text == decoded), true, CLN.Utils.LogCategories.misc) end
    end
end

SLASH_CHATTEST1 = "/base64test"
SlashCmdList["CHATTEST"] = function()
    CLN:RunBase64TestCases()
end