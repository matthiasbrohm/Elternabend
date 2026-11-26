-- Elternabend: Neue Gildenmitglieder im Gildenchat begrüßen
--
-- Tritt jemand der Gilde bei, schreibt genau einer die Begrüßung mit Vorstellungsrunde, Discord und
-- Addon-Tipp – alle anderen schreiben nichts (ein „Willkommen“ von 15 Leuten war zu viel). Standardmäßig aus,
-- denn das Addon schreibt hier in deinem Namen (Einstellungen » „Neue Gildenmitglieder begrüßen“).
--
-- Wer die lange schreibt, losen die Addons unsichtbar aus: Beim Beitritt schickt jeder mit
-- eingeschaltetem Schalter eine Zufallszahl an die Gilde (Addon-Nachricht, nicht im Chat), die
-- höchste gewinnt. Wer gerade nicht an der Tastatur war, macht nicht mit. Taucht die lange
-- Begrüßung nicht auf, schreibt sie nach einer Weile der Nächste in der Reihe.
-- Gesendet wird über ns.SendChat (Core.lua): direkt, und falls das Spiel das blockiert, mit der nächsten Eingabe.
local _, ns = ...

local Welcome = { pending = {}, twinks = {} }
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
local ROLL_WAIT = 3       -- so lange werden die Zufallszahlen gesammelt
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

function Welcome.LongText(name)
    local template = LONG[math.random(1, #LONG)]
    local text = template:format(Display(name))
    if #text > 255 then text = template:format(Display(name):match("^(%S+)") or Display(name)) end
    return text
end

Welcome.LONG = LONG -- für die Tests

-- Beitritt aus der Systemmeldung lesen („%s ist der Gilde beigetreten.“ – Text des Spiels)
local joinPattern
local function JoinPattern()
    if joinPattern == nil then
        local fmt = type(ERR_GUILD_JOIN_S) == "string" and ERR_GUILD_JOIN_S or ""
        joinPattern = fmt ~= "" and ("^" .. fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%s", "(.+)") .. "$") or false
    end
    return joinPattern
end

-- Twinks bekommen keine Begrüßung für neue Spieler. Bescheid kommt bei der Anfrage vom Einladenden und
-- nach dem Beitritt vom Twink selbst (Addon-Nachricht TWK), dazu seine Zeile „… ein neuer Twink …“ im Gildenchat.
local TWINK_TTL = 3600
function Welcome:MarkTwink(name)
    local key = ns.NameKey(name)
    if not key then return end
    self.twinks[key] = time()
    local entry = self.pending[key]
    if entry then entry.seen = true end
end

function Welcome:IsTwink(key)
    local t = key and self.twinks[key]
    return t ~= nil and time() - t < TWINK_TTL
end

function Welcome:Joined(name)
    if not self:Enabled() or not name or ns.IsSecret(name) or ns.SameName(name, ns.UnitFullName("player")) then return end
    local key = ns.NameKey(name)
    if not key or self.pending[key] or self:IsTwink(key) then return end
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
    if entry.seen then return end -- steht schon im Chat
    local place = Place(entry)
    if place == 1 then
        self:Queue(entry)
    else
        -- Warten, bis die Begrüßung im Chat steht; bleibt sie aus, ist der Nächste dran
        local wait = place and (FALLBACK * (place - 1)) or (FALLBACK * 3)
        C_Timer.After(wait, function()
            local e = self.pending[key]
            if not e or e.sent or e.queued or e.seen then return end
            self:Queue(e)
        end)
    end
end

function Welcome:Queue(entry)
    if entry.queued then return end
    entry.queued = true
    if entry.sent or entry.seen or GetTime() - entry.joined > GIVE_UP then return end
    if self:IsTwink(ns.NameKey(entry.name)) then return end
    entry.sent = true
    ns.SendChat(Welcome.LongText(entry.name), "GUILD")
end

ns.Comm.handlers.TWK = function(_, parts)
    if parts[2] and parts[2] ~= "" then Welcome:MarkTwink(parts[2]) end
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

-- Steht die Begrüßung im Gildenchat? (Name und „discord“ in einer Zeile) Dann schreibt sonst keiner mehr.
ns:On("CHAT_MSG_GUILD", function(msg, sender)
    if type(msg) ~= "string" or ns.IsSecret(msg) or not next(Welcome.pending) then return end
    local lower = ns.Lower(msg)
    -- Der Neue schreibt selbst „ich bin ein neuer Twink“: keine Begrüßung
    if type(sender) == "string" and not ns.IsSecret(sender) and lower:find("twink", 1, true) then
        local key = ns.NameKey(sender)
        if key and Welcome.pending[key] then Welcome:MarkTwink(sender) end
    end
    if not lower:find("discord", 1, true) then return end
    for _, entry in pairs(Welcome.pending) do
        local first = ns.Lower(Display(entry.name):match("^(%S+)") or "")
        if first ~= "" and lower:find(first, 1, true) then entry.seen = true end
    end
end)
