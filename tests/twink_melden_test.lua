-- Gruppensuche: mit einem anderen eigenen Charakter melden („als Jäger online, kommt mit dem Tank“)

local function Welt()
    local roster = {
        { name = "Anna Sturmwind", online = true, level = 40, classFile = "HUNTER" },
        { name = "Beta Lux", online = true, level = 40, classFile = "MAGE" },
        { name = "Thorin Eisenfuss", online = false, level = 38, classFile = "WARRIOR" },
    }
    local w = login({ guild = "Elternabend", roster = roster })
    w:advance(30)
    w:clear()
    w.roster = roster
    return w
end

local function Roster(w)
    w:fire("GUILD_ROSTER_UPDATE")
    w:advance(5)
end

-- Suchender (wir) bekommt eine Meldung von Beta, die mit ihrem Twink Thorin mitkommen will
test("Twink melden: der Suchende sieht „Beta » Thorin“ und lädt erst ein, wenn Thorin online ist", function()
    local w = Welt()
    local invited
    w.env.C_PartyInfo.InviteUnit = function(name) invited = name end
    w:call(w.ns.Groups.Post, w.ns.Groups, "Die Todesminen", { tank = 1, heal = 0, dd = 2 }, "")
    local id = w.ns.Groups.mine.id
    w:receive("LFGJOIN\t" .. id .. "\ttank\tWARRIOR\tThorin Eisenfuss", "WHISPER", "Beta Lux")
    seen(w, "print", "Beta Lux möchte als Tank mit %(mit Thorin Eisenfuss, loggt dafür um%)")
    local a = w.ns.Groups:Applicants()[1]
    equal(a.alt, "Thorin Eisenfuss")
    -- Einladen, solange Thorin offline ist: nur Bescheid an Beta, keine Einladung
    w:call(w.ns.Groups.Invite, w.ns.Groups, a)
    equal(invited, nil)
    equal(a.state, "relog")
    w:advance(2)
    seen(w, "comm", "LFGANS " .. id .. " relog")
    equal(w.ns.Groups.mine.need.tank, 1)
    -- Thorin kommt online: Hinweis an den Suchenden
    w.roster[2].online = false
    w.roster[3].online = true
    Roster(w)
    seen(w, "print", "Thorin Eisenfuss ist jetzt online")
    w:call(w.ns.Groups.Invite, w.ns.Groups, a)
    equal(invited, "Thorin Eisenfuss")
    equal(a.state, "invited")
    equal(w.ns.Groups.mine.need.tank, 0)
    -- Panel zeigt beides
    w.ns.UI:Show("gruppen")
    noErrors(w)
end)

test("Twink melden: ohne Twink wie bisher sofort einladen", function()
    local w = Welt()
    local invited
    w.env.C_PartyInfo.InviteUnit = function(name) invited = name end
    w:call(w.ns.Groups.Post, w.ns.Groups, "Die Todesminen", { tank = 1, heal = 0, dd = 2 }, "")
    local id = w.ns.Groups.mine.id
    w:receive("LFGJOIN\t" .. id .. "\tdd\tMAGE", "WHISPER", "Beta Lux") -- alte Addon-Version: ohne Twink-Feld
    local a = w.ns.Groups:Applicants()[1]
    equal(a.alt, nil)
    w:call(w.ns.Groups.Invite, w.ns.Groups, a)
    equal(invited, "Beta Lux")
    noErrors(w)
end)

-- Wer sich meldet: Charakter wählen und mit ihm melden
test("Twink melden: Charakterwahl im Reiter Gruppen und Meldung mit Twink", function()
    local w = Welt()
    local me = w.ns.PlayerKey()
    local guild = "Elternabend"
    w.ns.db.myChars[me] = { name = "Anna Sturmwind", classFile = "HUNTER", level = 40, guild = guild }
    w.ns.db.myChars[w.ns.NameKey("Thorin Eisenfuss")] = { name = "Thorin Eisenfuss", classFile = "WARRIOR", level = 38, guild = guild }
    w.ns.db.myChars[w.ns.NameKey("Fremd Twink")] = { name = "Fremd Twink", classFile = "MAGE", level = 60, guild = "Andere Gilde" }
    local chars = w.ns.Groups:MyCharacters()
    equal(#chars, 2) -- nur diese Gilde
    check(chars[1].current, "aktueller Charakter nicht zuerst")
    -- ein Gesuch von Beta
    w:receive("LFG\tg1\tHalle der Thanen\t1\t0\t2\t\t0\t0", "GUILD", "Beta Lux")
    w.ns.UI:Show("gruppen")
    local p = w.ns.UI.panels.gruppen
    w:call(p.Refresh, p)
    equal(p.altButton:GetText(), "Mit: diesem Charakter")
    w:call(p.altButton:GetScript("OnClick"), p.altButton, "LeftButton")
    equal(p.alt, "Thorin Eisenfuss")
    check(p.altButton:GetText():find("Thorin Eisenfuss", 1, true), p.altButton:GetText())
    p.selected = "g1"
    w:call(p.joinButtons.tank:GetScript("OnClick"))
    w:advance(2)
    seen(w, "comm", "LFGJOIN g1 tank WARRIOR Thorin Eisenfuss")
    seen(w, "print", "mit Thorin Eisenfuss%. Zum Einladen loggst du dann um")
    -- Antwort „umloggen“
    w:receive("LFGANS\tg1\trelog", "WHISPER", "Beta Lux")
    seen(w, "print", "logg jetzt auf Thorin Eisenfuss um")
    -- wieder zurück auf den aktuellen Charakter
    w:call(p.altButton:GetScript("OnClick"), p.altButton, "RightButton")
    equal(p.alt, nil)
    noErrors(w)
end)

test("Gruppensuche: Tipp, vorher Discord und Webseite anzusehen", function()
    local w = Welt()
    w.ns.UI:Show("gruppen")
    local p = w.ns.UI.panels.gruppen
    w:call(p.Refresh, p)
    check(p.ownState:GetText():find("Gruppensuche im Discord oder auf der Webseite", 1, true), p.ownState:GetText())
    noErrors(w)
end)
