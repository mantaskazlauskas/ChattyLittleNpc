---@class ChattyLittleNpc
local CLN = _G.ChattyLittleNpc

---@class ReplayFrame
local ReplayFrame = CLN.ReplayFrame

-- =========================
-- Core helpers
-- =========================

-- Cache for normalized text to avoid repeated processing
local _normCache = {}
local _cacheSize = 0
local MAX_CACHE_SIZE = 100

function ReplayFrame:TA_Normalize(text)
    if not text or type(text) ~= "string" then return "" end
    
    -- Check cache first
    if _normCache[text] then return _normCache[text] end
    
    local s = self.ToSingleLine and self:ToSingleLine(text) or text
    s = s:lower()
    
    -- Cache management
    if _cacheSize >= MAX_CACHE_SIZE then
        -- Clear cache when full (simple strategy)
        _normCache = {}
        _cacheSize = 0
    end
    _normCache[text] = s
    _cacheSize = _cacheSize + 1
    
    return s
end

function ReplayFrame:TA_Tokenize(text)
    local s = self:TA_Normalize(text)
    -- Replace punctuation with spaces; keep apostrophes within words
    s = s:gsub("[^%w%s']", " ")
    local words = {}
    for w in s:gmatch("%S+") do 
        table.insert(words, w) 
    end
    return words
end

function ReplayFrame:TA_FirstNWords(text, n)
    local words = self:TA_Tokenize(text)
    n = math.max(0, math.min(n or #words, #words))
    return table.concat(words, " ", 1, n)
end

function ReplayFrame:TA_CountWords(text)
    local words = self:TA_Tokenize(text)
    return #words
end

function ReplayFrame:TA_CountSentences(text)
    local s = self:TA_Normalize(text)
    local count = 0
    for _ in s:gmatch("[%.!?]+") do count = count + 1 end
    return count
end

function ReplayFrame:TA_HasExclamation(text)
    local s = self:TA_Normalize(text)
    return s:find("!") ~= nil
end

function ReplayFrame:TA_HasQuestion(text)
    local s = self:TA_Normalize(text)
    return s:find("%?") ~= nil
end

-- Return basic punctuation stats across sentences.
-- Counts sentences by trailing punctuation blocks and classifies by presence of '!' or '?'.
-- Returns a table: { total = n, questions = q, exclamations = e, periods = p }
function ReplayFrame:TA_SentencePunctuationStats(text)
    local s = self:TA_Normalize(text)
    local total, q, e, p = 0, 0, 0, 0
    -- Iterate over punctuation blocks like ".", "!", "?", or combinations "!?", ".." etc.
    for punct in s:gmatch("[%.!?]+") do
        total = total + 1
        local hadMark = false
        if punct:find("!") then e = e + 1; hadMark = true end
        if punct:find("%?") then q = q + 1; hadMark = true end
        if not hadMark then p = p + 1 end
    end
    return { total = total, questions = q, exclamations = e, periods = p }
end

-- =========================
-- Config-backed lexicons with pattern matching
-- =========================

local function ta_mergeLists(defaults, custom)
    local list = {}
    for _, v in ipairs(defaults or {}) do list[#list+1] = v end
    if type(custom) == "table" then
        for _, v in ipairs(custom) do list[#list+1] = tostring(v):lower() end
    end
    return list
end

local function ta_toSet(list)
    local t = {}
    for _, v in ipairs(list or {}) do t[v] = true end
    return t
end

-- Cached lexicons with timestamp
local _lexCache = nil
local _lexCacheTime = 0
local LEXICON_CACHE_DURATION = 30 -- seconds

local function ta_getLexicons()
    local now = GetTime and GetTime() or 0
    if _lexCache and (now - _lexCacheTime) < LEXICON_CACHE_DURATION then
        return _lexCache
    end
    
    local prof = CLN and CLN.db and CLN.db.profile or {}
    local greetingWords = ta_mergeLists({
        "hello","hi","hey","greetings","hail","welcome","howdy","sup","yo",
        -- faction/race-flavored single-word cues
        "lok'tar","shorel'aran","how","salutations","ahoy",
        -- common wow variations
        "hail","well","greet","blessing","blessings",
    }, prof.greetingWords)
    
    local greetingPhrases = ta_mergeLists({
        -- generic
        "well met","good day","good morning","good evening","good afternoon",
        "hello there","hey there","hello friend","hey friend","hail friend","well hello",
        "greetings traveler","greetings traveller","greetings wanderer","a thousand greetings",
        "well met traveler","well met traveller","welcome traveler","welcome traveller",
        -- stormwind/human
        "king's honor friend","light be with you","blessings of the light",
        -- night elf
        "elune adore","goddess watch over you","elune-adore","ishnu-alah",
        -- blood elf/high elf
        "salama ashal'anore","anu belore dela'na","belore'doranei","shorel'aran",
        -- tauren
        "may the eternal sun shine upon you","an'she guide you","peace friend",
        "earth mother be with you","walk with the earth mother",
        -- orc
        "lok'tar ogar","strength and honor","blood and thunder",
        -- troll
        "hey mon","how ya doin mon","how ya doin', mon","how you doin mon",
        "stay away from da voodoo","darkspear never die",
        -- goblin
        "time is money friend","pleasure doing business",
        -- dwarf
        "keep yer feet on the ground","by my beard",
        -- gnome
        "powered up","short and sweet",
        -- undead
        "what joy is there in this curse",
        -- draenei
        "the light shall burn you","gift of the naaru",
    }, prof.greetingPhrases)
    
    local serviceWords = ta_mergeLists({
        "greet","greeting","salutations","ahoy","hail","welcome",
        "friend","traveler","traveller","champion","hero","adventurer",
        "stranger","visitor","customer","citizen","mortal",
    }, prof.serviceWords)
    
    local servicePhrases = ta_mergeLists({
        -- generic service/shop/trainer greeters
        "what can i do for you","what can i help you with","how can i help",
        "can i help you","looking for something","you need something",
        "something for you","what brings you here","state your business",
        "speak your business","how may i assist","at your service",
        "greetings friend","greetings hero","greetings champion",
        "welcome to","step right up","come one come all",
        -- orcish/tribal variants
        "what do you need","what you want","you want something",
        -- polite/formal
        "how may i be of service","what service can i provide",
        "might i interest you","perhaps you seek",
        -- racial flavor
        "light bless you","the light be with you","may the light guide you",
        -- shop/vendor specific
        "finest wares","best prices","quality goods","take a look",
    }, prof.servicePhrases)
    
    _lexCache = {
        greetingWords = ta_toSet(greetingWords),
        greetingPhrases = greetingPhrases,
        serviceWords = ta_toSet(serviceWords),
        servicePhrases = servicePhrases,
    }
    _lexCacheTime = now
    return _lexCache
end

-- =========================
-- High-level detectors with confidence scoring
-- =========================

function ReplayFrame:HasGreetingInFirstWords(text, limit)
    limit = limit or 10
    local words = self:TA_Tokenize(text)
    if #words == 0 then return false end
    local n = math.min(limit, #words)
    local lex = ta_getLexicons()
    
    -- Early exit for strong single-word matches in first 3 words
    for i = 1, math.min(3, n) do
        if lex.greetingWords[words[i]] then return true end
    end
    
    -- Check service words in broader range
    for i = 1, n do
        if lex.serviceWords[words[i]] then return true end
    end
    
    -- Phrase matching with early termination
    local segment = table.concat(words, " ", 1, n)
    for _, p in ipairs(lex.greetingPhrases) do
        if segment:find(p, 1, true) then return true end
    end
    for _, p in ipairs(lex.servicePhrases) do
        if segment:find(p, 1, true) then return true end
    end
    
    -- Enhanced check: use talk animation analysis for subtle greetings
    if self.ChooseTalkAnimIdForText then
        -- Extract first sentence for analysis
        local firstSentence = segment
        local dotPos = text:find("%.")
        if dotPos and dotPos > 10 and dotPos < (#text * 0.5) then
            firstSentence = text:sub(1, dotPos)
        elseif #text > 60 then
            firstSentence = text:sub(1, 60)
        end
        
        -- Use talk animation analysis - normal talk (60) in short opening statements
        -- often indicates greetings vs exclamations (64) or questions (65)
        local animId = self:ChooseTalkAnimIdForText(firstSentence)
        if animId == 60 and #firstSentence < 100 then
            -- Additional heuristics for potential greetings missed by patterns
            local lowerFirst = firstSentence:lower()
            local hasGreetingIndicators = lowerFirst:find("welcome") or 
                                        lowerFirst:find("you") or
                                        lowerFirst:find("what") or
                                        lowerFirst:find("how") or
                                        lowerFirst:find("come") or
                                        lowerFirst:find("need") or
                                        lowerFirst:find("help") or
                                        lowerFirst:find("seek")
            if hasGreetingIndicators then
                return true
            end
        end
    end
    
    return false
end

-- More detailed analysis for advanced animation decisions
function ReplayFrame:GetGreetingConfidence(text, limit)
    limit = limit or 10
    local words = self:TA_Tokenize(text)
    if #words == 0 then return 0 end
    local n = math.min(limit, #words)
    local lex = ta_getLexicons()
    local confidence = 0
    
    -- Strong greeting words in first position get highest confidence
    if n >= 1 and lex.greetingWords[words[1]] then
        confidence = confidence + 0.8
    end
    
    -- Service words add moderate confidence
    for i = 1, n do
        if lex.serviceWords[words[i]] then
            confidence = confidence + 0.3
            break
        end
    end
    
    -- Phrase matches add confidence based on position
    local segment = table.concat(words, " ", 1, n)
    for _, p in ipairs(lex.greetingPhrases) do
        local start, _ = segment:find(p, 1, true)
        if start then
            -- Earlier phrases get higher confidence
            local positionBonus = math.max(0, 0.6 - (start - 1) * 0.1)
            confidence = confidence + 0.5 + positionBonus
            break
        end
    end
    
    -- Enhanced analysis using talk animation classification
    if confidence < 0.7 and self.ChooseTalkAnimIdForText then
        -- Extract first sentence for analysis
        local firstSentence = segment
        local dotPos = text:find("%.")
        if dotPos and dotPos > 10 and dotPos < (#text * 0.5) then
            firstSentence = text:sub(1, dotPos)
        elseif #text > 60 then
            firstSentence = text:sub(1, 60)
        end
        
        -- Use talk animation analysis
        local animId = self:ChooseTalkAnimIdForText(firstSentence)
        if animId == 60 and #firstSentence < 100 then
            -- Normal talk animation in short opening suggests potential greeting
            local lowerFirst = firstSentence:lower()
            local greetingIndicatorCount = 0
            
            -- Count greeting indicators
            if lowerFirst:find("welcome") then greetingIndicatorCount = greetingIndicatorCount + 1 end
            if lowerFirst:find("you") then greetingIndicatorCount = greetingIndicatorCount + 1 end
            if lowerFirst:find("what") then greetingIndicatorCount = greetingIndicatorCount + 1 end
            if lowerFirst:find("how") then greetingIndicatorCount = greetingIndicatorCount + 1 end
            if lowerFirst:find("come") then greetingIndicatorCount = greetingIndicatorCount + 1 end
            if lowerFirst:find("need") then greetingIndicatorCount = greetingIndicatorCount + 1 end
            if lowerFirst:find("help") then greetingIndicatorCount = greetingIndicatorCount + 1 end
            if lowerFirst:find("seek") then greetingIndicatorCount = greetingIndicatorCount + 1 end
            
            -- Add confidence based on indicator count
            if greetingIndicatorCount > 0 then
                confidence = confidence + math.min(0.4, greetingIndicatorCount * 0.15)
            end
        end
    end
    
    return math.min(1.0, confidence)
end

-- Convenience summary for animation logic or UI
function ReplayFrame:AnalyzeText(text)
    local words = self:TA_Tokenize(text)
    local first10 = table.concat(words, " ", 1, math.min(10, #words))
    local wordCount = #words
    local sentenceCount = self:TA_CountSentences(text)
    local hasGreet = self:HasGreetingInFirstWords(text, 10)
    local greetConfidence = self:GetGreetingConfidence(text, 10)
    local hasExcl = self:TA_HasExclamation(text)
    local hasQuest = self:TA_HasQuestion(text)
    
    -- Determine animation recommendation
    local animationHint = "talk"
    if hasGreet and greetConfidence > 0.5 then
        animationHint = "wave_then_talk"
    elseif hasExcl then
        animationHint = "talk_exclamation"
    elseif hasQuest then
        animationHint = "talk_question"
    end
    
    return {
        wordCount = wordCount,
        sentenceCount = sentenceCount,
        firstSegment = first10,
        hasGreeting = hasGreet,
        greetingConfidence = greetConfidence,
        hasExclamation = hasExcl,
        hasQuestion = hasQuest,
        animationHint = animationHint,
        -- Additional metadata for future features
        textComplexity = wordCount > 20 and "high" or (wordCount > 8 and "medium" or "low"),
        isFormal = first10:find("thou") or first10:find("thee") or first10:find("thy"),
    }
end

