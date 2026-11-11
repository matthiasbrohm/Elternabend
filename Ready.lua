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

-- Lagerfeuer-Buffs (WoW Forever): Wer eine Minute am Lagerfeuer sitzt, bekommt für eine Stunde je
-- aufgestelltem Lagerobjekt einen Buff. Erkannt werden sie an der Zauber-ID. Die IDs stammen aus
-- Datenbanken im Netz (zwei Reihen: Aura und Objekt) und sind im Spiel noch nicht alle bestätigt –
-- /ea lagerfeuer zeigt, was das Addon am eigenen Charakter findet.
local CAMP = {
    -- Alchemie: Manabrunnen
    [1307259] = "Mana", [1230564] = "Mana",
    -- Schmiedekunst: Schleifrad
    [1307392] = "Stärke", [1230171] = "Stärke",
    -- Verzauberkunst: Verzauberte Laute
    [1307234] = "Rüstung", [1230643] = "Rüstung",
    -- Erste Hilfe: Verbandskasten
    [1307244] = "Ausdauer", [1230117] = "Ausdauer",
    -- Kräuterkunde: Räucherkerze
    [1307251] = "Intelligenz", [1229705] = "Intelligenz",
    -- Bergbau: Magnetstein
    [1307254] = "Angriffskraft", [1230161] = "Angriffskraft",
    -- Kürschnerei: Lagerstuhl
    [1307229] = "Krit", [1229517] = "Krit",
    -- Schneiderei: Fraktionsbanner
    [1307239] = "Willenskraft", [1307240] = "Willenskraft", [1263425] = "Willenskraft",
    -- Angeln: Fischglas
    [1307245] = "Werte", [1229745] = "Werte",
    -- Sammelbuff „Vorzüge des Lagers“
    [1229741] = "Lager",
}
Ready.CAMP_ORDER = { "Angriffskraft", "Stärke", "Krit", "Werte", "Rüstung", "Ausdauer", "Intelligenz", "Willenskraft", "Mana", "Lager" }
local CAMP_LOW = 15 -- Minuten: darunter lieber nochmal ans Feuer

-- Im Spiel gibt es nur EINEN Buff („Lagervorteile“, 1229741); was er bringt, steht in seinem
-- Tooltip. Daraus die einzelnen Vorteile lesen: Stichwort im Text -> Bezeichnung.
local CAMP_WORDS = {
    { "angriffskraft", "Angriffskraft" }, { "attack power", "Angriffskraft" },
    { "stärke", "Stärke" }, { "strength", "Stärke" },
    { "kritisch", "Krit" }, { "critical", "Krit" },
    { "rüstung", "Rüstung" }, { "armor", "Rüstung" },
    { "ausdauer", "Ausdauer" }, { "stamina", "Ausdauer" },
    { "intelligenz", "Intelligenz" }, { "intellect", "Intelligenz" },
    { "willenskraft", "Willenskraft" }, { "spirit", "Willenskraft" },
    { "mana", "Mana" },
}

-- Tooltip-Zeilen eines eigenen Buffs (leer, wenn der Client sie nicht hergibt)
local function AuraLines(aura)
    local lines = {}
    local id = aura.auraInstanceID
    if not (C_TooltipInfo and C_TooltipInfo.GetUnitBuffByAuraInstanceID and id) or ns.IsSecret(id) then return lines end
    local ok, data = pcall(C_TooltipInfo.GetUnitBuffByAuraInstanceID, "player", id)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return lines end
    for i, line in ipairs(data.lines) do
        local text = line.leftText
        if i > 1 and type(text) == "string" and not ns.IsSecret(text) and text ~= "" then table.insert(lines, text) end
    end
    return lines
end

-- Der Tooltip von „Lagervorteile“ sieht so aus:
--   Erhält die folgenden Lagerboni:
--   Manabrunnen: Stellt alle 5 Sekunden 10 Mana wieder her.
-- Je Zeile „Lagerobjekt: Wirkung“. Die Wirkung bestimmt die Bezeichnung; passt kein Stichwort,
-- steht der Name des Lagerobjekts da.
local function CampLabel(effect)
    local text = ns.Lower(effect)
    if text:find("werte", 1, true) and text:find("%%") then return "Werte" end
    for _, w in ipairs(CAMP_WORDS) do
        if text:find(w[1], 1, true) then return w[2] end
    end
end

local function CampFromText(lines, seen, extra)
    local found = false
    for _, block in ipairs(lines) do
        for line in block:gmatch("[^\r\n]+") do
            local object, effect = line:match("^%s*([^:]+):%s*(%S.*)$")
            -- Nur echte Boni: nicht „Zauber-ID: 1229741“ (Zahl) und nicht „Noch 18 Minuten“
            -- (enthält intern „|4Minute:Minuten;“)
            if object and (object:find("[%d|]") or not effect:find("%a+%s+%a")) then object = nil end
            if object then
                found = true
                local label = CampLabel(effect)
                if label then
                    seen[label] = true
                else
                    label = strtrim((object:gsub("[,\t|]", " "))):sub(1, 24)
                    if label ~= "" and not seen[label] then
                        seen[label] = true
                        table.insert(extra, label)
                    end
                end
            end
        end
    end
    if found then return end
    -- Anderes Format: wenigstens nach Stichwörtern im ganzen Text suchen
    local text = ns.Lower(table.concat(lines, " "))
    for _, w in ipairs(CAMP_WORDS) do
        if text:find(w[1], 1, true) then seen[w[2]] = true end
    end
end

local function HasWord(name, words)
    for _, w in ipairs(words) do
        if name:find(w, 1, true) then return true end
    end
    return false
end

-- Eigener Charakter ---------------------------------------------------------------
function Ready:Collect()
    local r = { flask = false, food = false, durability = 100, missing = {}, camp = {}, campLeft = 0 }
    local campSeen, campExtra, campEnd = {}, {}, nil
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
            local id = aura.spellId
            local label = id and not ns.IsSecret(id) and CAMP[id]
            if label and not campSeen[label] then
                campSeen[label] = true
                if label == "Lager" then CampFromText(AuraLines(aura), campSeen, campExtra) end
                local expires = aura.expirationTime
                if expires and not ns.IsSecret(expires) and expires > 0 then
                    campEnd = math.min(campEnd or expires, expires)
                end
            end
        end
    end
    -- „Lager“ steht nur für den Buff selbst: weglassen, sobald die einzelnen Vorteile bekannt sind
    local details = 0
    for label in pairs(campSeen) do
        if label ~= "Lager" then details = details + 1 end
    end
    if details > 0 then campSeen["Lager"] = nil end
    for _, label in ipairs(Ready.CAMP_ORDER) do
        if campSeen[label] then table.insert(r.camp, label) end
    end
    for _, label in ipairs(campExtra) do table.insert(r.camp, label) end
    if campEnd then r.campLeft = math.max(0, math.floor((campEnd - GetTime()) / 60)) end
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
    return table.concat({ r.flask and 1 or 0, r.food and 1 or 0, r.durability, table.concat(r.missing, ","),
        #r.camp > 0 and table.concat(r.camp, ",") or "-", r.campLeft or 0 }, "\t")
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

-- Lagerfeuer: Kurztext für die Liste und Zeile für den Tooltip (nil = Addon zu alt, meldet es nicht)
function Ready.CampShort(r)
    if not r or not r.camp then return nil end
    if #r.camp == 0 then return "–", "none" end
    local what = (#r.camp == 1 and r.camp[1] == "Lager") and "ja" or tostring(#r.camp)
    return what .. " · " .. (r.campLeft or 0) .. " Min", (r.campLeft or 0) < CAMP_LOW and "low" or "ok"
end

function Ready.CampLine(r)
    if not r or not r.camp then return nil end
    if #r.camp == 0 then return "Lagerfeuer: kein Buff" end
    if #r.camp == 1 and r.camp[1] == "Lager" then return "Lagerfeuer: Lagervorteile (noch " .. (r.campLeft or 0) .. " Min.)" end
    return "Lagerfeuer: " .. table.concat(r.camp, ", ") .. " (noch " .. (r.campLeft or 0) .. " Min.)"
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
    local campNone, campLow, campAny = {}, {}, false
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
            if r.camp then
                if #r.camp == 0 then
                    table.insert(campNone, name)
                else
                    campAny = true
                    if (r.campLeft or 0) < CAMP_LOW then table.insert(campLow, name) end
                end
            end
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
    -- Lagerfeuer nur ansagen, wenn es überhaupt jemand hat (sonst war die Gruppe noch nicht am Feuer)
    if campAny then
        if #campNone > 0 then ns.AnnounceList("Kein Lagerfeuer-Buff: ", campNone) end
        if #campLow > 0 then ns.AnnounceList("Lagerfeuer läuft bald ab: ", campLow) end
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
    -- Lagerfeuer melden erst neuere Versionen: fehlt das Feld, bleibt camp nil (= unbekannt)
    local camp
    if parts[6] then
        camp = {}
        if parts[6] ~= "-" then
            for label in parts[6]:gmatch("[^,]+") do table.insert(camp, label) end
        end
    end
    Ready.states[key] = { flask = parts[2] == "1", food = parts[3] == "1", durability = tonumber(parts[4]) or 100, missing = missing,
        camp = camp, campLeft = tonumber(parts[7]) or 0 }
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
    -- Termine aus dem Kalender (Export aus dem Raidplaner)
    for _, r in ipairs(ns.Calendar and ns.Calendar:Raids() or {}) do
        if r.status ~= "abgesagt" then
            table.insert(candidates, { id = r.id, date = date("%Y-%m-%d %H:%M", r.start), title = r.name })
        end
    end
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

-- /ea lagerfeuer: Was erkennt das Addon am eigenen Charakter? Zeigt auch unbekannte neue Buffs
-- mit ihrer ID, damit sich die Liste oben ergänzen lässt.
function Ready:PrintCamp()
    local r = self:Collect()
    if #r.camp > 0 then
        ns.Print("|cff40ff40Lagerfeuer erkannt:|r " .. table.concat(r.camp, ", ") .. " (noch " .. r.campLeft .. " Min.)")
    else
        ns.Print("Kein Lagerfeuer-Buff erkannt.")
    end
    local unknown = {}
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 60 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
            if not aura then break end
            local id, name = aura.spellId, aura.name
            if id and not ns.IsSecret(id) and not ns.IsSecret(name) then
                table.insert(unknown, (CAMP[id] and "|cff40ff40" or "|cffc8bead") .. tostring(name) .. " = " .. id .. "|r")
                if CAMP[id] then
                    -- Was steht im Tooltip? (daraus liest das Addon die einzelnen Vorteile)
                    local lines = AuraLines(aura)
                    for _, text in ipairs(lines) do table.insert(unknown, "      |cfff3dc9aTooltip:|r " .. text) end
                    if #lines == 0 then table.insert(unknown, "      |cffffb35aKein Tooltip-Text lesbar|r") end
                    if type(aura.points) == "table" and #aura.points > 0 then
                        local pts = {}
                        for _, v in ipairs(aura.points) do table.insert(pts, tostring(v)) end
                        table.insert(unknown, "      |cfff3dc9aWerte:|r " .. table.concat(pts, " / "))
                    end
                end
            end
        end
    end
    if #unknown > 0 then
        ns.Print("Deine Buffs mit ID (grün = als Lagerfeuer erkannt):")
        for _, line in ipairs(unknown) do print("   " .. line) end
    end
end
