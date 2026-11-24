-- Elternabend: Neue Gildenmitglieder im Gildenchat begrüßen
--
-- Tritt jemand der Gilde bei, schreibt genau einer die lange Begrüßung mit Vorstellungsrunde,
-- Discord und Addon-Tipp – alle anderen danach nur ein kurzes „Willkommen“. Standardmäßig aus,
-- denn das Addon schreibt hier in deinem Namen (Einstellungen » „Neue Gildenmitglieder begrüßen“).
--
-- Wer die lange schreibt, losen die Addons unsichtbar aus: Beim Beitritt schickt jeder mit
-- eingeschaltetem Schalter eine Zufallszahl an die Gilde (Addon-Nachricht, nicht im Chat), die
-- höchste gewinnt. Wer gerade nicht an der Tastatur war, macht nicht mit. Taucht die lange
-- Begrüßung nicht auf, schreibt sie nach einer Weile der Nächste in der Reihe.
-- Gesendet wird über ns.SendChat (Core.lua): direkt, und falls das Spiel das blockiert, mit der nächsten Eingabe.
local _, ns = ...

local Welcome = { pending = {} }
ns.Welcome = Welcome

-- Lange Begrüßung (einer schreibt sie): immer mit Name, Discord-Link, #vorstellungsrunde und Addon-Tipp.
-- Muss „discord“ enthalten – daran erkennen die anderen Addons, dass sie schon im Chat steht.
local LONG = {
    "Willkommen bei Elternabend, %s. Stell dich gern kurz im Discord in #vorstellungsrunde vor: "
        .. "discord.gg/elternabend - Tipp: Unser Addon \"Elternabend\" (CurseForge/Wago) zeigt Raids, Berufe und Gruppen.",
    "Herzlich willkommen, %s! Magst du dich kurz im Discord in #vorstellungsrunde vorstellen? discord.gg/elternabend - "
        .. "Unser Addon \"Elternabend\" (CurseForge/Wago) zeigt dir Raids, Berufe und Gruppen.",
    "Hallo %s, schön, dass du beim Elternabend bist! Sag gern im Discord in #vorstellungsrunde kurz Hallo: "
        .. "discord.gg/elternabend - Tipp: Das Addon \"Elternabend\" (CurseForge/Wago) hilft bei Raids, Berufen und Gruppen.",
    "Willkommen in der Runde, %s! Die Kinder schlafen, die Helden erwachen. Stell dich gern im Discord in "
        .. "#vorstellungsrunde vor: discord.gg/elternabend - Unser Addon \"Elternabend\" gibt es bei CurseForge/Wago.",
    "Schön, dass du da bist, %s! Erster Punkt der Tagesordnung: kurz im Discord in #vorstellungsrunde vorstellen - "
        .. "discord.gg/elternabend. Unser Addon \"Elternabend\" (CurseForge/Wago) zeigt Raids, Berufe und Gruppen.",
    "Hallo %s und willkommen beim Elternabend! Wir freuen uns auf ein kurzes Hallo im Discord in #vorstellungsrunde: "
        .. "discord.gg/elternabend - Tipp: Addon \"Elternabend\" bei CurseForge/Wago holen.",
}
-- Kurzes Willkommen (alle anderen) – ohne „discord“, sonst hielte man es für die lange Begrüßung
local SHORT = {
    "Willkommen, %s!",
    "Herzlich willkommen, %s :)",
    "Hallo %s, schön, dass du da bist!",
    "Willkommen bei uns, %s!",
    "Hey %s, schön, dich dabeizuhaben!",
    "Willkommen beim Elternabend, %s – der Kaffee steht bereit!",
    "Hallo %s! Die Kinder schlafen, die Helden erwachen – willkommen!",
    "Moin %s, willkommen in der Runde!",
    "Schön, dass du zu uns gefunden hast, %s!",
    "Willkommen, %s! Setz dich, der Elternabend hat gerade angefangen.",
    "Ein herzliches Hallo an %s!",
    "Willkommen an Bord, %s :)",
    "Hallo %s, fühl dich wie zu Hause!",
    "Juhu, Verstärkung! Willkommen, %s!",
    "Willkommen, %s – Fragen sind hier immer erlaubt!",
    "Hallo %s! Schnapp dir einen Keks und mach es dir gemütlich.",
    "Willkommen in der Familie, %s!",
    "Na, wer ist denn da? Hallo %s, willkommen!",
    "Willkommen, %s! Die Hausaufgaben sind gemacht, jetzt wird gespielt.",
    "Grüß dich, %s, schön, dass du da bist!",
    "Willkommen, %s! Psst, die Kleinen schlafen schon ;)",
    "Hallo %s, willkommen beim Elternabend – Anwesenheit wird nicht kontrolliert :)",
}
local ROLL_WAIT = 3       -- so lange werden die Zufallszahlen gesammelt
local SHORT_AFTER = 6     -- frühestens so lange nach dem Beitritt kommt ein kurzes Willkommen
local FALLBACK = 25       -- lange Begrüßung nach so vielen Sekunden nicht gesehen: der Nächste schreibt sie
local GIVE_UP = 180       -- so lange nach dem Beitritt ist es zu spät
local AWAY = 120          -- so lange ohne Eingabe: nicht an der Tastatur, nicht mitlosen

function Welcome:Enabled()
    return ns.db and ns.db.settings.welcome == true
end

-- Name für den Chat: ohne Server, mit Nachnamen (so steht er auch in der Gildenliste)
local function Display(name)
    return ns.ShortName(name) or name
end

-- Zufällige Vorlage; was im Gildenchat für diesen Neuen schon stand, nicht noch einmal
local function Pick(list, name, seen)
    local free = {}
    for _, t in ipairs(list) do
        if not (seen and seen[ns.Lower(t:format(name))]) then table.insert(free, t) end
    end
    if #free == 0 then free = list end
    return free[math.random(1, #free)]
end

function Welcome.LongText(name, seen)
    local template = Pick(LONG, Display(name), seen)
    local text = template:format(Display(name))
    if #text > 255 then text = template:format(Display(name):match("^(%S+)") or Display(name)) end
    return text
end

function Welcome.ShortText(name, seen)
    return Pick(SHORT, Display(name), seen):format(Display(name))
end

Welcome.LONG, Welcome.SHORT = LONG, SHORT -- für die Tests

-- Beitritt aus der Systemmeldung lesen („%s ist der Gilde beigetreten.“ – Text des Spiels)
local joinPattern
local function JoinPattern()
    if joinPattern == nil then
        local fmt = type(ERR_GUILD_JOIN_S) == "string" and ERR_GUILD_JOIN_S or ""
        joinPattern = fmt ~= "" and ("^" .. fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$") or false
    end
    return joinPattern
end

function Welcome:Joined(name)
    if not self:Enabled() or not name or ns.IsSecret(name) or ns.SameName(name, ns.UnitFullName("player")) then return end
    local key = ns.NameKey(name)
    if not key or self.pending[key] then return end
    local now = GetTime()
    local entry = { name = name, joined = now, rolls = {} }
    self.pending[key] = entry
    -- nur wer gerade spielt, lost mit – sonst hinge die lange Begrüßung an jemandem, der weg ist
    if now - (ns.lastInput or 0) < AWAY then
        entry.roll = math.random(1, 999999)
        entry.rolls[ns.NameKey(ns.UnitFullName("player")) or "?"] = entry.roll
        ns.Comm:Send("WELCOME", key .. "\t" .. entry.roll, "GUILD")
    end
    C_Timer.After(ROLL_WAIT, function() self:Decide(key) end)
    C_Timer.After(GIVE_UP, function() self.pending[key] = nil end)
end

-- Platz in der Reihe: 1 = höchste Zahl (schreibt die lange Begrüßung)
local function Place(entry)
    if not entry.roll then return nil end
    local place = 1
    local me = ns.NameKey(ns.UnitFullName("player")) or "?"
    for who, roll in pairs(entry.rolls) do
        if who ~= me and (roll > entry.roll or (roll == entry.roll and who < me)) then place = place + 1 end
    end
    return place
end

function Welcome:Decide(key)
    local entry = self.pending[key]
    if not entry or entry.sent then return end
    entry.decided = true
    local place = Place(entry)
    if place == 1 and not entry.seen then
        self:Queue(entry, true)
    elseif entry.seen then
        self:Queue(entry, false)
    else
        -- Warten, bis die lange Begrüßung im Chat steht; bleibt sie aus, ist der Nächste dran
        local wait = place and (FALLBACK * (place - 1)) or (FALLBACK * 3)
        C_Timer.After(math.max(SHORT_AFTER, wait), function()
            local e = self.pending[key]
            if not e or e.sent or e.queued then return end
            self:Queue(e, not e.seen)
        end)
    end
end

function Welcome:Queue(entry, long)
    if entry.queued then return end
    entry.queued = true
    local delay = long and 0 or math.max(0, SHORT_AFTER - (GetTime() - entry.joined)) + math.random() * 4
    C_Timer.After(delay, function()
        if entry.sent or GetTime() - entry.joined > GIVE_UP then return end
        -- inzwischen hat jemand anderes die lange geschrieben: dann doch nur kurz
        local useLong = long and not entry.seen
        entry.sent = true
        ns.SendChat(useLong and Welcome.LongText(entry.name, entry.texts) or Welcome.ShortText(entry.name, entry.texts), "GUILD")
    end)
end

ns.Comm.handlers.WELCOME = function(sender, parts)
    local key, roll = parts[2], tonumber(parts[3])
    local entry = key and Welcome.pending[key]
    if not roll or not ns.Members:Find(sender) then return end
    if not entry then
        -- Beitrittsmeldung hier noch nicht angekommen: Zahl merken, der Beitritt folgt gleich
        if not Welcome:Enabled() then return end
        Welcome.early = Welcome.early or {}
        Welcome.early[key] = Welcome.early[key] or {}
        Welcome.early[key][ns.NameKey(sender) or sender] = roll
        return
    end
    entry.rolls[ns.NameKey(sender) or sender] = roll
end

ns:On("CHAT_MSG_SYSTEM", function(msg)
    if not Welcome:Enabled() or type(msg) ~= "string" or ns.IsSecret(msg) then return end
    local pattern = JoinPattern()
    local name = pattern and msg:match(pattern)
    if not name then return end
    Welcome:Joined(name)
    local key = ns.NameKey(name)
    local entry = key and Welcome.pending[key]
    if entry and Welcome.early and Welcome.early[key] then
        for who, roll in pairs(Welcome.early[key]) do entry.rolls[who] = roll end
        Welcome.early[key] = nil
    end
end)

-- Steht die lange Begrüßung im Gildenchat? (Name und „discord“ in einer Zeile)
ns:On("CHAT_MSG_GUILD", function(msg)
    if type(msg) ~= "string" or ns.IsSecret(msg) or not next(Welcome.pending) then return end
    local lower = ns.Lower(msg)
    -- Was die anderen schon geschrieben haben, merken – dann wählt man selbst einen anderen Text
    for _, entry in pairs(Welcome.pending) do
        entry.texts = entry.texts or {}
        entry.texts[lower] = true
    end
    if not lower:find("discord", 1, true) then return end
    for _, entry in pairs(Welcome.pending) do
        local first = ns.Lower(Display(entry.name):match("^(%S+)") or "")
        if first ~= "" and lower:find(first, 1, true) then
            entry.seen = true
            -- schon ausgelost und nicht dran: jetzt das kurze Willkommen hinterher
            if entry.decided and not entry.queued then Welcome:Queue(entry, false) end
        end
    end
end)
