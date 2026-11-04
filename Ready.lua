-- Elternabend: Raid-Vorbereitung und Erinnerung vor dem Raid
--
-- Jedes Addon prüft für den eigenen Charakter: Fläschchen, Essen, Haltbarkeit der
-- Rüstung und fehlende Verzauberungen. Die Raidleitung fragt das mit einem Klick
-- ab (und bei jedem Bereitschaftscheck kommt es von selbst) und sieht es im Raid-Reiter.
--   RDYQ                                 Leitung → Gruppe: bitte melden
--   RDY  Fläschchen Essen Haltbarkeit Fehlende-Verzauberungen
--
-- Erinnerung: Ist ein Raid aus dem Raidplaner geladen, verteilt das Addon dessen
-- Termin in der Gilde. 15 Minuten vorher erinnert es alle mit Addon.
--   RAIDT  ID Termin Titel   (Gilde)
--   RAIDTQ                   (Gilde, beim Einloggen)
local _, ns = ...

local Ready = { states = {} }
ns.Ready = Ready

local REMIND_BEFORE = 15 * 60
local LOW_DURABILITY = 30 -- Prozent: darunter muss repariert werden

-- Diese Plätze sollten verzaubert sein
local ENCHANT_SLOTS = {
    { 15, "Umhang" }, { 5, "Brust" }, { 9, "Handgelenke" }, { 7, "Beine" }, { 8, "Füße" }, { 16, "Waffe" },
}

local FLASK_WORDS = { "fläschchen", "flask", "phiole", "phial", "elixier", "elixir" }
local FOOD_WORDS = { "satt", "well fed", "gut genährt" }

local function HasWord(name, words)
    for _, w in ipairs(words) do
        if name:find(w, 1, true) then return true end
    end
    return false
end

-- Eigener Charakter ---------------------------------------------------------------
function Ready:Collect()
    local r = { flask = false, food = false, durability = 100, missing = {} }
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 60 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            local name = aura.name
            if name and not ns.IsSecret(name) then
                name = ns.Lower(name)
                if HasWord(name, FLASK_WORDS) then r.flask = true end
                if HasWord(name, FOOD_WORDS) then r.food = true end
            end
        end
    end
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 and not ns.IsSecret(cur) then
            r.durability = math.min(r.durability, math.floor(cur / max * 100 + 0.5))
        end
    end
    for _, s in ipairs(ENCHANT_SLOTS) do
        local link = GetInventoryItemLink("player", s[1])
        if link and not ns.IsSecret(link) then
            local enchant = link:match("item:%d+:(%d*)")
            if not enchant or enchant == "" or enchant == "0" then table.insert(r.missing, s[2]) end
        end
    end
    return r
end

function Ready:Serialize(r)
    return table.concat({ r.flask and 1 or 0, r.food and 1 or 0, r.durability, table.concat(r.missing, ",") }, "\t")
end

-- Kurzfassung für die Liste: „alles da“ oder „Fläschchen, Essen“
function Ready.Short(r)
    if not r then return nil end
    local parts = {}
    if not r.flask then table.insert(parts, "Fl") end
    if not r.food then table.insert(parts, "Essen") end
    if r.durability < LOW_DURABILITY then table.insert(parts, "Rep") end
    if #r.missing > 0 then table.insert(parts, "Vz " .. #r.missing) end
    return parts
end

-- Ausführlich für Tooltip und eigene Erinnerung
function Ready.Problems(r)
    local list = {}
    if not r.flask then table.insert(list, "Fläschchen") end
    if not r.food then table.insert(list, "Essen") end
    if r.durability < LOW_DURABILITY then table.insert(list, "Reparieren (" .. r.durability .. " %)") end
    if #r.missing > 0 then table.insert(list, "Verzauberung: " .. table.concat(r.missing, ", ")) end
    return list
end

function Ready:Send(channel, target)
    local r = self:Collect()
    self.states[ns.PlayerKey()] = r
    ns.Comm:Send("RDY", self:Serialize(r), channel, target)
end

function Ready:Get(key)
    return self.states[key]
end

-- Leitung: alle abfragen und nach ein paar Sekunden ansagen, was fehlt
function Ready:Check(announce)
    if not IsInGroup() then
        ns.Print("Du bist in keiner Gruppe.")
        return
    end
    wipe(self.states)
    self.states[ns.PlayerKey()] = self:Collect()
    ns.Comm:Send("RDYQ")
    ns:Fire("READY_UPDATE")
    if announce then C_Timer.After(5, function() Ready:Announce() end) end
end

function Ready:Announce()
    local flask, food, repair, enchant, noAddon = {}, {}, {}, {}, {}
    for _, m in ipairs(ns.Raid.members) do
        local r = self.states[m.key]
        local name = ns.ShortName(m.name)
        if not r then
            if m.online then table.insert(noAddon, name) end
        else
            if not r.flask then table.insert(flask, name) end
            if not r.food then table.insert(food, name) end
            if r.durability < LOW_DURABILITY then table.insert(repair, name) end
            if #r.missing > 0 then table.insert(enchant, name) end
        end
    end
    if #flask + #food + #repair + #enchant == 0 then
        ns.Announce("[Elternabend] Vorbereitung: Alle mit Addon sind startklar!")
    else
        if #flask > 0 then ns.AnnounceList("Fläschchen fehlt: ", flask) end
        if #food > 0 then ns.AnnounceList("Essen fehlt: ", food) end
        if #repair > 0 then ns.AnnounceList("Bitte reparieren: ", repair) end
        if #enchant > 0 then ns.AnnounceList("Verzauberung fehlt: ", enchant) end
    end
    if #noAddon > 0 then ns.Print("Ohne Addon (nicht geprüft): " .. table.concat(noAddon, ", ")) end
end

ns.Comm.handlers.RDYQ = function(sender)
    if not ns.IsTrusted(sender) then return end
    C_Timer.After(math.random() * 2, function() Ready:Send() end)
end

ns.Comm.handlers.RDY = function(sender, parts)
    local m = ns.Raid:Find(sender)
    local key = m and m.key or ns.NameKey(sender)
    if not key then return end
    local missing = {}
    for slot in (parts[5] or ""):gmatch("[^,]+") do table.insert(missing, slot) end
    Ready.states[key] = { flask = parts[2] == "1", food = parts[3] == "1", durability = tonumber(parts[4]) or 100, missing = missing }
    ns:Fire("READY_UPDATE")
end

-- Beim Bereitschaftscheck meldet jedes Addon von selbst
ns:On("READY_CHECK", function()
    wipe(Ready.states)
    C_Timer.After(math.random() * 2, function() Ready:Send() end)
end)
ns:On("GROUP_LEFT", function() wipe(Ready.states) end)

-- Raidtermin und Erinnerung -------------------------------------------------------
-- „2026-12-10 21:00“ oder „10.12.2026 21:00“ → Zeitstempel
function Ready.ParseDate(text)
    if not text then return nil end
    local y, mo, d, h, mi = text:match("(%d%d%d%d)%-(%d%d?)%-(%d%d?)%D+(%d%d?):(%d%d)")
    if not y then
        d, mo, y, h, mi = text:match("(%d%d?)%.(%d%d?)%.(%d%d%d%d)%D+(%d%d?):(%d%d)")
    end
    if not y then return nil end
    return time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = 0 })
end

-- Nächster Raid: aus dem eigenen Raidplaner-Import oder aus der Gilde verteilt
function Ready:NextRaid()
    local best
    local plan = ns.db.plan
    local candidates = { ns.db.nextRaid }
    if plan and plan.date then table.insert(candidates, { id = plan.id, date = plan.date, title = plan.title }) end
    for _, r in ipairs(candidates) do
        local at = r and self.ParseDate(r.date)
        if at and at > time() - 3600 and (not best or at < best.at) then
            best = { id = r.id, date = r.date, title = r.title, at = at }
        end
    end
    return best
end

function Ready:ShareRaid(channel, target)
    local plan = ns.db.plan
    local at = plan and self.ParseDate(plan.date)
    if not at or at < time() or not IsInGuild() then return end
    local clean = function(s) return (tostring(s or ""):gsub("\t", " ")) end
    ns.Comm:Send("RAIDT", table.concat({ clean(plan.id), clean(plan.date), clean(plan.title) }, "\t"), channel or "GUILD", target)
end

ns.Comm.handlers.RAIDT = function(sender, parts)
    local at = Ready.ParseDate(parts[3])
    if not at or at < time() then return end
    local cur = ns.db.nextRaid
    local curAt = cur and Ready.ParseDate(cur.date)
    -- Den frühesten kommenden Raid behalten
    if curAt and curAt > time() and curAt <= at and cur.id ~= parts[2] then return end
    ns.db.nextRaid = { id = parts[2], date = parts[3], title = parts[4], from = ns.ShortName(sender) }
    ns:Fire("INFO_UPDATE")
end

ns.Comm.handlers.RAIDTQ = function(sender)
    if not ns.db.plan then return end
    C_Timer.After(2 + math.random() * 6, function() Ready:ShareRaid("WHISPER", sender) end)
end

function Ready:CheckReminder()
    local raid = self:NextRaid()
    if not raid then return end
    local left = raid.at - time()
    local key = tostring(raid.id or raid.date)
    if left > REMIND_BEFORE or left < 0 or ns.db.reminded == key then return end
    ns.db.reminded = key
    local mins = math.floor(left / 60 + 0.5)
    local text = string.format("Raid in %d Minuten%s – Reparieren, Fläschchen und Essen nicht vergessen!",
        mins, raid.title and (": " .. raid.title) or "")
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.86, b = 0.6 })
    end
    PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    ns.Print(text)
    local problems = self.Problems(self:Collect())
    if #problems > 0 then ns.Print("Dir fehlt noch: " .. table.concat(problems, " · ")) end
end

ns:Listen("INIT", function()
    C_Timer.NewTicker(30, function() Ready:CheckReminder() end)
end)
ns:On("PLAYER_LOGIN", function()
    C_Timer.After(25 + math.random() * 20, function()
        if IsInGuild() then ns.Comm:Send("RAIDTQ", nil, "GUILD") end
    end)
end)
-- Nach dem Import aus dem Raidplaner den Termin an die Gilde geben
ns:Listen("PLAN_IMPORTED", function() Ready:ShareRaid() end)
