# Lua Environment in WoW (Patch 12.0.1)

> WoW uses Lua 5.1 with modifications. No os/io/debug/file libraries.
> Full reference: https://warcraft.wiki.gg/wiki/Lua_functions

## Available Libraries

| Library | Status | Notes |
|---------|--------|-------|
| Basic functions | ✅ Available | assert, error, pcall, xpcall, type, select, etc. |
| `string` | ✅ Available | All standard + WoW extensions |
| `table` | ✅ Available | All standard + table.wipe, table.removemulti |
| `math` | ✅ Available | Trig functions use **degrees**, not radians |
| `bit` | ✅ Available | Bitwise operations (bit.band, bit.bor, etc.) |
| `coroutine` | ✅ Available | Use sparingly (memory intensive) |
| `os` | ❌ Removed | No operating system access |
| `io` | ❌ Removed | No file I/O |
| `debug` | ❌ Removed | No debug library |
| `package` | ❌ Removed | No package/require |
| `loadfile` | ❌ Removed | Cannot load files |
| `dofile` | ❌ Removed | Cannot execute files |

## Basic Functions

```lua
assert(value [, errormsg])      -- Assert value is truthy
collectgarbage()                -- Force garbage collection
error("message", level)         -- Throw error
pcall(func, ...)                -- Protected call (returns success, result)
xpcall(func, errorHandler, ...) -- Protected call with error handler
type(var)                       -- Returns "nil","boolean","number","string","table","function","thread","userdata"
select(index, list)             -- Returns subset or count ("#")
pairs(table)                    -- Iterator for all key/value pairs
ipairs(table)                   -- Iterator for sequential integer keys
next(table, index)              -- Next key/value pair
unpack(table [, start [, end]]) -- Returns table contents as values
tostring(arg)                   -- Convert to string
tonumber(arg [, base])          -- Convert to number
setmetatable(table, metatable)  -- Set metatable
getmetatable(obj)               -- Get metatable
rawget(table, index)            -- Get without metamethods
rawset(table, index, value)     -- Set without metamethods
rawequal(v1, v2)                -- Compare without metamethods
loadstring("lua code")          -- Parse string as Lua, returns function
time()                          -- Seconds since epoch
date(format, time)              -- Formatted date string
```

## String Functions

Standard Lua string operations:
```lua
string.format(fmt, ...)         -- format() alias
string.find(s, pattern [, init [, plain]])  -- strfind() alias
string.match(s, pattern [, init])           -- strmatch() alias
string.gmatch(s, pattern)       -- gmatch() alias
string.gsub(s, pattern, repl [, n])         -- gsub() alias
string.sub(s, i [, j])          -- strsub() alias
string.len(s)                   -- strlen() alias
string.lower(s)                 -- strlower() alias
string.upper(s)                 -- strupper() alias
string.rep(s, n)                -- strrep() alias
string.reverse(s)               -- strrev() alias
string.byte(s [, i])            -- strbyte() alias
string.char(...)                -- strchar() alias
```

WoW-specific string functions:
```lua
strtrim(s [, chars])            -- Trim whitespace or specified chars
strsplit(delimiter, s [, pieces]) -- Split string, returns multiple values
strsplittable(delimiter, s [, pieces]) -- Split string, returns table
strjoin(delimiter, s1, s2, ...) -- Join strings with delimiter
strconcat(...)                  -- Concatenate all args
tostringall(...)                -- Convert all args to strings
strlenutf8(s)                   -- UTF-8 aware string length
strcmputf8i(s1, s2)             -- UTF-8 case-insensitive compare
```

## Math Functions

**Important**: WoW trig functions work in **degrees**, not radians!

```lua
math.abs(x)        -- abs(x)
math.ceil(x)       -- ceil(x)
math.floor(x)      -- floor(x)
math.max(x, ...)   -- max(x, ...)
math.min(x, ...)   -- min(x, ...)
math.sqrt(x)       -- sqrt(x)
math.random([m [, n]]) -- random([m [, n]])
math.fmod(x, y)    -- fmod(x, y)
math.exp(x)        -- exp(x)
math.log(x)        -- log(x) (natural log)
math.log10(x)      -- log10(x)

-- DEGREES (not radians!)
math.sin(degrees)   -- sin(degrees)
math.cos(degrees)   -- cos(degrees)
math.tan(degrees)   -- tan(degrees)
math.asin(x)        -- asin(x) returns degrees
math.acos(x)        -- acos(x) returns degrees
math.atan(x)        -- atan(x) returns degrees
math.atan2(y, x)    -- atan2(y, x) returns degrees
math.rad(degrees)    -- deg → rad conversion
math.deg(radians)    -- rad → deg conversion

-- WoW-specific
fastrandom([m [, n]])  -- Faster than math.random
```

**Constants**: `math.pi`, `math.huge`

## Table Functions

```lua
table.insert(t [, pos], value)   -- tinsert() alias
table.remove(t [, pos])          -- tremove() alias
table.sort(t [, comp])           -- sort() alias
table.concat(t [, sep, i, j])   -- Concatenate to string
table.maxn(t)                    -- Largest positive integer key
```

WoW-specific:
```lua
table.wipe(t)                    -- wipe() alias — clears ALL keys
table.removemulti(t [, pos [, count]]) -- Remove multiple elements
table.create(arraySizeHint [, nodeSizeHint]) -- Pre-allocate table
```

## Bit Operations

```lua
bit.band(a, ...)    -- Bitwise AND
bit.bor(a, ...)     -- Bitwise OR
bit.bxor(a, ...)    -- Bitwise XOR
bit.bnot(a)         -- Bitwise NOT
bit.lshift(a, n)    -- Left shift
bit.rshift(a, n)    -- Right shift (logical)
bit.arshift(a, n)   -- Arithmetic right shift
bit.mod(a, n)       -- Signed modulus
```

## Coroutines

```lua
coroutine.create(f)              -- Create coroutine
coroutine.resume(co [, ...])     -- Resume/start coroutine
coroutine.yield(...)             -- Yield from coroutine
coroutine.wrap(f)                -- Create callable coroutine wrapper
coroutine.status(co)             -- "running", "suspended", "normal", "dead"
coroutine.running()              -- Current coroutine
```

## Environment Functions

```lua
getfenv(func_or_level)           -- Get function environment
setfenv(func_or_level, table)    -- Set function environment
```

## Metatables

WoW supports standard Lua metamethods:
```lua
__index     -- Table/function for missing key lookups
__newindex   -- Table/function for new key assignments
__call       -- Make table callable
__tostring   -- Custom tostring behavior
__add, __sub, __mul, __div, __mod, __pow, __unm  -- Arithmetic
__eq, __lt, __le  -- Comparison
__concat     -- String concatenation (..)
__len        -- Length operator (#)
__gc         -- Garbage collection (limited)
__metatable  -- Protect metatable access
```

## WoW-Specific Globals

```lua
-- Proxy objects (for GC-less userdata)
newproxy(boolean_or_proxy)  -- Creates userdata with shareable metatable

-- Security
issecure()                  -- True if currently executing secure code
issecurevariable(table, key) : isSecure, taintedBy
hooksecurefunc([table,] "name", hookFunc)  -- Secure post-hook
securecall(func_or_name, ...)  -- Call without spreading taint
forceinsecure()             -- Force insecure execution

-- Debug output
print(...)                  -- Chat frame output
DevTools_Dump(value)        -- Pretty-print table (if Blizzard_DebugTools loaded)
```

## String Metatable

All strings have their metatable set to index the `string` table:
```lua
-- These are equivalent:
local s = string.format("%d", 42)
local s = ("%d"):format(42)

-- Method syntax works on variables:
local upper = myString:upper()
local parts = myString:split(",")
```

## Patterns (Lua Pattern Matching)

WoW uses Lua patterns (not regex):

| Pattern | Matches |
|---------|---------|
| `.` | Any character |
| `%a` | Letter |
| `%d` | Digit |
| `%w` | Alphanumeric |
| `%s` | Whitespace |
| `%p` | Punctuation |
| `%l` | Lowercase |
| `%u` | Uppercase |
| `%c` | Control character |
| `%x` | Hex digit |
| `%A` | Non-letter (uppercase = complement) |
| `[set]` | Character class |
| `[^set]` | Complement class |
| `*` | 0 or more (greedy) |
| `+` | 1 or more (greedy) |
| `-` | 0 or more (non-greedy) |
| `?` | 0 or 1 |
| `^` | Start of string |
| `$` | End of string |
| `(...)` | Capture group |
| `%b()` | Balanced match |

**Escape special characters with `%`**: `%.` `%[` `%)` etc.
