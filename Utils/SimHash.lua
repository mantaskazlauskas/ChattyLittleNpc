---@class ChattyLittleNpc
local CLN = LibStub("AceAddon-3.0"):GetAddon("ChattyLittleNpc")

-- SimHash64_CharNgrams.lua
-- SimHash that uses character-based n-grams to make small typos yield near-identical hashes.
---@class SimHash64
local SimHash64 = {}
CLN.SimHash64 = SimHash64

------------------------------------------------------------
-- 1) Lua/WoW bit operations and local references
------------------------------------------------------------
local bit = bit
local band, bor, bxor = bit.band, bit.bor, bit.bxor
local lshift, rshift = bit.lshift, bit.rshift
local floor = math.floor
local byte, sub, gmatch = string.byte, string.sub, string.gmatch

------------------------------------------------------------
-- 2) Two 32-bit FNV-1a variants to form a "64-bit" token hash
------------------------------------------------------------
local FNV32_OFFSET_BASIS_HI = 2166136261
local FNV32_PRIME_HI        = 16777619

local FNV32_OFFSET_BASIS_LO = 3166136261
local FNV32_PRIME_LO        = 16777621

function SimHash64:Hash32_Hi(str)
    local hash = FNV32_OFFSET_BASIS_HI
    for i = 1, #str do
        hash = bxor(hash, byte(str, i))
        hash = band(hash * FNV32_PRIME_HI, 0xFFFFFFFF)
    end
    return hash
end

function SimHash64:Hash32_Lo(str)
    local hash = FNV32_OFFSET_BASIS_LO
    for i = 1, #str do
        hash = bxor(hash, byte(str, i))
        hash = band(hash * FNV32_PRIME_LO, 0xFFFFFFFF)
    end
    return hash
end

function SimHash64:Hash64(str)
    local hi = self:Hash32_Hi(str)
    local lo = self:Hash32_Lo(str)
    return hi, lo
end

------------------------------------------------------------
-- 3) Clean text: convert uppercase -> lowercase
--    and remove any non-alphanumeric
------------------------------------------------------------
function SimHash64:CleanText(text)
    text = text:lower()
    -- Replace any character not in [a-z0-9] with a space or empty
    -- If you want to keep spaces to preserve word boundaries, replace with space
    text = text:gsub("[^a-z0-9]+", "")
    return text
end

------------------------------------------------------------
-- 4) Build n-grams from entire text *as characters*
------------------------------------------------------------
local function buildCharNgrams(fullText, n)
    local ngrams = {}
    local length = #fullText
    -- If text length < n, you'll get zero n-grams
    for i = 1, (length - n + 1) do
        local gram = sub(fullText, i, i + n - 1)
        table.insert(ngrams, gram)
    end
    return ngrams
end

------------------------------------------------------------
-- 5) GenerateHash: character-based n-grams by default
--    e.g. ngramSize=3 or 4 helps with minor typos
--    Returns a hex string "HHHHHHHHLLLLLLLL"
------------------------------------------------------------
function SimHash64:GenerateHash(text, ngramSize, removeFillers)
    -- 1) Clean text
    text = self:CleanText(text)

    -- If no ngramSize provided, default to 3 (common for minor-typo tolerance)
    if not ngramSize then
        ngramSize = 3
    end

    -- 3) Build character-based n-grams
    local charNgrams = buildCharNgrams(text, ngramSize)
    -- If we somehow have zero n-grams (text too short), you may handle fallback
    -- e.g. fallback to hashing entire text as a single token
    if #charNgrams == 0 and #text > 0 then
        table.insert(charNgrams, text)
    end

    -- 4) We'll keep 64 running sums (one per bit)
    local bitSums = {}
    for i = 1, 64 do
        bitSums[i] = 0
    end

    -- 5) For each n-gram, compute the 64-bit hash -> (hi, lo), update bit sums
    for _, token in ipairs(charNgrams) do
        local hi, lo = self:Hash64(token)
        for bitIndex = 0, 63 do
            if self:IsBitSet64(hi, lo, bitIndex) then
                bitSums[bitIndex + 1] = bitSums[bitIndex + 1] + 1
            else
                bitSums[bitIndex + 1] = bitSums[bitIndex + 1] - 1
            end
        end
    end

    -- 6) Construct final 64-bit from sums
    local finalHi, finalLo = 0, 0
    for bitIndex = 0, 63 do
        if bitSums[bitIndex + 1] >= 0 then
            if bitIndex < 32 then
                finalLo = bor(finalLo, lshift(1, bitIndex))
            else
                finalHi = bor(finalHi, lshift(1, bitIndex - 32))
            end
        end
    end

    return string.format("%08X%08X", finalHi, finalLo)
end

------------------------------------------------------------
-- 6) Check if a particular bit is set in our 64-bit (hi, lo)
------------------------------------------------------------
function SimHash64:IsBitSet64(hi, lo, bitIndex)
    if bitIndex < 32 then
        local mask = lshift(1, bitIndex)
        return band(lo, mask) ~= 0
    else
        local mask = lshift(1, bitIndex - 32)
        return band(hi, mask) ~= 0
    end
end

------------------------------------------------------------
-- 7) Compare two 64-bit SimHash hex strings (Hamming distance)
------------------------------------------------------------
function SimHash64:CountSetBits32(x)
    local count = 0
    while x ~= 0 do
        x = band(x, x - 1)
        count = count + 1
    end
    return count
end

function SimHash64:AreSimilar(hashA, hashB, threshold)
    if threshold == nil then
        threshold = 3
    end

    local hiA = tonumber(sub(hashA, 1, 8), 16)
    local loA = tonumber(sub(hashA, 9, 16), 16)
    local hiB = tonumber(sub(hashB, 1, 8), 16)
    local loB = tonumber(sub(hashB, 9, 16), 16)

    local diffHi = bxor(hiA, hiB)
    local diffLo = bxor(loA, loB)

    local distance = self:CountSetBits32(diffHi) + self:CountSetBits32(diffLo)
    return (distance <= threshold), distance
end

------------------------------------------------------------
-- 8) (Optional) Dynamic threshold or "closest match" logic
--    remains the same if you want to keep it.
------------------------------------------------------------
function SimHash64:FindClosestHash(hashTable, text, ngramSize, removeFillers, threshold)
    local textHash = self:GenerateHash(text, ngramSize, removeFillers)

    local bestHash = nil
    local bestDistance = math.huge

    for _, candidateHash in ipairs(hashTable) do
        -- Large threshold to get actual distance
        local _, distance = self:AreSimilar(textHash, candidateHash, 64)
        if distance < bestDistance then
            bestDistance = distance
            bestHash = candidateHash
        end
    end

    if threshold and bestDistance > threshold then
        return nil, bestDistance
    end

    return bestHash, bestDistance
end

------------------------------------------------------------
-- 9) Example test usage
------------------------------------------------------------
function CLN:RunSimHash64TestCases()
    local texts = {
        "While the Vizier does not approve of war profiteering",
        "While the Vizer does not approve of war profiteering",
        "While the Vizier does not approve of war profiteering", -- identical to #1
        "While the Frankenstein does not approve of war profiteering",
    }

    -- Precompute a hash table
    local hashTable = {}
    for i, t in ipairs(texts) do
        hashTable[i] = self.SimHash64:GenerateHash(t, 3, false)
        self:Print(("Text #%d Hash = %s"):format(i, hashTable[i]))
    end

    -- Compare #1 to #2, #4, etc.
    local refHash = hashTable[1]
    for i = 2, #hashTable do
        local isSimilar, distance = self.SimHash64:AreSimilar(refHash, hashTable[i], 5)
        self:Print(("Compare #1 vs #%d => Distance=%d, Similar? %s"):
            format(i, distance, isSimilar and "YES" or "NO"))
    end

    -- Example: find closest among #2..#4 for text #1
    local bestHash, bestDist = self.SimHash64:FindClosestHash(hashTable, texts[1], 3, false, nil)
    self:Print(("Closest match for #1's text = %s (distance=%d)"):format(bestHash or "N/A", bestDist))
end

SLASH_SIMHASH64TEST1 = "/simhash64test"
SlashCmdList["SIMHASH64TEST"] = function()
    CLN:RunSimHash64TestCases()
end
