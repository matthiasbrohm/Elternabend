-- Elternabend Raid: Austausch mit gilde-elternabend.de
--
-- Ein Addon kann im Spiel nicht ins Internet. Der Austausch läuft deshalb über
-- Texte zum Kopieren und Einfügen:
--   Webseite → Addon: Der Raidplaner gibt einen Raid mit Anmeldungen und
--                     Soft-Reserves als Text aus ("#ELTERNABEND-RAID").
--   Addon → Webseite: Nach dem Raid erzeugt das Addon einen Bericht mit
--                     Anwesenheit, Bossen und Beute ("#ELTERNABEND-BERICHT").
-- Das genaue Format steht in der README.md.
local _, ns = ...

local Web = {}
ns.Web = Web

local FORMAT_VERSION = 1
local SESSION_TIMEOUT = 6 * 3600 -- nach 6 Stunden Pause beginnt ein neuer Raid

local function Split(line)
    local fields = {}
    for field in (line .. ";"):gmatch("([^;]*);") do
        table.insert(fields, strtrim(field))
    end
    return fields
end

local function Clean(s)
    if s == nil then return "" end
    return (tostring(s):gsub("[;\r\n|]", " "))
end

-- Import ---------------------------------------------------------------------
-- Erkennt das Format des Raidplaners und fällt sonst auf softres.it-CSV zurück.
function Web:Import(text)
    text = text or ""
    if text:find("#ELTERNABEND%-RAID") then
        return self:ImportPlan(text)
    end
    return ns.SR:Import(text)
end

function Web:ImportPlan(text)
    local plan = { signups = {}, importedAt = time() }
    local entries = {}
    local dates = {} -- kommende Raidtermine für den Kalender („termin;…“)

    for line in text:gmatch("[^\r\n]+") do
        local f = Split(line)
        local kind = (f[1] or ""):lower()
        if kind == "raid" then
            plan.id, plan.title, plan.template, plan.date = f[2], f[3], f[4], f[5]
        elseif kind == "spieler" and f[2] and f[2] ~= "" then
            local key = ns.NameKey(f[2])
            if key then
                plan.signups[key] = { name = f[2], class = f[3], role = (f[4] or ""):lower(),
                    status = (f[5] ~= nil and f[5] ~= "") and f[5]:lower() or "dabei" }
            end
        elseif kind == "gruppe" and tonumber(f[2]) then
            -- Raidgruppe aus dem Raidplaner: gruppe;Nummer;Name;Name;…
            local g = tonumber(f[2])
            if g >= 1 and g <= 8 then
                plan.groups = plan.groups or {}
                plan.groups[g] = {}
                for i = 3, math.min(#f, 7) do
                    if f[i] ~= "" then table.insert(plan.groups[g], f[i]) end
                end
            end
        elseif kind == "termin" and f[2] and tonumber(f[4]) then
            -- termin;ID;Name;Start;Dauer;Zusagen;Plätze;Status → Zeile im Format des Kalenders
            table.insert(dates, table.concat({ "R", f[2], (f[3] or ""):gsub("[%^~]", " "), f[4], tonumber(f[5]) or 120,
                tonumber(f[6]) or 0, tonumber(f[7]) or 0, f[8] or "offen" }, "^"))
        elseif kind == "sr" and f[2] and tonumber(f[3]) then
            table.insert(entries, { name = f[2], itemId = tonumber(f[3]), itemName = f[4], boss = f[5] ~= "" and f[5] or nil, plus = 0 })
        end
    end

    if not plan.id and next(plan.signups) == nil and #entries == 0 then
        ns.Print("|cffff5555Import fehlgeschlagen:|r Keine Raid-Daten gefunden.")
        return false
    end

    ns.db.plan = plan
    ns.SR:SetEntries(entries, "Raidplaner" .. (plan.title and (": " .. plan.title) or ""))
    local count = 0
    for _ in pairs(plan.signups) do count = count + 1 end
    ns.Print(string.format("Raid „%s“ geladen: %d Anmeldungen, %d Soft-Reserves%s.", plan.title or "?", count, #entries,
        plan.groups and " – mit Raidgruppen (Raid » Raidgruppen)" or ""))
    -- Ein Text für alles: die Raidtermine gleich in den Kalender (nur Offiziere dürfen sie verteilen)
    if #dates > 0 and ns.Board:AmOfficer() then
        local ok, n, changed = ns.Calendar:Import("EART1^" .. time() .. "\n" .. table.concat(dates, "\n"), true)
        if ok and changed then
            ns.Print(n .. (n == 1 and " Raidtermin" or " Raidtermine") .. " im Kalender aktualisiert und an die Gilde geschickt.")
        end
    end
    if IsInGroup() and ns.IsTrusted(ns.UnitFullName("player")) then
        ns.Print("Tipp: Mit „An Gruppe senden“ sehen alle die Soft-Reserves.")
    end
    ns:Fire("ROSTER_UPDATE")
    ns:Fire("PLAN_IMPORTED")
    return true
end

-- Raid-Protokoll (Anwesenheit und Bosse) -----------------------------------
function Web:StartSession(silent)
    local name, instanceType = GetInstanceInfo()
    local plan = ns.db.plan
    ns.db.session = {
        id = time(),
        start = time(),
        last = time(),
        raidId = plan and plan.id,
        title = plan and plan.title,
        instance = instanceType == "raid" and name or nil,
        players = {},
        bosses = {},
    }
    self:Track()
    if not silent then ns.Print("Raid-Protokoll gestartet. Anwesenheit, Bosse und Beute werden mitgeschrieben.") end
    ns:Fire("SESSION_UPDATE")
end

function Web:EndSession()
    local s = ns.db.session
    if not s or s.ended then return end
    s.ended = time()
    ns.Print("Raid-Protokoll beendet. Den Bericht für die Webseite findest du unter „Bericht für die Webseite“.")
    ns:Fire("SESSION_UPDATE")
end

function Web:IsRunning()
    local s = ns.db.session
    return s ~= nil and not s.ended
end

-- Jede Minute: alle anwesenden Spieler erhalten eine Minute Anwesenheit
function Web:Track()
    local s = ns.db.session
    if not s or s.ended or not IsInGroup() then return end
    s.last = time()
    local name, instanceType = GetInstanceInfo()
    if instanceType == "raid" and not s.instance then s.instance = name end
    for _, m in ipairs(ns.Raid.members) do
        if m.online then
            local p = s.players[m.key]
            if not p then
                p = { name = ns.ShortName(m.name), class = m.class, classFile = m.classFile, first = time(), minutes = 0 }
                s.players[m.key] = p
            end
            p.minutes = p.minutes + 1
        end
    end
end

local function CheckAutoStart()
    if not ns.db or not ns.db.settings.autoSession or not IsInRaid() then return end
    local _, instanceType = GetInstanceInfo()
    if instanceType ~= "raid" then return end
    local s = ns.db.session
    if s and not s.ended and time() - (s.last or 0) < SESSION_TIMEOUT then return end
    Web:StartSession(true)
    ns.Print("Raid-Instanz betreten – das Raid-Protokoll läuft.")
end

ns:Listen("INIT", function()
    C_Timer.NewTicker(60, function() Web:Track() end)
end)
ns:On("PLAYER_ENTERING_WORLD", function() C_Timer.After(3, CheckAutoStart) end)
ns:On("ZONE_CHANGED_NEW_AREA", function() C_Timer.After(3, CheckAutoStart) end)

ns:On("ENCOUNTER_END", function(encounterID, encounterName, difficultyID, groupSize, success)
    local s = ns.db and ns.db.session
    if not s or s.ended then return end
    if ns.IsSecret(encounterID) or ns.IsSecret(encounterName) or ns.IsSecret(success) then return end
    table.insert(s.bosses, { time = time(), id = encounterID, name = encounterName, kill = success == 1 })
    ns:Fire("SESSION_UPDATE")
end)

-- Bericht für die Webseite -------------------------------------------------
function Web:BuildReport()
    local s = ns.db.session
    if not s then return nil end
    local lines = { "#ELTERNABEND-BERICHT " .. FORMAT_VERSION }
    local signups = ns.db.plan and ns.db.plan.signups or {}

    table.insert(lines, table.concat({ "raid", Clean(s.raidId), Clean(s.instance or s.title), s.start, s.ended or s.last,
        Clean(ns.ShortName(ns.UnitFullName("player"))) }, ";"))

    local players = {}
    for key, p in pairs(s.players) do table.insert(players, { key = key, p = p }) end
    table.sort(players, function(a, b) return a.p.name < b.p.name end)
    for _, e in ipairs(players) do
        local signup = signups[e.key]
        table.insert(lines, table.concat({ "anwesend", Clean(e.p.name), Clean(e.p.class), e.p.minutes,
            signup and signup.status or "nicht angemeldet" }, ";"))
    end

    for _, b in ipairs(s.bosses) do
        table.insert(lines, table.concat({ "boss", b.time, b.id or 0, Clean(b.name), b.kill and 1 or 0 }, ";"))
    end

    for i = #ns.db.history, 1, -1 do
        local h = ns.db.history[i]
        if h.session == s.id then
            local itemName = h.link and h.link:match("%[(.-)%]") or ""
            table.insert(lines, table.concat({ "beute", h.time, h.itemId or 0, Clean(itemName), Clean(h.winner),
                h.sr and "SR" or Clean(h.label), h.roll or "" }, ";"))
        end
    end

    table.insert(lines, "#ENDE")
    return table.concat(lines, "\n")
end
