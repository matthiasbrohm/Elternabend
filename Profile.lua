-- Elternabend: Spielzeiten und „Erste Schritte“
--
-- Jeder kann hinterlegen, wann er meist spielt (Wochentag × Tageszeit, dazu eine kurze Notiz). Die Addons
-- reichen das in der Gilde weiter – so sieht man im Reiter „Gilde“, wer zur selben Zeit online ist.
-- Dazu eine kleine Liste für Neue („Erste Schritte“); ihr Stand reist mit, damit die Gildenleitung sieht,
-- wem sie noch helfen kann.
--
-- Eigene Angaben (accountweit):  ns.db.me = { times, note, done = { discord, raid }, t }
-- Bekannte Angaben aller:        ns.db.profiles[Schlüssel] = { name, t, times, steps, note }
--   times  sieben Hex-Ziffern, Montag bis Sonntag; je Tag Bits 1 Vormittag, 2 Nachmittag, 4 Abend, 8 Spät
--   steps  Bitmaske der erledigten Schritte (Reihenfolge wie in Profile.STEPS)
--   wish   Raidwunsch: 1 ja, gern · 2 ab und zu · 3 eher nicht (0 = keine Angabe, nil = altes Addon)
--   raid   vierzehn Hex-Ziffern, je Tag zwei: Bits für die Startzeiten in Profile.RAID_TIMES
--   roles  Bitmaske 1 Tank, 2 Heiler, 4 DD
-- Nachrichten: PRF (eigener Stand), PRQ (wer hat Neueres als ich?), PRA (alles Bekannte, in Stücken)
local _, ns = ...

local Profile = {}
ns.Profile = Profile

Profile.DAYS = { "Mo", "Di", "Mi", "Do", "Fr", "Sa", "So" }
Profile.SLOTS = {
    { bit = 1, label = "Vormittag", short = "vormittags", hint = "bis 12 Uhr" },
    { bit = 2, label = "Nachmittag", short = "nachmittags", hint = "12–18 Uhr" },
    { bit = 4, label = "Abend", short = "abends", hint = "18–21 Uhr" },
    { bit = 8, label = "Spät", short = "spät", hint = "ab 21 Uhr" },
}
local NOTE_MAX = 60

local function Me()
    ns.db.me = ns.db.me or {}
    ns.db.me.done = ns.db.me.done or {}
    return ns.db.me
end
Profile.Me = Me

local function All()
    ns.db.profiles = ns.db.profiles or {}
    return ns.db.profiles
end

local function HasBit(value, bit)
    return math.floor(value / bit) % 2 == 1
end

-- Spielzeiten ---------------------------------------------------------------------------------
-- "0c0c00f" → { 0, 12, 0, 12, 0, 0, 15 }; nil, wenn ungültig oder nichts angekreuzt
function Profile.Parse(times)
    if type(times) ~= "string" or not times:match("^%x%x%x%x%x%x%x$") then return nil end
    local days, any = {}, false
    for i = 1, 7 do
        days[i] = tonumber(times:sub(i, i), 16)
        if days[i] > 0 then any = true end
    end
    return any and days or nil
end

function Profile.Pack(days)
    local out = {}
    for i = 1, 7 do out[i] = string.format("%x", (days[i] or 0) % 16) end
    return table.concat(out)
end

-- Was zwei Spieler gemeinsam haben: Anzahl der Zeitfenster und die gemeinsamen Zeiten (gepackt)
function Profile.Common(a, b)
    local da, db = Profile.Parse(a), Profile.Parse(b)
    if not da or not db then return 0, nil end
    local both, count = {}, 0
    for i = 1, 7 do
        both[i] = 0
        for _, slot in ipairs(Profile.SLOTS) do
            if HasBit(da[i], slot.bit) and HasBit(db[i], slot.bit) then
                both[i] = both[i] + slot.bit
                count = count + 1
            end
        end
    end
    return count, count > 0 and Profile.Pack(both) or nil
end

-- „abends Mo, Di, Do · spät Fr, Sa“
function Profile.TimesText(times)
    local days = Profile.Parse(times)
    if not days then return "" end
    local parts = {}
    for _, slot in ipairs(Profile.SLOTS) do
        local names, n = {}, 0
        for i = 1, 7 do
            if HasBit(days[i], slot.bit) then
                table.insert(names, Profile.DAYS[i])
                n = n + 1
            end
        end
        if n > 0 then
            local list = table.concat(names, ", ")
            if n == 7 then
                list = "täglich"
            elseif list == "Mo, Di, Mi, Do, Fr" then
                list = "Mo–Fr"
            elseif list == "Sa, So" then
                list = "am Wochenende"
            end
            table.insert(parts, slot.short .. " " .. list)
        end
    end
    return table.concat(parts, " · ")
end

-- Raidwünsche ---------------------------------------------------------------------------------
-- Wer will raiden, an welchen Tagen, zu welchen Startzeiten, in welcher Rolle? (für die Raidplanung)
Profile.WISHES = {
    { label = "Ja, gern", short = "ja, gern", color = "green" },
    { label = "Ab und zu", short = "ab und zu", color = "goldBright" },
    { label = "Eher nicht", short = "eher nicht", color = "muted" },
}
-- Startzeiten (ein Raid dauert etwa zwei Stunden); bei Bedarf einfach hier ändern – höchstens acht
Profile.RAID_TIMES = {
    { label = "9:00", hint = "bis etwa 11 Uhr" },
    { label = "10:00", hint = "bis etwa 12 Uhr" },
    { label = "11:30", hint = "bis etwa 13:30 Uhr" },
    { label = "14:00", hint = "bis etwa 16 Uhr" },
    { label = "17:00", hint = "bis etwa 19 Uhr" },
    { label = "19:00", hint = "bis etwa 21 Uhr" },
    { label = "20:00", hint = "bis etwa 22 Uhr" },
    { label = "21:00", hint = "bis etwa 23 Uhr – unsere übliche Zeit" },
}
for i, t in ipairs(Profile.RAID_TIMES) do t.bit = 2 ^ (i - 1) end
Profile.ROLES = {
    { bit = 1, label = "Tank", plural = "Tanks" },
    { bit = 2, label = "Heiler", plural = "Heiler" },
    { bit = 4, label = "DD", plural = "DD" },
}

-- "000000000000a1" → { 0, 0, 0, 0, 0, 0, 161 }; nil, wenn ungültig oder nichts angekreuzt
function Profile.ParseRaid(raid)
    if type(raid) ~= "string" or not raid:match("^" .. string.rep("%x", 14) .. "$") then return nil end
    local days, any = {}, false
    for i = 1, 7 do
        days[i] = tonumber(raid:sub(i * 2 - 1, i * 2), 16)
        if days[i] > 0 then any = true end
    end
    return any and days or nil
end

function Profile.PackRaid(days)
    local out = {}
    for i = 1, 7 do out[i] = string.format("%02x", (days[i] or 0) % 256) end
    return table.concat(out)
end

local function DayList(names)
    local list = table.concat(names, ", ")
    if #names == 7 then return "täglich" end
    if list == "Mo, Di, Mi, Do, Fr" then return "Mo–Fr" end
    if list == "Sa, So" then return "am Wochenende" end
    return list
end

-- „am Wochenende ab 10:00 · Mo–Fr ab 21:00“
function Profile.RaidText(raid)
    local days = Profile.ParseRaid(raid)
    if not days then return "" end
    local parts = {}
    for _, t in ipairs(Profile.RAID_TIMES) do
        local names = {}
        for i = 1, 7 do
            if HasBit(days[i], t.bit) then table.insert(names, Profile.DAYS[i]) end
        end
        if #names > 0 then table.insert(parts, DayList(names) .. " ab " .. t.label) end
    end
    return table.concat(parts, " · ")
end

function Profile.RolesText(roles)
    local out = {}
    for _, r in ipairs(Profile.ROLES) do
        if HasBit(roles or 0, r.bit) then table.insert(out, r.label) end
    end
    return table.concat(out, "/")
end

-- Ganze Zeile für Tooltips: „ja, gern – Sa, So 10:00 · Heiler/DD“
function Profile.WishText(r)
    local w = r and Profile.WISHES[r.wish or 0]
    if not w then return "" end
    local parts = { w.short }
    if r.wish ~= 3 then
        local when, roles = Profile.RaidText(r.raid), Profile.RolesText(r.roles)
        if when ~= "" then table.insert(parts, when) end
        if roles ~= "" then table.insert(parts, roles) end
    end
    return table.concat(parts, " – ")
end

function Profile:SetRaid(wish, raid, roles)
    local me = Me()
    me.wish = Profile.WISHES[wish or 0] and wish or nil
    me.raid = Profile.ParseRaid(raid) and raid or nil
    me.roles = (tonumber(roles) or 0) % 8
    if me.roles == 0 then me.roles = nil end
    self:Changed()
end

-- Erste Schritte ------------------------------------------------------------------------------
Profile.STEPS = {
    { key = "discord", label = "Dem Discord beitreten", manual = true, button = "Bin drin",
        hint = "Den Link findest du auf der Startseite unter „Discord & Webseite“." },
    { key = "main", label = "Deinen Main festlegen", tab = "mitglieder", button = "Zur Gilde",
        hint = "Reiter Gilde » „Diesen Charakter als Main festlegen“ – dann stehen deine Twinks bei dir." },
    { key = "berufe", label = "Berufe erfassen",
        hint = "Öffne einmal dein Berufsfenster – danach finden dich die anderen als Hersteller." },
    { key = "zeiten", label = "Spielzeiten eintragen", times = true, button = "Eintragen",
        hint = "Wann bist du meist online? So findest du Mitspieler mit denselben Zeiten." },
    { key = "raid", label = "Raidtermine ansehen", manual = true, tab = "kalender", button = "Zum Kalender",
        hint = "Im Kalender stehen die kommenden Raids. Anmelden kannst du dich auf der Webseite oder im Discord." },
}
Profile.ALL_STEPS = 2 ^ #Profile.STEPS - 1

function Profile:StepDone(step)
    local me = Me()
    if step.key == "main" then
        return ns.db.myMain ~= nil
    elseif step.key == "berufe" then
        for _, c in pairs(ns.db.professions or {}) do
            if c.mine and #(c.profs or {}) > 0 then return true end
        end
        return false
    elseif step.key == "zeiten" then
        return Profile.Parse(me.times) ~= nil
    end
    return me.done[step.key] == true
end

function Profile:StepMask()
    local mask = 0
    for i, step in ipairs(self.STEPS) do
        if self:StepDone(step) then mask = mask + 2 ^ (i - 1) end
    end
    return mask
end

-- Was fehlt noch? Liefert die Bezeichnungen der offenen Schritte zu einer Bitmaske.
function Profile.OpenSteps(mask)
    local open = {}
    for i, step in ipairs(Profile.STEPS) do
        if not HasBit(mask or 0, 2 ^ (i - 1)) then table.insert(open, step.label) end
    end
    return open
end

function Profile:MarkDone(key)
    local me = Me()
    if me.done[key] then return end
    me.done[key] = true
    self:Changed()
end

-- Weitergeben -------------------------------------------------------------------------------
local function Clean(s) return (tostring(s or ""):gsub("[%^~\t\r\n|]", " ")) end

local function Encode(r)
    return table.concat({ Clean(r.name), r.t, r.times or "", r.steps or 0, Clean(r.note),
        r.wish or 0, r.raid or "", r.roles or 0 }, "^")
end

local function Decode(text)
    local name, t, times, steps, note, wish, raid, roles = strsplit("^", text or "")
    t = tonumber(t)
    if not name or name == "" or not t then return nil end
    if times ~= "" and not (times or ""):match("^%x%x%x%x%x%x%x$") then times = "" end
    note = strtrim(note or "")
    if #note > NOTE_MAX * 2 then note = "" end
    local r = { name = name, t = t, times = times or "", steps = math.min(tonumber(steps) or 0, Profile.ALL_STEPS), note = note }
    -- Raidwunsch: fehlt bei älteren Addons ganz (dann bleibt wish nil)
    wish = tonumber(wish)
    if wish then
        r.wish = Profile.WISHES[wish] and wish or 0
        r.raid = Profile.ParseRaid(raid) and raid or ""
        r.roles = (tonumber(roles) or 0) % 8
    end
    return r
end

-- Eintrag übernehmen, wenn er neuer ist. Gibt true zurück, wenn sich etwas geändert hat.
function Profile:Accept(r)
    local key = ns.NameKey(r.name)
    if not key or r.t > time() + 86400 then return false end
    local old = All()[key]
    -- Gleich alt, aber mit Raidwunsch (ein älteres Addon hat ihn beim Weitergeben weggelassen): nehmen
    if old and (old.t > r.t or (old.t == r.t and not (r.wish and not old.wish))) then return false end
    All()[key] = r
    return true
end

function Profile:Newest()
    local t = 0
    for _, r in pairs(All()) do
        if r.t > t then t = r.t end
    end
    return t
end

-- Eigenen Stand für diesen Charakter merken und in die Gilde schicken
function Profile:Broadcast()
    local name = ns.UnitFullName("player")
    local key = ns.NameKey(name)
    local me = Me()
    if not key or not me.t then return end
    local r = { name = name, t = me.t, times = me.times or "", steps = self:StepMask(), note = me.note or "",
        wish = me.wish or 0, raid = me.raid or "", roles = me.roles or 0 }
    All()[key] = r
    if IsInGuild() then ns.Comm:Send("PRF", Encode(r), "GUILD") end
end

-- Etwas an den eigenen Angaben hat sich geändert
function Profile:Changed()
    Me().t = time()
    Me().steps = self:StepMask()
    self:Broadcast()
    ns:Fire("PROFILE_UPDATE")
end

function Profile:SetTimes(times, note)
    local me = Me()
    me.times = Profile.Parse(times) and times or nil
    note = strtrim(Clean(note))
    -- nicht mitten in einem Umlaut abschneiden
    if #note > NOTE_MAX then note = (note:sub(1, NOTE_MAX):gsub("[\192-\255][\128-\191]*$", "")) end
    me.note = note ~= "" and note or nil
    self:Changed()
end

-- Schritte, die sich von selbst erledigen (Main, Berufe): Stand nachziehen und melden, wenn er sich
-- geändert hat – oder wenn dieser Charakter den aktuellen Stand noch nicht gemeldet hat
function Profile:CheckSteps()
    local me = Me()
    local mask = self:StepMask()
    if me.steps ~= mask then
        me.steps = mask
        if mask == 0 and not me.t then return end -- noch gar nichts eingetragen: nichts zu melden
        me.t = time()
        self:Broadcast()
        ns:Fire("PROFILE_UPDATE")
        return
    end
    local key = ns.PlayerKey()
    local mine = key and All()[key]
    if me.t and (not mine or mine.t < me.t) then
        self:Broadcast()
        ns:Fire("PROFILE_UPDATE")
    end
end

ns.Comm.handlers.PRF = function(sender, parts)
    local r = Decode(parts[2])
    if not r or not ns.SameName(r.name, sender) then return end
    if Profile:Accept(r) then ns:Fire("PROFILE_UPDATE") end
end

-- Einloggen: Stand vergleichen; wer Neueres hat, schickt alles (zufällig verzögert – kommt in der Zeit
-- schon eine Antwort von jemand anderem, entfällt die eigene)
ns.Comm.handlers.PRQ = function(_, parts)
    local theirs = tonumber(parts[2]) or 0
    if Profile:Newest() <= theirs then return end
    Profile.answer = true
    C_Timer.After(4 + math.random() * 8, function()
        if not Profile.answer then return end
        Profile.answer = nil
        local items = {}
        local M = ns.Members
        for key, r in pairs(All()) do
            -- nur, wer noch in der Gilde ist (solange die Gildenliste bekannt ist)
            if not M or #M.list == 0 or M.byKey[key] then table.insert(items, Encode(r)) end
        end
        if #items > 0 then
            ns.WhenChatFree(function() ns.Comm:SendLarge("PRA", table.concat(items, "~"), "GUILD") end)
        end
    end)
end

ns.Comm.handlers.PRA = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if not data then return end
    Profile.answer = nil
    local changed = false
    for item in data:gmatch("[^~]+") do
        local r = Decode(item)
        -- den eigenen Stand lässt man sich nicht von anderen überschreiben
        if r and not ns.SameName(r.name, ns.PlayerKey()) and Profile:Accept(r) then changed = true end
    end
    if changed then ns:Fire("PROFILE_UPDATE") end
end

-- Auswertung --------------------------------------------------------------------------------
-- Der Stand eines Spielers: der neueste Eintrag über Main und Twinks
function Profile:For(member)
    if not member then return nil end
    local main = member.main or member
    local best
    local function Look(m)
        local r = m and All()[m.key]
        if r and (not best or r.t > best.t) then best = r end
    end
    Look(main)
    for _, t in ipairs(main.twinks or {}) do Look(t) end
    return best
end

local function MyMain()
    local M = ns.Members
    local key = ns.PlayerKey()
    local e = M and key and M.byKey[key]
    return e and (e.main or e) or nil
end

-- Wer spielt zu denselben Zeiten wie ich? { { member, count, common }, … } – meiste Überschneidung zuerst.
-- times: andere Zeiten als die gespeicherten (für die Vorschau beim Ankreuzen)
function Profile:Matches(times)
    local out = {}
    local mine = times or Me().times
    if not Profile.Parse(mine) then return out end
    local self_ = MyMain()
    for _, m in ipairs(ns.Members.mains or {}) do
        if m ~= self_ then
            local r = self:For(m)
            local count, common = Profile.Common(mine, r and r.times)
            if count > 0 then table.insert(out, { member = m, count = count, common = common, note = r.note }) end
        end
    end
    table.sort(out, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.member.name < b.member.name
    end)
    return out
end

-- Wer aus der Gilde spielt wann? out[Tag][Zeitfenster] = { Mitglied, … } (ohne mich), nach Namen sortiert
function Profile:Slots()
    local out = {}
    for d = 1, 7 do
        out[d] = {}
        for s = 1, #Profile.SLOTS do out[d][s] = {} end
    end
    local self_ = MyMain()
    for _, m in ipairs(ns.Members.mains or {}) do
        local r = m ~= self_ and self:For(m)
        local days = r and Profile.Parse(r.times)
        if days then
            for d = 1, 7 do
                for s, slot in ipairs(Profile.SLOTS) do
                    if HasBit(days[d], slot.bit) then table.insert(out[d][s], m) end
                end
            end
        end
    end
    return out
end

-- Raidwünsche der Gilde (mit mir): out[Tag][Startzeit] = { { member, roles, wish }, … } für alle, die
-- raiden wollen (ja oder ab und zu); dazu out.count[Wunsch] und out.roles[Rolle] (nur wer raiden will)
function Profile:RaidSlots()
    local out = { count = { 0, 0, 0 }, roles = { 0, 0, 0 }, people = {} }
    for d = 1, 7 do
        out[d] = {}
        for t = 1, #Profile.RAID_TIMES do out[d][t] = {} end
    end
    local self_ = MyMain()
    for _, m in ipairs(ns.Members.mains or {}) do
        local r = self:For(m)
        if m == self_ then
            local me = Me()
            r = { wish = me.wish, raid = me.raid, roles = me.roles }
        end
        local wish = r and r.wish
        if wish and out.count[wish] then
            out.count[wish] = out.count[wish] + 1
            if wish ~= 3 then
                local e = { member = m, roles = r.roles or 0, wish = wish, raid = r.raid }
                table.insert(out.people, e)
                for i, role in ipairs(Profile.ROLES) do
                    if HasBit(e.roles, role.bit) then out.roles[i] = out.roles[i] + 1 end
                end
                local days = Profile.ParseRaid(r.raid)
                if days then
                    for d = 1, 7 do
                        for t, slot in ipairs(Profile.RAID_TIMES) do
                            if HasBit(days[d], slot.bit) then table.insert(out[d][t], e) end
                        end
                    end
                end
            end
        end
    end
    -- Beliebteste Termine zuerst
    out.best = {}
    for d = 1, 7 do
        for t = 1, #Profile.RAID_TIMES do
            if #out[d][t] > 0 then table.insert(out.best, { day = d, time = t, list = out[d][t] }) end
        end
    end
    table.sort(out.best, function(a, b)
        if #a.list ~= #b.list then return #a.list > #b.list end
        if a.day ~= b.day then return a.day < b.day end
        return a.time < b.time
    end)
    return out
end

-- „3 Tanks, 2 Heiler, 7 DD“ für eine Liste aus RaidSlots
function Profile.RoleCount(list)
    local n = { 0, 0, 0 }
    for _, e in ipairs(list) do
        for i, role in ipairs(Profile.ROLES) do
            if HasBit(e.roles or 0, role.bit) then n[i] = n[i] + 1 end
        end
    end
    local out = {}
    for i, role in ipairs(Profile.ROLES) do
        if n[i] > 0 then table.insert(out, n[i] .. " " .. (n[i] == 1 and role.label or role.plural)) end
    end
    return table.concat(out, ", ")
end

-- Für die Gildenleitung: wer hat bei den ersten Schritten noch etwas offen?
-- Liefert Textzeilen und die Zahl derer, die alles erledigt haben.
function Profile:StepsReport()
    local lines, done, known = {}, 0, {}
    for _, m in ipairs(ns.Members.mains or {}) do
        local r = self:For(m)
        if r then
            known[m.key] = true
            if r.steps >= Profile.ALL_STEPS then
                done = done + 1
            else
                table.insert(lines, ns.ShortName(m.name) .. ": offen – " .. table.concat(Profile.OpenSteps(r.steps), ", "))
            end
        end
    end
    table.sort(lines)
    -- Neue der letzten 30 Tage, von denen noch nichts kam (kein Addon oder eine ältere Version)
    local silent, seen = {}, {}
    local Log = ns.GuildLog
    for _, e in ipairs(Log and Log:Events("join") or {}) do
        if time() - e.t > 30 * 86400 then break end
        local m = ns.Members:Find(e.name)
        local main = m and (m.main or m)
        if main and not known[main.key] and not seen[main.key] then
            seen[main.key] = true
            table.insert(silent, ns.ShortName(main.name) .. " (seit " .. date("%d.%m.", e.t) .. ")")
        end
    end
    table.sort(silent)
    return lines, done, silent
end

ns:Listen("INIT", function()
    C_Timer.After(20, function()
        if not IsInGuild() then return end
        ns.Comm:Send("PRQ", tostring(Profile:Newest()), "GUILD")
        Profile:CheckSteps()
    end)
end)
-- Main festgelegt oder Berufe erfasst: Schritt abhaken
ns:Listen("MEMBERS_UPDATE", function() if Profile.ready then Profile:CheckSteps() end end)
ns:Listen("PROF_UPDATE", function() if Profile.ready then Profile:CheckSteps() end end)
ns:Listen("INIT", function() C_Timer.After(30, function() Profile.ready = true end) end)
