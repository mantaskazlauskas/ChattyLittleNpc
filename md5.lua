---@class ChattyLittleNpc
local ChattyLittleNpc = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

-- MD5.lua (Pure Lua MD5 implementation)
-- This is a simple MD5 implementation you can use in your WoW addon.

local MD5 = {}
ChattyLittleNpc.MD5 = MD5

local K = {
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
}


local floor,modf = math.floor,math.modf
local byte,char,sub = string.byte,string.char,string.sub
local band,bor,bxor,bnot = bit.band,bit.bor,bit.bxor,bit.bnot
local lshift,rshift = bit.lshift,bit.rshift

-- Left rotate function
function MD5:lrot(x, n)
    return lshift(x, n) + rshift(x, 32 - n)
end

-- Padding function
function MD5:Padding(len)
    local bits = len * 8
    local pad_len = 56 - (len + 1) % 64
    if pad_len < 0 then pad_len = pad_len + 64 end
    local padding = "\128" .. string.rep("\0", pad_len) .. char(bits % 256)
    bits = floor(bits / 256)
    for i = 1, 7 do
        padding = padding .. char(bits % 256)
        bits = floor(bits / 256)
    end
    return padding
end

-- Process the message in successive 512-bit chunks
function MD5:ProcessChunk(chunk, H0, H1, H2, H3)
    local F, G, temp
    local a, b, c, d = H0, H1, H2, H3

    for i = 0, 63 do
        if i < 16 then
            F = (b and c) or (b and d)
            G = i
        elseif i < 32 then
            F = (d and b) or (c and b)
            G = (5 * i + 1) % 16
        elseif i < 48 then
            F = bxor(b, c, d)
            G = (3 * i + 5) % 16
        else
            F = bxor(c, bor(b, bnot(d)))
            G = (7 * i) % 16
        end

        local shift_amount
        if i % 4 == 0 then
            shift_amount = 7
        elseif i % 4 == 1 then
            shift_amount = 12
        elseif i % 4 == 2 then
            shift_amount = 17
        else
            shift_amount = 22
        end

        temp = d
        d = c
        c = b
        b = b + self:lrot(a + F + K[i + 1] + chunk[G + 1], shift_amount)
        a = temp
    end

    H0 = H0 + a
    H1 = H1 + b
    H2 = H2 + c
    H3 = H3 + d

    return H0, H1, H2, H3
end

-- Main MD5 function
function MD5:GenerateHash(message)
    -- Reset MD5 initialization constants
    local H0, H1, H2, H3 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476

    -- Pre-process the message
    message = message .. self:Padding(#message)

    for i = 1, #message, 64 do
        local chunk = {byte(sub(message, i, i + 63), 1, 64)}
        H0, H1, H2, H3 = self:ProcessChunk(chunk, H0, H1, H2, H3)
    end

    return string.format("%08x%08x%08x%08x", H0, H1, H2, H3)
end

function ChattyLittleNpc:RunMD5TestCases()
    local testCases = {
        "Hello, World!",                      -- Basic test
        "1234567890",                         -- Numbers only
        "!@#$%^&*()_+-=[]{};':\",.<>/?",      -- Special characters
        "The quick brown fox jumps over the lazy dog!", -- Sentence with spaces and punctuation
        "🙂🚀✨",                             -- Unicode emojis (depends on Lua environment support)
        "\n\t\r",                             -- Control characters (newline, tab, carriage return)
        "A very, very long string with lots of characters! 1234567890!@#$%^&*()_+-=[]{};':\",.<>/?", -- Long string
        "MixedCASE123!@#",                    -- Mixed case with numbers and special characters
    }

    for _, text in ipairs(testCases) do
        print("Original Text: " .. text)
        local hash = self.MD5:GenerateHash(text)
        print("MD5 Hash: " .. hash)
        print("--------------------------")
    end
end

SLASH_MD5TEST1 = "/md5test"
SlashCmdList["MD5TEST"] = function()
    ChattyLittleNpc:RunMD5TestCases()
end
