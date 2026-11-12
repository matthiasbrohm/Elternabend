-- Elternabend: Kalender
--
-- Zeigt in einer Monatsansicht:
--   * Raidtermine aus dem Raidplaner der Webseite (ein Offizier fügt sie ein, das Addon
--     verteilt sie an alle in der Gilde – wie bei der Pinnwand ohne eigenen Server)
--   * Ereignisse aus Blizzards Ingame-Kalender: Dunkelmond-Jahrmarkt, „Zu den Waffen“
--     (PvP-Bonus auf einem Schlachtfeld), sonstige Feiertage, Gildenereignisse
--
-- Nachrichten:
--   CALR  <Termine>   alle Raidtermine (SendLarge, GUILD) – nur von Offizieren eingefügte werden angenommen
--   CALQ  <Version>   „Welchen Stand habt ihr?“ beim Einloggen
--
-- Format der Termine (auch der Export aus dem Raidplaner):
--   EART1^<Exportzeit>[^<von>]
--   R^<id>^<Name>^<Start>^<Dauer Min>^<Zusagen>^<Plätze>^<Status>
local _, ns = ...

local Cal = { cache = {} } -- cache: JJJJMM -> { days, soft }
ns.Calendar = Cal

Cal.KINDS = {
    raid = { label = "Raids", color = "goldBright" },
    dmf = { label = "Dunkelmond-Jahrmarkt", color = "purple" },
    pvp = { label = "Zu den Waffen (PvP)", color = "red" },
    guild = { label = "Gildenkalender", color = "green" },
    other = { label = "Weitere Feiertage", color = "muted" },
}
Cal.ORDER = { "raid", "dmf", "pvp", "guild", "other" }

local function DB() return ns.db.calendar end

-- Raidtermine -------------------------------------------------------------------------
local function Clean(s)
    return (tostring(s or ""):gsub("[%^~\r\n\t|]", " "))
end

function Cal:Parse(text)
    text = tostring(text or ""):gsub("\r", "")
    local lines = {}
    for line in text:gmatch("[^\n~]+") do table.insert(lines, strtrim(line)) end
    local head = lines[1] and { strsplit("^", lines[1]) } or {}
    if head[1] ~= "EART1" then return nil, "Das ist kein Terminexport aus dem Raidplaner (er beginnt mit EART1)." end
    local data = { version = tonumber(head[2]) or 0, from = head[3] or "", list = {} }
    for i = 2, #lines do
        local f = { strsplit("^", lines[i]) }
        if f[1] == "R" and f[2] and tonumber(f[4]) then
            table.insert(data.list, {
                id = f[2], name = Clean(f[3]):sub(1, 60), start = tonumber(f[4]), dur = tonumber(f[5]) or 120,
                yes = tonumber(f[6]) or 0, slots = tonumber(f[7]) or 0, status = f[8] or "offen",
            })
        end
        if #data.list >= 60 then break end
    end
    table.sort(data.list, function(a, b) return a.start < b.start end)
    return data
end

function Cal:Serialize(data)
    local lines = { table.concat({ "EART1", data.version, Clean(data.from) }, "^") }
    for _, r in ipairs(data.list) do
        table.insert(lines, table.concat({ "R", r.id, Clean(r.name), r.start, r.dur, r.yes, r.slots, r.status }, "^"))
    end
    return table.concat(lines, "~") -- „~“ statt Zeilenumbruch, wie bei der Pinnwand
end

-- Raidtermine der Gilde – ein Charakter ohne Gilde oder in einer anderen Gilde sieht sie nicht
function Cal:Raids()
    if not ns.Info:AtHome() then return {} end
    return DB().raids.list
end

-- Offizier fügt den Export aus dem Raidplaner ein
-- onlyIfChanged: nichts tun (und nichts verteilen), wenn die Termine schon genau so da sind –
-- für den Raid-Text, der die Termine bei jedem Einfügen mitbringt
local function Signature(list)
    local parts = {}
    for _, r in ipairs(list or {}) do
        table.insert(parts, table.concat({ r.id, r.name, r.start, r.dur, r.yes, r.slots, r.status }, "^"))
    end
    return table.concat(parts, "~")
end

function Cal:Import(text, onlyIfChanged)
    if not ns.Board:AmOfficer() then return false, "Raidtermine einfügen dürfen nur Offiziere." end
    local data, err = self:Parse(text)
    if not data then return false, err end
    if onlyIfChanged and Signature(data.list) == Signature(DB().raids.list) then return true, #data.list, false end
    data.from = ns.UnitFullName("player") or ""
    data.version = math.max(data.version, (DB().raids.version or 0) + 1)
    DB().raids = data
    self:Broadcast()
    ns:Fire("CALENDAR_UPDATE")
    return true, #data.list, true
end

function Cal:Broadcast()
    if not ns.Info:AtHome() then return end
    local payload = self:Serialize(DB().raids)
    ns.WhenChatFree(function() ns.Comm:SendLarge("CALR", payload, "GUILD") end)
end

-- Angenommen werden Termine, die ein Offizier eingefügt hat – auch wenn sie ein anderes
-- Mitglied weiterreicht (Antwort auf CALQ beim Einloggen)
function Cal:Receive(sender, text)
    if not ns.Info:AtHome() then return end
    local data = self:Parse(text)
    if not data or data.version <= (DB().raids.version or 0) then return end
    if not (ns.Board:IsOfficer(data.from ~= "" and data.from or sender) or ns.Board:IsOfficer(sender)) then return end
    DB().raids = data
    self.answerPending = nil -- jemand anderes hat schon geantwortet
    ns:Fire("CALENDAR_UPDATE")
end

ns.Comm.handlers.CALR = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if not data then return end
    if #ns.Members.list == 0 then
        Cal.waiting = { sender, data } -- Rechte erst prüfen, wenn die Gildenliste da ist
        return
    end
    Cal:Receive(sender, data)
end

ns.Comm.handlers.CALQ = function(_, parts)
    if not ns.Info:AtHome() then return end
    local theirs = tonumber(parts[2]) or 0
    local mine = DB().raids.version or 0
    if mine <= theirs or #DB().raids.list == 0 then return end
    -- Zufällig warten; kommt in der Zeit ein neuerer Stand von jemand anderem, entfällt die Antwort
    Cal.answerPending = true
    C_Timer.After(2 + math.random() * 6, function()
        if not Cal.answerPending then return end
        Cal.answerPending = nil
        Cal:Broadcast()
    end)
end

ns:Listen("MEMBERS_UPDATE", function()
    if Cal.waiting and #ns.Members.list > 0 then
        local w = Cal.waiting
        Cal.waiting = nil
        Cal:Receive(w[1], w[2])
    end
end)

-- Blizzard-Kalender ---------------------------------------------------------------------
local function Kind(e)
    if e.calendarType == "HOLIDAY" then
        local t = e.title or ""
        if t:find("Dunkelmond", 1, true) or t:find("Darkmoon", 1, true) then return "dmf" end
        if t:find("^Zu den Waffen") or t:find("^Call to Arms") then return "pvp" end
        return "other"
    end
    if e.calendarType == "GUILD_EVENT" or e.calendarType == "GUILD_ANNOUNCEMENT"
        or e.calendarType == "PLAYER" or e.calendarType == "COMMUNITY_EVENT" then
        return "guild"
    end
    return nil -- Raid-Sperren, Resets usw. nicht anzeigen
end

local function ToTime(ct)
    if not ct or not ct.year then return nil end
    return time({ year = ct.year, month = ct.month, day = ct.monthDay, hour = ct.hour or 0, min = ct.minute or 0 })
end

function Cal:Available()
    return C_Calendar and C_Calendar.GetNumDayEvents and C_Calendar.GetMonthInfo and true or false
end

function Cal:Open()
    if self.opened or not self:Available() then return end
    self.opened = true
    C_Calendar.OpenCalendar()
end

-- Blizzards Kalender hält nur den eingestellten Monat und seine Nachbarn bereit (Abstand -1..1).
-- Gelesene Monate kommen in den Zwischenspeicher; „soft“ heißt: nur als Nachbarmonat gelesen,
-- vielleicht unvollständig. Den Monat umstellen darf nur die Kalenderansicht (sonst würden
-- Startseite und Kalender den Monat ständig hin- und herschalten).
-- Beschreibung eines Feiertags (z. B. wo der Jahrmarkt steht); je Ereignis nur einmal lesen
local textCache = {}
local function HolidayText(offset, day, index, ev)
    if ev.calType ~= "HOLIDAY" or not C_Calendar.GetHolidayInfo then return nil end
    local key = ev.title .. (ev.start or 0)
    if textCache[key] == nil then
        local info = C_Calendar.GetHolidayInfo(offset, day, index)
        local text = info and info.description
        textCache[key] = type(text) == "string" and text ~= ""
            and (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) or false
    end
    return textCache[key] or nil
end

local function ReadOffset(offset)
    local info = C_Calendar.GetMonthInfo(offset)
    if not info or not info.year then return nil end
    local days = {}
    for d = 1, (info.numDays or 31) do
        for i = 1, (C_Calendar.GetNumDayEvents(offset, d) or 0) do
            local e = C_Calendar.GetDayEvent(offset, d, i)
            local kind = e and Kind(e)
            if kind then
                days[d] = days[d] or {}
                local ev = {
                    kind = kind, title = e.title or "", icon = e.iconTexture,
                    start = ToTime(e.startTime), finish = ToTime(e.endTime),
                    calType = e.calendarType,
                }
                ev.text = HolidayText(offset, d, i, ev)
                table.insert(days[d], ev)
            end
        end
    end
    return info.year * 100 + info.month, days
end

function Cal:Load()
    if not self:Available() then return end
    for _, offset in ipairs({ 0, -1, 1 }) do
        local key, days = ReadOffset(offset)
        if key then
            local old = self.cache[key]
            if offset == 0 or not old or old.soft then
                self.cache[key] = { days = days, soft = offset ~= 0 }
            end
        end
    end
end

-- Ereignisse eines Monats: Tag -> Liste { kind, title, icon, start, finish, text, … }
-- switch = true: Monat bei Blizzard einstellen, wenn er noch nicht (vollständig) gelesen ist
function Cal:BlizzardMonth(year, month, switch)
    if not self:Available() then return {} end
    self:Open()
    local key = year * 100 + month
    local c = self.cache[key]
    if not c or c.soft then
        self:Load() -- vielleicht hat Blizzard den Monat schon
        c = self.cache[key]
    end
    if switch and (not c or c.soft) and C_Calendar.SetAbsMonth
        and not (CalendarFrame and CalendarFrame:IsShown()) and self.requested ~= key then
        self.requested = key -- nur einmal anfragen, die Antwort kommt mit CALENDAR_UPDATE_EVENT_LIST
        C_Calendar.SetAbsMonth(month, year)
        self:Load()
        c = self.cache[key]
    end
    return c and c.days or {}
end

-- Wo steht der Jahrmarkt? Aus dem Beschreibungstext
local PLACES = {
    { "Elwynn", "Wald von Elwynn (bei Goldhain)" },
    { "Goldhain", "Wald von Elwynn (bei Goldhain)" },
    { "Mulgore", "Mulgore (bei Donnerfels)" },
    { "Terokkar", "Wald von Terokkar" },
    { "Dunkelmond%-Insel", "Dunkelmond-Insel" },
}
function Cal:Place(text)
    if not text then return nil end
    for _, p in ipairs(PLACES) do
        if text:find(p[1]) then return p[2] end
    end
end

ns:On("CALENDAR_UPDATE_EVENT_LIST", function()
    Cal.requested = nil
    Cal:Load()
    ns:Fire("CALENDAR_UPDATE")
end)

-- Alles für einen Monat: Tag -> Liste (Raids zuerst)
function Cal:Month(year, month)
    local days = {}
    for d, list in pairs(self:BlizzardMonth(year, month, true)) do
        days[d] = {}
        for _, e in ipairs(list) do table.insert(days[d], e) end
    end
    for _, r in ipairs(self:Raids()) do
        local t = date("*t", r.start)
        if t.year == year and t.month == month then
            days[t.day] = days[t.day] or {}
            table.insert(days[t.day], 1, { kind = "raid", title = r.name, start = r.start, raid = r })
        end
    end
    return days
end

function Cal:Shown(kind)
    return DB().show[kind] ~= false
end

-- Kurzer Name für die Monatsansicht und die Startseite
function Cal:Short(e)
    if e.kind == "dmf" then return "Jahrmarkt" end
    if e.kind == "pvp" then return (e.title:gsub("^Zu den Waffen: ", "PvP: "):gsub("^Call to Arms: ", "PvP: ")) end
    if e.kind == "raid" then return date("%H:%M", e.start) .. " " .. e.title end
    if e.kind == "guild" and e.start then return date("%H:%M", e.start) .. " " .. e.title end
    return e.title
end

-- Für die Startseite: was läuft gerade (Jahrmarkt, PvP), nächster Raid, nächster Jahrmarkt
-- Liest nur, was schon geladen ist – stellt Blizzards Kalender nie um.
function Cal:Summary()
    local now = time()
    local today = date("*t", now)
    local running, seen = {}, {}
    for _, e in ipairs(self:BlizzardMonth(today.year, today.month)[today.day] or {}) do
        if (e.kind == "dmf" or e.kind == "pvp") and not seen[e.title] then
            seen[e.title] = true
            table.insert(running, self:Short(e) .. (e.finish and (" bis " .. date("%d.%m.", e.finish)) or ""))
        end
    end
    local nextRaid
    for _, r in ipairs(self:Raids()) do
        if r.start + (r.dur or 120) * 60 > now and r.status ~= "abgesagt" then nextRaid = r break end
    end
    -- Nächster Jahrmarkt (nur wenn gerade keiner ist)
    local nextDmf
    local dmfNow = false
    for _, e in ipairs(self:BlizzardMonth(today.year, today.month)[today.day] or {}) do
        if e.kind == "dmf" then dmfNow = true end
    end
    for m = 0, 2 do
        local y, mo = today.year, today.month + m
        if mo > 12 then y, mo = y + 1, mo - 12 end
        local c = not dmfNow and self.cache[y * 100 + mo]
        for d = 1, 31 do
            for _, e in ipairs(c and c.days[d] or {}) do
                if e.kind == "dmf" and e.start and e.start > now and (not nextDmf or e.start < nextDmf) then nextDmf = e.start end
            end
        end
    end
    return running, nextRaid, nextDmf
end

-- Aufräumen und Start --------------------------------------------------------------------
ns:Listen("INIT", function()
    local keep = {}
    for _, r in ipairs(DB().raids.list or {}) do
        if r.start > time() - 2 * 86400 then table.insert(keep, r) end
    end
    DB().raids.list = keep
end)

ns:On("PLAYER_LOGIN", function()
    C_Timer.After(30 + math.random() * 15, function()
        if ns.Info:AtHome() then ns.Comm:Send("CALQ", tostring(DB().raids.version or 0), "GUILD") end
    end)
end)
