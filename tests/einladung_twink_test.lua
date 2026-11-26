-- Gildeneinladung: gleich sagen, ob neuer Spieler oder Twink (Idee von Phillipp)

local function Gilde(officer)
    local w = login({
        guild = "Elternabend", officer = officer,
        roster = {
            { name = "Anna Sturmwind", online = true },
            { name = "Beta Lux", online = true, classFile = "PRIEST" },
        },
    })
    w.env.ERR_GUILD_INVITE_S = "Ihr habt %s eingeladen, Eurer Gilde beizutreten."
    w.env.ERR_GUILD_JOIN_S = "%s ist der Gilde beigetreten."
    w.env.ERR_GUILD_DECLINE_S = "%s lehnt Eure Gildeneinladung ab."
    w:advance(30)
    w:clear()
    return w
end

local function Eingeladen(w, name) w:fire("CHAT_MSG_SYSTEM", string.format(w.env.ERR_GUILD_INVITE_S, name)) end
local function Beigetreten(w, name) w:fire("CHAT_MSG_SYSTEM", string.format(w.env.ERR_GUILD_JOIN_S, name)) end

test("Einladung: Leitung markiert „Twink von …“ – gilt, sobald die Person beitritt", function()
    local w = Gilde(true)
    local ns = w.ns
    ns.Board.AmOfficer = function() return true end
    Eingeladen(w, "Clemens Dunkelklinge")
    local d = ns.UI.inviteTwink
    check(d and d:IsShown(), "keine Frage nach der Einladung")
    check(d.von:IsShown(), "„Twink von …“ fehlt für die Leitung")
    ns.Recruit:Mark("Clemens Dunkelklinge", "von", "Beta Lux")
    seen(w, "print", "gilt, sobald die Einladung angenommen ist")
    check(not ns.db.links[ns.NameKey("Clemens Dunkelklinge")], "schon vor dem Beitritt gesetzt")
    Beigetreten(w, "Clemens Dunkelklinge")
    local r = ns.db.links[ns.NameKey("Clemens Dunkelklinge")]
    check(r and r.main == "Beta Lux" and r.k == "o", "Zuordnung fehlt")
    w:advance(3)
    seen(w, "comm", "LNK Clemens Dunkelklinge%^Beta Lux")
    noErrors(w)
end)

test("Einladung: eigener Twink – auch wenn die Antwort erst nach dem Beitritt kommt", function()
    local w = Gilde(false)
    local ns = w.ns
    Eingeladen(w, "Mira Mondschein")
    local d = ns.UI.inviteTwink
    check(d:IsShown() and d.mein:IsShown() and not d.von:IsShown(), "Knöpfe falsch")
    Beigetreten(w, "Mira Mondschein")
    ns.Recruit:Mark("Mira Mondschein", "mein")
    local r = ns.db.links[ns.NameKey("Mira Mondschein")]
    check(r and ns.SameName(r.main, ns.UnitFullName("player")) and r.k == "s", "eigener Twink nicht gemeldet")
    seen(w, "print", "ist als dein Twink gemeldet")
    noErrors(w)
end)

test("Einladung: Leitung sagt „Neuer Spieler“ – steht als Main fest; abgelehnt: nichts", function()
    local w = Gilde(true)
    local ns = w.ns
    ns.Board.AmOfficer = function() return true end
    Eingeladen(w, "Clemens Dunkelklinge")
    ns.Recruit:Mark("Clemens Dunkelklinge", "neu")
    Beigetreten(w, "Clemens Dunkelklinge")
    equal(ns.db.links[ns.NameKey("Clemens Dunkelklinge")].main, "")
    -- abgelehnt: Markierung verfällt
    Eingeladen(w, "Mira Mondschein")
    ns.Recruit:Mark("Mira Mondschein", "von", "Beta Lux")
    w:fire("CHAT_MSG_SYSTEM", string.format(w.env.ERR_GUILD_DECLINE_S, "Mira Mondschein"))
    Beigetreten(w, "Mira Mondschein")
    check(not ns.db.links[ns.NameKey("Mira Mondschein")], "Markierung nach Ablehnung angewandt")
    noErrors(w)
end)

test("Einladung: Frage lässt sich abschalten", function()
    local w = Gilde(true)
    w.ns.SetOpt("inviteTwink", false)
    Eingeladen(w, "Clemens Dunkelklinge")
    check(not (w.ns.UI.inviteTwink and w.ns.UI.inviteTwink:IsShown()), "trotz Schalter gefragt")
    noErrors(w)
end)

test("Einladung: kommt „Ihr habt … eingeladen“ nicht im Chat an, fragt das Addon beim Beitritt (eigene Anfrage)", function()
    local w = Gilde(true)
    local ns = w.ns
    ns.Board.AmOfficer = function() return true end
    -- Anfrage per Flüstern, Befehl zum Kopieren angezeigt – Einladung von Hand, Meldung fehlt
    ns.Recruit:Command("Clemens Dunkelklinge")
    Beigetreten(w, "Clemens Dunkelklinge")
    local d = ns.UI.inviteTwink
    check(d and d:IsShown(), "beim Beitritt nicht gefragt")
    ns.Recruit:Mark("Clemens Dunkelklinge", "von", "Beta Lux")
    equal(ns.db.links[ns.NameKey("Clemens Dunkelklinge")].main, "Beta Lux")
    noErrors(w)
end)

test("Einladung: Meldung oben in der Bildschirmmitte (UI_INFO_MESSAGE) zählt auch", function()
    local w = Gilde(true)
    w:fire("UI_INFO_MESSAGE", 0, string.format(w.env.ERR_GUILD_INVITE_S, "Mira Mondschein"))
    check(w.ns.UI.inviteTwink and w.ns.UI.inviteTwink:IsShown(), "nicht gefragt")
    noErrors(w)
end)
