-- Elternabend Raid: Kern (Namespace, Events, Hilfsfunktionen, Slash-Befehle)
-- Zielplattform: WoW Forever (Retail-Client, Interface 16001)
local ADDON, ns = ...
_G.Elternabend = ns

ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "dev"
ns.PREFIX = "ElternRaid"
ns.WEBSITE = "gilde-elternabend.de"
ns.DOWNLOAD = "gilde-elternabend.de/addon" -- Download-Seite mit Versionshinweisen
ns.LOGO = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Wappen" -- Gildenwappen (Media/Wappen.tga)

local defaults = {
    settings = {
        rollTime = 20,       -- Sekunden pro Würfelrunde
        msMax = 100,         -- /roll 100 = Hauptspezialisierung
        osMax = 99,          -- /roll 99  = Off-Spec und Twinks
        minQuality = 4,      -- ab dieser Qualität im Plündermeister-Reiter (4 = Episch)
        raidWarning = true,  -- Würfelrunden als Schlachtzugswarnung ansagen
        autoOpenLoot = true, -- Fenster beim Looten automatisch öffnen
        srPriority = true,   -- SR-Würfe gewinnen vor normalen Würfen
        autoSession = true,  -- Raid-Protokoll beim Betreten einer Raid-Instanz starten
        minimapAngle = 220,
        minimapHidden = false,
        guildButtonHidden = false,
    },
    softres = { items = {} },
    recruit = {      -- Gildeneinladung per Flüstern
        enabled = true,
        popup = true,          -- Fenster und Ton bei neuen Anfragen (aus = still im Reiter Invite sammeln)
        quietInstance = true,  -- in Dungeons und Raids automatisch stumm
        keywords = "ginv, gildeninvite, gilde",
        reply = "Die Einladung in die Gilde Elternabend ist unterwegs – einfach annehmen. Willkommen!",
        log = {},
    },
    welcomeSeen = {}, -- Begrüßung schon gezeigt (pro Charakter)
    professions = {}, -- Berufe und Rezepte der Gilde (eigene und empfangene)
    myChars = {},     -- eigene Charaktere auf diesem Account
    myMain = nil,     -- Schlüssel des eigenen Mains
    memberSuggestions = {}, -- alt (bis 4.5): Twink-Vorschläge für Offiziere
    guildlog = {},    -- Gildenchronik für die Leitung: Gildenname -> { snapshot, events, since }
    links = {},       -- Twink-Zuordnungen im Addon: Twink-Schlüssel -> { twink, main, t, by, k }
    sync = {},        -- Abgleich über die Mac-App: wann zuletzt ein Raid von der Webseite übernommen wurde
    profiles = {},    -- Spielzeiten und „Erste Schritte“ der Gilde: Schlüssel -> { name, t, times, steps, note }
    me = {},          -- eigene Spielzeiten und abgehakte Schritte (accountweit)
    options = {},     -- Einstellungen: abgeschaltete Bereiche (Schlüssel -> false), siehe ns.OPTIONS
    quiz = { best = 0 }, -- Quiz: längste Serie; als Leitung zusätzlich, welche Fragen schon dran waren
    away = {         -- „Kind wach, gleich zurück“
        showButton = true, -- Elternknopf auf dem Bildschirm, solange man in einer Gruppe ist
        announce = true,   -- zusätzlich eine Zeile im Gruppenchat (für Spieler ohne Addon)
    },
    notes = {        -- eigene Notizen, auf Wunsch auf dem Bildschirm
        list = {},
        nextId = 1,
    },
    groups = {       -- Gruppensuche in der Gilde
        notify = true,     -- neue Gesuche im Chat melden
        chat = true,       -- eigene Gesuche auch im Gildenchat posten (für Mitglieder ohne Addon)
        seen = {},         -- Gesuche, die man im Reiter „Gruppen“ schon gesehen hat (für die Plakette)
    },
    orders = {       -- Handwerksaufträge
        out = {},          -- eigene Aufträge an andere
        inc = {},          -- Aufträge an die eigenen Charaktere
        outbox = {},       -- Nachrichten an gerade Abwesende
    },
    fame = {},       -- Ruhmeshalle: Erstkills der Gilde
    board = {        -- Pinnwand: Zettel der Gilde (accountweit)
        notes = {},        -- alle bekannten Zettel
        seen = {},         -- gelesen (Prüfsumme beim Lesen)
    },
    calendar = {     -- Kalender
        raids = { version = 0, list = {} }, -- Raidtermine aus dem Raidplaner (in der Gilde verteilt)
        show = {},         -- Filter: Art -> false = ausgeblendet
    },
    plan = nil,      -- Raid aus dem Raidplaner der Webseite
    nextRaid = nil,  -- nächster Raidtermin, in der Gilde verteilt
    session = nil,   -- laufendes Raid-Protokoll (Anwesenheit, Bosse)
    history = {},    -- vergebene Beute
}

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Spiel-Events -----------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if list then
        for i = 1, #list do list[i](...) end
    end
end)

-- Interne Nachrichten zwischen den Modulen ------------------------------
local listeners = {}

function ns:Listen(msg, fn)
    listeners[msg] = listeners[msg] or {}
    table.insert(listeners[msg], fn)
end

function ns:Fire(msg, ...)
    local list = listeners[msg]
    if list then
        for i = 1, #list do list[i](...) end
    end
end

-- Geheime Werte und Chat-Sperre ----------------------------------------
-- Der Retail-Client verschleiert in Kämpfen und Bossbegegnungen manche Werte
-- ("secret values") und sperrt Chat- und Addon-Nachrichten. Solche Werte dürfen
-- nicht verglichen oder gespeichert werden.
function ns.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

function ns.ChatLocked()
    return C_ChatInfo.InChatMessagingLockdown ~= nil and C_ChatInfo.InChatMessagingLockdown()
end

-- Was während der Sperre gesendet werden soll, wartet hier und geht danach raus
local pending = {}

function ns.WhenChatFree(fn)
    if ns.ChatLocked() then
        table.insert(pending, fn)
    else
        fn()
    end
end

local function FlushPending()
    if ns.ChatLocked() or #pending == 0 then return end
    local list = pending
    pending = {}
    for _, fn in ipairs(list) do fn() end
end

ns:On("ADDON_RESTRICTION_STATE_CHANGED", function() C_Timer.After(0.5, FlushPending) end)
ns:On("PLAYER_REGEN_ENABLED", function() C_Timer.After(1, FlushPending) end)
ns:On("ENCOUNTER_END", function() C_Timer.After(2, FlushPending) end)

-- Gegenstände ------------------------------------------------------------
function ns.GetItemInfo(item)
    return C_Item.GetItemInfo(item)
end

function ns.GetItemIcon(itemId)
    return C_Item.GetItemIconByID(itemId)
end

function ns.GetItemQuality(itemOrLink)
    local q = select(3, C_Item.GetItemInfo(itemOrLink))
    if not q and type(itemOrLink) == "number" then q = C_Item.GetItemQualityByID(itemOrLink) end
    return q
end

function ns.ItemIDFromLink(link)
    if not link or ns.IsSecret(link) then return nil end
    return tonumber(link:match("item:(%d+)"))
end

-- Hilfsfunktionen --------------------------------------------------------
function ns.Print(...)
    print("|cfff3dc9aElternabend:|r", ...)
end

function ns.ShortName(name)
    if not name or ns.IsSecret(name) then return nil end
    return name:match("^([^%-]+)") or name
end

local UPPER_TO_LOWER = { ["Ä"] = "ä", ["Ö"] = "ö", ["Ü"] = "ü", ["À"] = "à", ["Á"] = "á",
    ["É"] = "é", ["È"] = "è", ["Í"] = "í", ["Ó"] = "ó", ["Ú"] = "ú", ["Ñ"] = "ñ" }

-- Kleinschreibung nur für A–Z und Umlaute: string.lower behandelt die Bytes von
-- UTF-8-Zeichen je nach Systemeinstellung falsch und zerstört dann „Ä“ & Co.
function ns.Lower(s)
    s = s:gsub("[A-Z]", string.lower)
    for upper, lower in pairs(UPPER_TO_LOWER) do
        s = s:gsub(upper, lower)
    end
    return s
end

-- Namen: In WoW Forever hat jeder Charakter Vor- und Nachnamen („Anna Sturmwind“).
-- UnitName liefert dort beide getrennt (zweiter Wert = Nachname), in Retail ist der
-- zweite Wert der Realm. Einladen und Anflüstern klappt in Forever nur mit dem
-- vollen Namen, deshalb arbeitet das Addon überall mit „Vorname Nachname“.
local toc = select(4, GetBuildInfo())
ns.IS_FOREVER = toc >= 16000 and toc < 17000
local SURNAME_SEPARATOR = Constants and Constants.CharacterNameSeparatorConsts
    and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "

-- Voller Name einer Einheit: Forever „Vorname Nachname“, Retail „Name-Realm“
function ns.UnitFullName(unit)
    local name, second = UnitName(unit)
    if not name or ns.IsSecret(name) or ns.IsSecret(second) then return name end
    if type(second) ~= "string" or second == "" then return name end
    if ns.IS_FOREVER then
        local tail = SURNAME_SEPARATOR .. second
        if name:sub(-#tail) == tail then return name end
        return name .. tail
    end
    return name .. "-" .. second
end

-- Vergleichsschlüssel: ohne Realm, kleingeschrieben, Vor- und Nachname mit einem Leerzeichen
-- Zwischenspeicher: NameKey läuft beim Auswerten der Gildenliste tausendfach mit denselben
-- Namen; jede Umwandlung kostet ein Dutzend gsub-Aufrufe (Ruckler bei großen Gilden)
local nameKeyCache, nameKeyCount = {}, 0
function ns.NameKey(name)
    if name == nil then return nil end
    local cached = nameKeyCache[name]
    if cached ~= nil then return cached or nil end
    local short = ns.ShortName(name)
    local key
    if short and short ~= "" then
        key = ns.Lower(strtrim(short))
        if SURNAME_SEPARATOR ~= " " then key = key:gsub((SURNAME_SEPARATOR:gsub("%W", "%%%0")), " ") end
        key = key:gsub("%s+", " ")
    end
    if type(name) == "string" then
        if nameKeyCount > 3000 then wipe(nameKeyCache); nameKeyCount = 0 end
        nameKeyCache[name] = key or false
        nameKeyCount = nameKeyCount + 1
    end
    return key
end

-- Nur der Vorname (für Listen, in denen jemand nur „Anna“ eingetragen hat)
function ns.FirstKey(name)
    local key = ns.NameKey(name)
    return key and (key:match("^(%S+)") or key)
end

-- Gleiche Person? Hat eine Seite nur den Vornamen, zählt der Vorname.
function ns.SameName(a, b)
    local ka, kb = ns.NameKey(a), ns.NameKey(b)
    if not ka or not kb then return false end
    if ka == kb then return true end
    local fa, fb = ns.FirstKey(ka), ns.FirstKey(kb)
    return (fa == ka or fb == kb) and fa == fb
end

function ns.PlayerKey()
    return ns.NameKey(ns.UnitFullName("player"))
end

function ns.GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

function ns.Announce(msg, useWarning)
    ns.WhenChatFree(function()
        local channel = ns.GroupChannel()
        if not channel then
            ns.Print(msg)
            return
        end
        if useWarning and channel == "RAID" and ns.db.settings.raidWarning
            and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
            channel = "RAID_WARNING"
        end
        C_ChatInfo.SendChatMessage(msg, channel)
    end)
end

-- Längere Namenslisten auf mehrere Chatzeilen (max. 255 Zeichen) verteilen
function ns.AnnounceList(prefix, names)
    local line = prefix
    for _, name in ipairs(names) do
        local part = (line == prefix and "" or ", ") .. name
        if #line + #part > 240 then
            ns.Announce(line)
            line = prefix .. name
        else
            line = line .. part
        end
    end
    ns.Announce(line)
end

-- Leiter oder Assistent? (darf Listen verteilen)
function ns.IsTrusted(name)
    local key = ns.NameKey(name)
    if not key then return false end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local _, rank = GetRaidRosterInfo(i)
            if ns.SameName(ns.UnitFullName("raid" .. i), key) then return (rank or 0) >= 1 end
        end
    elseif IsInGroup() then
        for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
            if UnitExists(unit) and ns.SameName(ns.UnitFullName(unit), key) then
                return UnitIsGroupLeader(unit)
            end
        end
    end
    return false
end

-- Einstellungen -----------------------------------------------------------
-- Alles, was das Addon außerhalb seines Fensters am Spiel verändert (Chat, Knöpfe auf dem
-- Bildschirm, Tooltips, Töne), lässt sich einzeln abstellen: Fenster „Einstellungen“ oder
-- /ea einstellungen. Ohne get/set liegt der Wert in ns.db.options (nil = an).
ns.OPTIONS = {
    { group = "IM CHAT" },
    { key = "chatMain", label = "Main vor Nachrichten von Twinks",
        hint = "Gilden- und Offizierschat: „(Beta) Wer kommt mit?“" },
    { key = "chatOnline", label = "Main hinter der Einlog-Meldung",
        hint = "„… ist jetzt online. (Twink von Beta Lux)“" },
    { key = "chatBoardMine", label = "Zettel an dich und Antworten auf deine Zettel melden" },
    { key = "chatBoard", label = "Neue Zettel an alle melden",
        hint = "sonst gesammelt in einer Zeile beim Einloggen" },
    { key = "chatGroups", label = "Neue Gruppengesuche melden",
        get = function() return ns.db.groups.notify end,
        set = function(on) ns.db.groups.notify = on end },
    { key = "awayChat", label = "„Kind wach“ zusätzlich in den Gruppenchat schreiben",
        hint = "für Mitspieler ohne Addon",
        get = function() return ns.db.away.announce end,
        set = function(on) ns.db.away.announce = on end },
    { key = "notices", label = "Statusmeldungen",
        hint = "„Raid-Protokoll läuft“, Pings anderer, ganze Soft-Reserve-Liste" },
    { group = "AUF DEM BILDSCHIRM" },
    { key = "awayButton", label = "Elternknopf, solange du in einer Gruppe bist",
        get = function() return ns.db.away.showButton end,
        set = function(on)
            ns.db.away.showButton = on
            ns.Away:UpdateButton()
        end },
    { key = "awayButtonIdle", label = "Elternknopf auch, wenn niemand weg ist",
        hint = "sonst nur, solange jemand weg ist",
        set = function(on)
            if on then ns.db.options.awayButtonIdle = nil else ns.db.options.awayButtonIdle = false end
            ns.Away:UpdateButton()
        end },
    { key = "minimap", label = "Knopf an der Minimap", hint = "ohne ihn öffnet /ea das Fenster",
        get = function() return not ns.db.settings.minimapHidden end,
        set = function(on)
            ns.db.settings.minimapHidden = not on
            ns.UI:UpdateMinimapButton()
        end },
    { key = "guildButton", label = "Knopf am Gildenfenster von Blizzard",
        get = function() return not ns.db.settings.guildButtonHidden end,
        set = function(on)
            ns.db.settings.guildButtonHidden = not on
            ns.GuildButton:Refresh()
        end },
    { key = "tooltipSR", label = "Soft-Reserves im Tooltip von Gegenständen" },
    { key = "raidReminder", label = "Erinnerung kurz vor dem Raid", hint = "eine Zeile im Chat" },
    { key = "raidReminderScreen", label = "Erinnerung auch groß in der Bildschirmmitte", hint = "mit Ton" },
    { key = "quizOpen", label = "Quizfenster öffnen, wenn die Leitung startet", hint = "sonst mit /ea quiz" },
    { key = "recruitPopup", label = "Fenster bei Gildenanfragen",
        hint = "sonst still im Reiter Invite",
        get = function() return ns.db.recruit.popup ~= false end,
        set = function(on)
            ns.db.recruit.popup = on
            ns:Fire("RECRUIT_UPDATE")
        end },
    { key = "lootOpen", label = "Fenster beim Plündern öffnen", hint = "im Raid, wenn es Beute zu verteilen gibt",
        get = function() return ns.db.settings.autoOpenLoot end,
        set = function(on) ns.db.settings.autoOpenLoot = on end },
    { group = "TÖNE" },
    { key = "soundsWaiting", label = "Töne, wenn jemand auf dich wartet",
        hint = "Soft-Reserve wird ausgewürfelt, Pause, Gruppenanfrage" },
    { key = "sounds", label = "Übrige Töne",
        hint = "Aufträge, Zettel an dich, Taktikbild, Raid-Erinnerung, Gildenanfragen" },
}

-- Voreinstellungen für die Knöpfe im Einstellungsfenster. „Ruhig“: Information ja, Unterbrechung nein –
-- nichts öffnet sich von selbst, Töne nur, wenn jemand auf dich wartet, Twinks im Chat bleiben.
ns.PRESETS = {
    an = {},
    ruhig = { minimap = false, sounds = false, chatBoard = false, raidReminderScreen = false, quizOpen = false,
        notices = false, awayButtonIdle = false, recruitPopup = false },
}

local optionByKey = {}
for _, o in ipairs(ns.OPTIONS) do
    if o.key then optionByKey[o.key] = o end
end

-- Ist ein Bereich eingeschaltet? (Vor dem Laden der gespeicherten Daten: ja.)
function ns.Opt(key)
    local o = optionByKey[key]
    if not o or not ns.db then return true end
    if o.get then return o.get() and true or false end
    return ns.db.options[key] ~= false
end

function ns.SetOpt(key, on)
    local o = optionByKey[key]
    if not o or not ns.db then return end
    on = on and true or false
    if o.set then
        o.set(on)
    else
        if on then ns.db.options[key] = nil else ns.db.options[key] = false end
    end
    ns:Fire("OPTIONS_UPDATE", key)
end

-- Eine Voreinstellung anwenden: "an", "aus" oder "ruhig" (nicht genannte Schalter: an, bei "aus": aus)
function ns.SetPreset(name)
    local preset = ns.PRESETS[name]
    for _, o in ipairs(ns.OPTIONS) do
        if o.key then
            local on = name ~= "aus"
            if preset and preset[o.key] ~= nil then on = preset[o.key] end
            ns.SetOpt(o.key, on)
        end
    end
end

-- Töne des Addons laufen hierüber. waiting = jemand wartet gerade auf dich (eigener Schalter)
function ns.Sound(kit, channel, waiting)
    if kit and ns.Opt(waiting and "soundsWaiting" or "sounds") then PlaySound(kit, channel) end
end

-- Initialisierung --------------------------------------------------------
ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    ElternabendDB = ElternabendDB or {}
    CopyDefaults(defaults, ElternabendDB)
    ns.db = ElternabendDB
    -- Umstellung 2: „Töne“ und „Pinnwand melden“ sind jetzt je zwei Schalter. Wer sie aus hatte, bekommt beide Teile aus.
    if (ns.db.optionsVersion or 1) < 2 then
        local o = ns.db.options
        if o.sounds == false then o.soundsWaiting = false end
        if o.chatBoard == false then o.chatBoardMine = false end
        ns.db.optionsVersion = 2
    end
    C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
    ns:Fire("INIT")
end)

-- Slash-Befehle ----------------------------------------------------------
local function Help()
    ns.Print("Befehle:")
    print("  /ea – Fenster öffnen/schließen")
    print("  /ea start | raid | sr | loot | beute | taktik | gruppen | gilde | kalender | pinnwand | berufe | notizen | invite – Bestimmten Reiter öffnen")
    print("  /ea ruhm – Ruhmeshalle: die Erstkills der Gilde")
    print("  /ea einstellungen – Chat-Zusätze, Knöpfe auf dem Bildschirm, Meldungen und Töne einzeln an- und abschalten")
    print("  /ea design – Design des Addons wählen (Elternabend, Allianz, Horde, Klassisch)")
    print("  /ea pause [Minuten] – Pause für den ganzen Raid (Leitung), /ea weiter beendet sie")
    print("  /ea vorbereitung – Fläschchen, Essen, Rüstung und Verzauberungen im Raid prüfen")
    print("  /ea gruppenhinweis – Neue Gruppengesuche im Chat melden an/aus")
    print("  /ea ginv – Flüster-Einladung in die Gilde an/aus")
    print("  /ea gilde – Mitglieder der Gilde mit Mains und Twinks")
    print("  /ea main – Diesen Charakter als Main festlegen")
    print("  /ea quiz – Quiz: in der Gruppe startet es die Leitung für alle, allein ist es eine Proberunde")
    print("  /ea kind [Minuten] – „Kind wach, gleich zurück“ (Standard 5 Minuten)")
    print("  /ea da – Wieder da")
    print("  /ea knopf – Elternknopf auf dem Bildschirm an/aus")
    print("  /ea kindchat – Kind-Status zusätzlich im Gruppenchat an/aus")
    print("  /ea import – Raid aus dem Raidplaner (oder softres.it-CSV) einfügen")
    print("  /ea bericht – Raid-Bericht für die Webseite erzeugen")
    print("  /ea sync – Soft-Reserves an die Gruppe senden")
    print("  /ea roll [Itemlink] – Würfelrunde für ein Item starten")
    print("  /ea rolltime <Sekunden> – Dauer einer Würfelrunde")
    print("  /ea quality <0-5> – Mindestqualität im Plündermeister-Reiter")
    print("  /ea rw – Schlachtzugswarnung an/aus")
    print("  /ea minimap – Minimap-Button ein/aus")
    print("  /ea gildenknopf – Knopf am Gildenfenster von Blizzard ein/aus")
    print("  /ea diagnose – zeigt, welche Addon-Nachrichten gesendet und empfangen wurden")
    print("  /ea ping – testet, ob Addon-Nachrichten in der Gilde ankommen")
end

SLASH_ELTERNABENDRAID1 = "/ea"
SLASH_ELTERNABENDRAID2 = "/elternabend"
SlashCmdList.ELTERNABENDRAID = function(input)
    input = strtrim(input or "")
    local cmd, rest = input:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    local s = ns.db.settings

    if cmd == "" then
        ns.UI:Toggle()
    elseif cmd == "start" or cmd == "info" then
        ns.UI:Show("start")
    elseif cmd == "raid" or cmd == "sr" or cmd == "loot" then
        ns.UI:Show(cmd)
    elseif cmd == "kind" or cmd == "afk" then
        ns.Away:Start(tonumber(rest) or 5)
    elseif cmd == "da" or cmd == "zurück" then
        ns.Away:Back()
    elseif cmd == "knopf" then
        ns.db.away.showButton = not ns.db.away.showButton
        ns.Print("Elternknopf: " .. (ns.db.away.showButton and "an" or "aus"))
        ns.Away:UpdateButton()
    elseif cmd == "kindchat" then
        ns.db.away.announce = not ns.db.away.announce
        ns.Print("Kind-Status im Gruppenchat: " .. (ns.db.away.announce and "an" or "aus"))
    elseif cmd == "gruppen" or cmd == "gruppe" or cmd == "lfg" then
        ns.UI:Show("gruppen")
    elseif cmd == "gruppenhinweis" then
        ns.db.groups.notify = not ns.db.groups.notify
        ns.Print("Neue Gruppengesuche im Chat: " .. (ns.db.groups.notify and "an" or "aus"))
    elseif cmd == "ruhm" or cmd == "ruhmeshalle" then
        ns.UI:ShowFame()
    elseif cmd == "pause" then
        ns.Pause:Start(tonumber(rest) or 5)
    elseif cmd == "weiter" then
        ns.Pause:End()
    elseif cmd == "vorbereitung" or cmd == "check" then
        ns.Ready:Check(ns.IsTrusted(ns.UnitFullName("player")))
        ns.UI:Show("raid")
    elseif cmd == "berufe" or cmd == "beruf" then
        ns.UI:Show("berufe")
    elseif cmd == "notizen" or cmd == "notiz" then
        ns.UI:Show("notizen")
    elseif cmd == "leitung" or cmd == "chronik" then
        ns.UI:Show("leitung")
    elseif cmd == "klassenliste" or cmd == "mitgliederliste" then
        ns.UI:ShowRoster()
    elseif cmd == "spielzeiten" or cmd == "zeiten" then
        ns.UI:ShowPlayTimes()
    elseif cmd == "schritte" or cmd == "ersteschritte" then
        ns.UI:ShowSteps()
    elseif cmd == "einstellungen" or cmd == "optionen" or cmd == "schalter" then
        ns.UI:ShowOptions()
    elseif cmd == "quiz" then
        ns.Quiz:Open()
    elseif cmd == "abgleich" then -- „sync“ heißt: Soft-Reserves an die Gruppe senden (weiter unten)
        ns.Sync:Status()
        ns.Sync:ApplyRaid(true)
    elseif cmd == "lagerfeuer" or cmd == "camp" then
        ns.Ready:PrintCamp()
    elseif cmd == "raidgruppen" or cmd == "aufstellung" then
        ns.UI:Show("raidgruppen")
    elseif cmd == "gruppentest" then
        -- Probe für die Raidplanung: Darf ein Addon hier Spieler zwischen den Raidgruppen verschieben?
        if not IsInRaid() then
            ns.Print("Der Test braucht einen Schlachtzug (zwei Spieler reichen: Gruppe bilden, in Schlachtzug umwandeln).")
        elseif not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
            ns.Print("Der Test braucht Leitung oder Assistenz im Schlachtzug.")
        else
            local index, from
            for i = 1, GetNumGroupMembers() do
                if UnitIsUnit("raid" .. i, "player") then index, from = i, select(3, GetRaidRosterInfo(i)) end
            end
            local to = from == 1 and 2 or 1
            ns.Print("Gruppentest: verschiebe dich von Gruppe " .. tostring(from) .. " nach Gruppe " .. to .. " …")
            local ok, err = pcall(SetRaidSubgroup, index, to)
            C_Timer.After(1.5, function()
                local now
                for i = 1, GetNumGroupMembers() do
                    if UnitIsUnit("raid" .. i, "player") then now = select(3, GetRaidRosterInfo(i)) end
                end
                if now == to then
                    ns.Print("|cff40ff40Gruppentest bestanden|r – du bist jetzt in Gruppe " .. to .. ". Das Addon darf Gruppen bauen.")
                else
                    ns.Print("|cffff6060Gruppentest nicht bestanden|r – du bist weiter in Gruppe " .. tostring(now) .. "."
                        .. (ok and "" or (" Fehler: " .. tostring(err))))
                end
            end)
        end
    elseif cmd == "design" or cmd == "skin" then
        ns.UI:ShowSkinPicker()
    elseif cmd == "kalender" or cmd == "termine" then
        ns.UI:Show("kalender")
    elseif cmd == "pinnwand" or cmd == "zettel" or cmd == "brett" then
        ns.UI:Show("pinnwand")
    elseif cmd == "gilde" or cmd == "mitglieder" or cmd == "twinks" then
        ns.UI:Show("mitglieder")
    elseif cmd == "main" then
        ns.Members:SetMyMain()
    elseif cmd == "invite" or cmd == "einladen" then
        ns.UI:Show("gilde")
    elseif cmd == "einlogtest" then
        ns.Members:OnlineTest()
    elseif cmd == "anfragen" or cmd == "stumm" then
        ns.Recruit:SetPopup(ns.db.recruit.popup == false)
    elseif cmd == "ginv" then
        ns.db.recruit.enabled = not ns.db.recruit.enabled
        ns.Print("Flüster-Einladung in die Gilde: " .. (ns.db.recruit.enabled and "an" or "aus"))
        ns:Fire("RECRUIT_UPDATE")
    elseif cmd == "taktik" then
        ns.UI:Show("taktik")
    elseif cmd == "verlauf" or cmd == "history" or cmd == "beute" then
        ns.UI:Show("history")
    elseif cmd == "import" then
        ns.UI:ShowImport()
    elseif cmd == "bericht" or cmd == "export" then
        ns.UI:ShowReport()
    elseif cmd == "sync" then
        ns.SR:Broadcast()
    elseif cmd == "roll" then
        local link = rest:match("(|c.-|Hitem:.-|h|r)") or rest:match("(|Hitem:.-|h.-|h)")
        local itemId = ns.ItemIDFromLink(link)
        if not itemId then
            ns.Print("Bitte ein Item verlinken: /ea roll [Shift-Klick auf Item]")
            return
        end
        ns.Loot:StartRoll({ itemId = itemId, link = link })
        ns.UI:Show("loot")
    elseif cmd == "rolltime" and tonumber(rest) then
        s.rollTime = math.max(5, math.min(120, tonumber(rest)))
        ns.Print("Würfeldauer: " .. s.rollTime .. " Sekunden")
    elseif cmd == "quality" and tonumber(rest) then
        s.minQuality = math.max(0, math.min(5, tonumber(rest)))
        ns.Print("Mindestqualität: " .. s.minQuality)
    elseif cmd == "rw" then
        s.raidWarning = not s.raidWarning
        ns.Print("Schlachtzugswarnung: " .. (s.raidWarning and "an" or "aus"))
    elseif cmd == "ping" then
        ns.Comm:Ping()
    elseif cmd == "diagnose" or cmd == "diag" then
        ns.Comm:Diagnose()
    elseif cmd == "minimap" then
        s.minimapHidden = not s.minimapHidden
        ns.UI:UpdateMinimapButton()
    elseif cmd == "leistung" then
        local p = ns.Members.perf
        local mins = math.max(1, (GetTime() - (p.since or 0)) / 60)
        local kb = 0
        if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
            UpdateAddOnMemoryUsage()
            kb = GetAddOnMemoryUsage("Elternabend") or 0
        end
        ns.Print(string.format("Gildenliste: %d Meldungen vom Server, %d ausgewertet (%.1f pro Minute) – zuletzt %.1f ms, höchstens %.1f ms. Speicher: %.0f KB.",
            p.events, p.scans, p.scans / mins, p.lastMs, p.maxMs, kb))
    elseif cmd == "gildenknopf" then
        s.guildButtonHidden = not s.guildButtonHidden
        ns.GuildButton:Refresh()
        ns.Print("Knopf am Gildenfenster: " .. (s.guildButtonHidden and "aus" or "an"))
    else
        Help()
    end
end
