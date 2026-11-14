-- Ein kleines WoW ohne WoW: lädt das Addon wie der Client (Dateien in der Reihenfolge der .toc,
-- gemeinsamer Namensraum) und spielt Events, Zeit und Nachrichten nach. Aufgezeichnet wird alles,
-- was beim Spieler ankommt: Chatzeilen, Töne, geöffnete Fenster, gesendeter Chat, Addon-Nachrichten
-- und Lua-Fehler.
--
-- Jede Welt hat ihre eigene Umgebung (setfenv): Tests beeinflussen sich nicht gegenseitig.
-- Unbekannte Blizzard-Funktionen sind harmlose Platzhalter (rufbar, liefern nil). Was für einen Test
-- zählt, wird unten echt nachgebaut – oder im Test per w.env.Funktion = … überschrieben.
local M = {}

local unpack = unpack or table.unpack

-- Platzhalter für unbekannte Blizzard-APIs ---------------------------------------------------------
local Mock
local mockMeta = {}
mockMeta.__index = function(t, k)
    local m = Mock()
    rawset(t, k, m)
    return m
end
mockMeta.__call = function() return nil end
Mock = function() return setmetatable({}, mockMeta) end
M.Mock = Mock

-- Lua-Funktionen, die es im Client als globale Namen gibt
local function LuaBuiltins(env, random)
    for _, k in ipairs({ "assert", "error", "ipairs", "pairs", "next", "pcall", "xpcall", "select", "type",
        "tonumber", "tostring", "rawget", "rawset", "rawequal", "setmetatable", "getmetatable", "unpack",
        "loadstring", "coroutine", "bit", "collectgarbage", "debugstack" }) do
        env[k] = _G[k]
    end
    env.string = string
    env.table = table
    local m = {}
    for k, v in pairs(math) do m[k] = v end
    m.random = random
    env.math = m
    env.strlen, env.strsub, env.strfind, env.strmatch, env.gsub, env.strrep = string.len, string.sub, string.find, string.match, string.gsub, string.rep
    env.strbyte, env.strchar, env.gmatch, env.strlower, env.strupper, env.format = string.byte, string.char, string.gmatch, string.lower, string.upper, string.format
    env.floor, env.ceil, env.abs, env.min, env.max, env.sqrt, env.mod = math.floor, math.ceil, math.abs, math.min, math.max, math.sqrt, math.fmod
    env.random = random
    env.tinsert, env.tremove, env.sort, env.wipe = table.insert, table.remove, table.sort, function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end
    env.strtrim = function(s, chars)
        local c = chars and ("[" .. chars:gsub("%p", "%%%0") .. "]") or "%s"
        return (s:gsub("^" .. c .. "+", ""):gsub(c .. "+$", ""))
    end
    env.strsplit = function(sep, s, limit)
        local out, pos = {}, 1
        while true do
            if limit and #out == limit - 1 then out[#out + 1] = s:sub(pos) break end
            local a, b = s:find(sep, pos, true)
            if not a then out[#out + 1] = s:sub(pos) break end
            out[#out + 1] = s:sub(pos, a - 1)
            pos = b + 1
        end
        return unpack(out)
    end
    env.strjoin = function(sep, ...) return table.concat({ ... }, sep) end
    env.date = os.date
end

-- Frames ----------------------------------------------------------------------------------------
local function FrameFactory(w)
    local meta = {}
    local methods = {}

    meta.__index = function(f, k)
        local v = methods[k]
        if v then return v end
        -- Nur Blizzard-Methoden (Großbuchstabe vorn) werden erfunden; eigene Felder des Addons bleiben nil
        if type(k) ~= "string" or not k:match("^[A-Z]") then return nil end
        if k:match("^Create") then
            return function(self) return w:NewFrame(k:sub(7), nil, self) end
        end
        -- Get…Texture, Get…FontString, GetScrollChild …: immer dasselbe Unterobjekt
        if k:match("^Get.*Texture$") or k:match("^Get.*FontString$") or k:match("^GetScrollChild$")
            or k:match("^Get.*Object$") or k:match("^Get.*Button$") or k:match("^Get.*Frame$") then
            return function(self)
                local sub = rawget(self, "_" .. k)
                if not sub then
                    sub = w:NewFrame("Region", nil, self)
                    rawset(self, "_" .. k, sub)
                end
                return sub
            end
        end
        if k:match("Width$") or k:match("Height$") then return function() return 100 end end
        if k:match("Scale$") or k:match("Alpha$") or k:match("Level$") then return function() return 1 end end
        if k:match("^GetNum") then return function() return 0 end end
        if k:match("^Is") or k:match("^Has") then return function() return false end end
        return function() return nil end
    end

    function methods:RegisterEvent(e)
        w.registered[e] = w.registered[e] or {}
        w.registered[e][self] = true
    end
    function methods:UnregisterEvent(e)
        if w.registered[e] then w.registered[e][self] = nil end
    end
    function methods:UnregisterAllEvents()
        for _, set in pairs(w.registered) do set[self] = nil end
    end
    function methods:SetScript(s, fn)
        rawset(self, "_on" .. s, fn)
        if s == "OnUpdate" and fn then w.updating[self] = true end
    end
    function methods:GetScript(s) return rawget(self, "_on" .. s) end
    function methods:HookScript(s, fn)
        local old = rawget(self, "_on" .. s)
        rawset(self, "_on" .. s, function(...)
            if old then old(...) end
            fn(...)
        end)
        if s == "OnUpdate" then w.updating[self] = true end
    end
    function methods:Show()
        if not rawget(self, "_shown") then
            rawset(self, "_shown", true)
            if rawget(self, "_name") then w:record("window", rawget(self, "_name")) end
            local h = rawget(self, "_onOnShow")
            if h then w:call(h, self) end
        end
    end
    function methods:Hide()
        if rawget(self, "_shown") then
            rawset(self, "_shown", false)
            local h = rawget(self, "_onOnHide")
            if h then w:call(h, self) end
        end
    end
    function methods:SetShown(v) if v then self:Show() else self:Hide() end end
    function methods:IsShown() return rawget(self, "_shown") and true or false end
    function methods:IsVisible()
        local f = self
        while f do
            if not rawget(f, "_shown") then return false end
            f = rawget(f, "_parent")
        end
        return true
    end
    function methods:GetName() return rawget(self, "_name") end
    function methods:GetParent() return rawget(self, "_parent") end
    function methods:SetParent(p) rawset(self, "_parent", p) end
    function methods:GetText() return rawget(self, "_text") end
    function methods:SetText(t) rawset(self, "_text", t) end
    function methods:SetFormattedText(fmt, ...) rawset(self, "_text", fmt:format(...)) end
    function methods:GetObjectType() return rawget(self, "_kind") end
    function methods:IsObjectType(t) return rawget(self, "_kind") == t end
    function methods:GetChecked() return rawget(self, "_checked") or false end
    function methods:SetChecked(v) rawset(self, "_checked", v and true or false) end
    function methods:GetValue() return rawget(self, "_value") or 0 end
    function methods:SetValue(v) rawset(self, "_value", v) end
    function methods:GetMinMaxValues() return 0, 100 end
    function methods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function methods:GetCenter() return 500, 400 end
    function methods:GetLeft() return 400 end
    function methods:GetRight() return 600 end
    function methods:GetTop() return 500 end
    function methods:GetBottom() return 300 end
    function methods:GetRect() return 400, 300, 200, 200 end
    function methods:GetSize() return 100, 100 end
    function methods:GetVerticalScroll() return 0 end
    function methods:GetVerticalScrollRange() return 0 end
    function methods:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function methods:GetTextColor() return 1, 1, 1, 1 end
    function methods:GetCursorPosition() return 0 end
    function methods:GetNumLetters() return #(rawget(self, "_text") or "") end
    function methods:GetChildren() end
    function methods:GetRegions() end
    function methods:GetID() return rawget(self, "_id") or 0 end
    function methods:SetID(id) rawset(self, "_id", id) end
    function methods:Click(...)
        local h = rawget(self, "_onOnClick")
        if h then w:call(h, self, ...) end
    end

    return meta
end

function M.new(opts)
    opts = opts or {}
    local w = {
        now = 1000, clock0 = 1794000000, timers = {}, registered = {}, log = {}, errors = {},
        filters = {}, frames = {}, updating = {}, opts = opts, seed = 12345,
    }

    -- Zufall: reproduzierbar
    local function random(a, b)
        w.seed = (w.seed * 1103515245 + 12345) % 2147483648
        local r = w.seed / 2147483648
        if not a then return r end
        if not b then a, b = 1, a end
        return a + math.floor(r * (b - a + 1))
    end

    function w:record(kind, ...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        table.insert(self.log, { kind = kind, text = table.concat(parts, " "), at = self.now })
    end

    -- Jeder Aufruf ins Addon läuft geschützt; Fehler landen in w.errors statt den Test abzubrechen
    function w:call(fn, ...)
        local args, n = { ... }, select("#", ...)
        local ok, err = xpcall(function() return fn(unpack(args, 1, n)) end, debug.traceback)
        if not ok then table.insert(self.errors, err) end
        return ok
    end

    local frameMeta = FrameFactory(w)
    function w:NewFrame(kind, name, parent)
        local f = setmetatable({ _kind = kind, _name = name, _parent = parent, _shown = true }, frameMeta)
        -- Frames mit Namen sind Fenster: anfangs versteckt, Zeigen wird aufgezeichnet
        if name and kind == "Frame" then rawset(f, "_shown", false) end
        if name then self.env[name] = f end
        table.insert(self.frames, f)
        return f
    end

    -- Zeit ----------------------------------------------------------------------------------------
    local function addTimer(delay, fn, every, iterations)
        local t = { at = w.now + math.max(delay or 0, 0), fn = fn, every = every, left = iterations }
        function t:Cancel() self.cancelled = true end
        function t:IsCancelled() return self.cancelled or false end
        table.insert(w.timers, t)
        return t
    end

    -- Zeit vorspulen: Timer laufen in der richtigen Reihenfolge, sichtbare Frames bekommen OnUpdate
    function w:advance(seconds)
        local target = self.now + seconds
        local nextUpdate = self.now
        while true do
            table.sort(self.timers, function(a, b) return a.at < b.at end)
            local t = self.timers[1]
            local tAt = t and t.at or math.huge
            local uAt = nextUpdate + 1
            if math.min(tAt, uAt) > target then break end
            if uAt < tAt then
                self.now = uAt
                nextUpdate = uAt
                for f in pairs(self.updating) do
                    local h = rawget(f, "_onOnUpdate")
                    if h and f:IsVisible() then self:call(h, f, 1) end
                end
            else
                table.remove(self.timers, 1)
                self.now = t.at
                if not t.cancelled then
                    self:call(t.fn, t)
                    if t.every and not t.cancelled then
                        if t.left then t.left = t.left - 1 end
                        if not t.left or t.left > 0 then
                            t.at = self.now + t.every
                            table.insert(self.timers, t)
                        end
                    end
                end
            end
        end
        self.now = target
    end

    -- Events --------------------------------------------------------------------------------------
    function w:fire(event, ...)
        for f in pairs(self.registered[event] or {}) do
            local h = rawget(f, "_onOnEvent")
            if h then self:call(h, f, event, ...) end
        end
    end

    -- Chatzeile durch die Filter des Addons schicken, wie es das Chatfenster tut.
    -- Liefert den angezeigten Text oder nil, wenn die Zeile verschluckt wird.
    function w:chatLine(event, msg, sender, ...)
        local args = { msg, sender, ... }
        for _, fn in ipairs(self.filters[event] or {}) do
            local res
            self:call(function() res = { fn(nil, event, unpack(args)) } end)
            if res and res[1] then return nil end
            if res and res[2] ~= nil then
                for i = 2, #res do args[i - 1] = res[i] end
            end
        end
        return args[1]
    end

    -- Addon-Nachricht von einem anderen Spieler empfangen
    function w:receive(msg, channel, sender)
        self:fire("CHAT_MSG_ADDON", "ElternRaid", msg, channel or "GUILD", sender)
    end

    -- Slash-Befehl eingeben, z. B. w:slash("/ea quiz")
    function w:slash(line)
        local cmd, rest = line:match("^(%S+)%s*(.*)$")
        for key, fn in pairs(self.env.SlashCmdList) do
            for i = 1, 9 do
                local alias = rawget(self.env, "SLASH_" .. key .. i)
                if not alias then break end
                if alias:lower() == cmd:lower() then return self:call(fn, rest) end
            end
        end
        error("unbekannter Befehl: " .. cmd)
    end

    -- Aufzeichnung lesen --------------------------------------------------------------------------
    function w:clear() self.log = {} end
    function w:entries(kind)
        local out = {}
        for _, e in ipairs(self.log) do
            if not kind or e.kind == kind then out[#out + 1] = e.text end
        end
        return out
    end
    function w:find(kind, pattern)
        for _, e in ipairs(self.log) do
            if e.kind == kind and e.text:find(pattern) then return e.text end
        end
    end
    function w:dump()
        for _, e in ipairs(self.log) do print(string.format("  %7.1fs  %-7s %s", e.at - 1000, e.kind, e.text)) end
    end

    -- Die Spielwelt -------------------------------------------------------------------------------
    local env = {}
    w.env = env
    w.unknown = {}
    setmetatable(env, { __index = function(t, k)
        if type(k) ~= "string" then return nil end
        -- Eigene globale Namen des Addons (gespeicherte Variablen, Frames) gibt es erst, wenn das Addon sie anlegt
        if k:match("^Elternabend") then return nil end
        -- Blizzards Textkonstanten (ERR_…, SOUNDKIT …) als erkennbare Platzhalter
        if k:match("^[A-Z][A-Z0-9_]+$") then return k .. " %s" end
        w.unknown[k] = true
        local m = Mock()
        rawset(t, k, m)
        return m
    end })
    env._G = env
    LuaBuiltins(env, random)

    local me = { name = opts.name or "Anna", surname = opts.surname or "Sturmwind" }
    w.me = me

    -- gespeicherte Variablen
    env.ElternabendDB = opts.db
    env.ElternabendSync = nil
    env.ElternabendAbgleich = nil

    env.print = function(...) w:record("print", ...) end
    env.geterrorhandler = function() return function(err) table.insert(w.errors, tostring(err)) end end
    env.seterrorhandler = function() end
    env.GetTime = function() return w.now end
    env.time = function() return math.floor(w.now) + w.clock0 end
    env.date = function(fmt, t) return os.date(fmt, t or env.time()) end
    env.GetServerTime = env.time
    env.debugprofilestop = function() return w.now * 1000 end
    env.GetBuildInfo = function() return "1.16.1", "1", "Nov 2026", 16001 end
    env.issecretvalue = nil
    env.C_Timer = {
        After = function(d, fn) addTimer(d, fn) end,
        NewTimer = function(d, fn) return addTimer(d, fn) end,
        NewTicker = function(d, fn, n) return addTimer(d, fn, d, n) end,
    }
    env.PlaySound = function(id) w:record("sound", id) end
    env.PlaySoundFile = function(id) w:record("sound", id) end
    env.SOUNDKIT = setmetatable({}, { __index = function(_, k) return k end })
    env.CreateFrame = function(kind, name, parent) return w:NewFrame(kind, name, parent) end
    env.CreateFont = function(name) return w:NewFrame("Font", name) end
    env.CreateColor = function() return w:NewFrame("Color") end
    env.hooksecurefunc = function() end
    env.SlashCmdList = {}
    env.UISpecialFrames = {}
    env.Constants = {}
    env.Enum = setmetatable({}, { __index = function(t, k)
        local v = setmetatable({}, { __index = function(_, kk) return kk end })
        rawset(t, k, v)
        return v
    end })
    env.UIParent = w:NewFrame("Frame")
    env.Minimap = w:NewFrame("Frame")
    env.GameTooltip = w:NewFrame("GameTooltip")
    env.ItemRefTooltip = w:NewFrame("GameTooltip")
    env.RaidWarningFrame = w:NewFrame("Frame")
    env.RaidNotice_AddMessage = function(_, text) w:record("screen", text) end
    env.StaticPopupDialogs = {}
    env.StaticPopup_Show = function(which) w:record("popup", which) end
    env.ChatFrame_AddMessageEventFilter = function(event, fn)
        w.filters[event] = w.filters[event] or {}
        table.insert(w.filters[event], fn)
    end
    env.ChatFrameUtil = nil
    env.C_AddOns = { GetAddOnMetadata = function(_, key) return key == "Version" and w.version or nil end }
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, msg, channel, target)
            w:record("comm", channel .. (target and (" " .. target) or ""), (msg:gsub("\t", " ")))
            return true
        end,
        SendChatMessage = function(msg, channel, _, target)
            w:record("chat", channel .. (target and (" " .. tostring(target)) or ""), msg)
        end,
        InChatMessagingLockdown = function() return false end,
    }
    env.SendChatMessage = env.C_ChatInfo.SendChatMessage

    -- Spieler, Gruppe, Gilde
    -- Gruppe: opts.party = { "Beta Lux", … } (party1 …), opts.groupLeader = Name der Leitung
    env.UnitName = function(u)
        if u == "player" then return me.name, me.surname end
        local i = type(u) == "string" and tonumber(u:match("^party(%d)$"))
        local full = i and opts.party and opts.party[i]
        if full then return full:match("^(%S+)%s*(.-)$") end
    end
    env.UnitFullName = env.UnitName
    env.UnitGUID = function(u) if u == "player" then return "Player-1-00000001" end end
    env.UnitClass = function(u) if u == "player" then return "Paladin", "PALADIN", 2 end end
    env.UnitLevel = function() return 60 end
    env.UnitExists = function(u)
        if u == "player" then return true end
        local i = type(u) == "string" and tonumber(u:match("^party(%d)$"))
        if i and opts.party then return opts.party[i] ~= nil end
        return (opts.group and u == "party1") or false
    end
    env.UnitIsGroupLeader = function(u)
        if u == "player" then return opts.leader or false end
        local name, surname = env.UnitName(u)
        return name ~= nil and opts.groupLeader == (surname ~= "" and (name .. " " .. surname) or name)
    end
    env.UnitIsGroupAssistant = function() return false end
    env.UnitInRaid = function() return nil end
    env.UnitAffectingCombat = function() return false end
    env.InCombatLockdown = function() return false end
    env.GetRealmName = function() return "Forever" end
    env.GetNormalizedRealmName = env.GetRealmName
    env.IsInGroup = function() return opts.group or opts.raid or false end
    env.IsInRaid = function() return opts.raid or false end
    env.GetNumGroupMembers = function() return (opts.raid and 10) or (opts.group and 5) or 0 end
    env.IsInInstance = function() return false, "none" end
    env.GetInstanceInfo = function() return "Elwynn", "none", 0 end
    env.IsInGuild = function() return opts.guild ~= nil end
    env.GetGuildInfo = function(u) if u == "player" and opts.guild then return opts.guild, "Mitglied", 4 end end
    env.CanGuildInvite = function() return opts.canInvite or false end
    env.CanEditOfficerNote = function() return opts.officer or false end
    env.CanViewOfficerNote = function() return opts.officer or false end
    env.GetNumGuildMembers = function() return #(opts.roster or {}), #(opts.roster or {}) end
    env.GetGuildRosterInfo = function(i)
        local m = (opts.roster or {})[i]
        if not m then return nil end
        return m.name, m.rank or "Mitglied", m.rankIndex or 4, m.level or 60, m.class or "Krieger", "Elwynn", "",
            m.officerNote or "", m.online or false, 0, m.classFile or "WARRIOR"
    end
    env.C_GuildInfo = {
        GuildRoster = function() w:fire("GUILD_ROSTER_UPDATE") end,
        CanViewOfficerNote = function() return opts.officer or false end,
        MemberExistsByName = function(name)
            for _, m in ipairs(opts.roster or {}) do if m.name == name then return true end end
            return false
        end,
    }
    -- Texte des deutschen Clients, an denen das Addon Meldungen erkennt
    env.ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h ist jetzt online."
    env.RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { colorStr = "ffffffff", r = 1, g = 1, b = 1 } end })
    env.GetGuildRosterMOTD = function() return opts.motd or "" end
    env.GetItemInfo = function() return nil end
    env.C_Item = { GetItemInfo = function() return nil end, GetItemInfoInstant = function() return nil end }

    w.version = opts.version or "dev"
    return w
end

-- Das Addon in eine Welt laden: Dateien in der Reihenfolge der .toc, ein gemeinsamer Namensraum
-- Übersetzte Dateien werden zwischengespeichert: Jede Welt führt sie mit eigener Umgebung neu aus
local compiled = {}
function M.load(w, dir)
    local ns = {}
    for line in io.lines(dir .. "/Elternabend.toc") do
        local file = line:match("^%s*([^#%s][^%s]*%.lua)%s*$")
        if file then
            local path = dir .. "/" .. file
            local chunk, err = compiled[path], nil
            if not chunk then
                chunk, err = loadfile(path)
                compiled[path] = chunk
            end
            if not chunk then
                table.insert(w.errors, err)
            else
                setfenv(chunk, w.env)
                w:call(chunk, "Elternabend", ns)
            end
        end
    end
    w.ns = ns
    return ns
end

-- Kurzform: Welt bauen, Addon laden, wie beim Einloggen starten
function M.login(dir, opts)
    local w = M.new(opts)
    M.load(w, dir)
    w:fire("ADDON_LOADED", "Elternabend")
    w:fire("PLAYER_LOGIN")
    w:fire("PLAYER_ENTERING_WORLD", true, false)
    if opts and opts.guild then w:fire("GUILD_ROSTER_UPDATE") end
    return w
end

return M
