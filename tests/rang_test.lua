-- Rechtsklick in der Gildenliste: Rang ändern. Eine Stufe über den sicheren Knopf (/gpromote), mehrere Stufen
-- direkt über C_GuildInfo.SetGuildRankOrder – und zurück auf einzelne Stufen, wenn das Spiel das ablehnt.

local RANGS = { "Gildenleitung", "Offizier", "Veteran", "Mitglied", "Twink", "Initiand" }

local function Welt(extra)
    local opts = { guild = "Elternabend", officer = true, roster = {
        { name = "Neu Hier", rank = "Initiand", rankIndex = 5, online = true, guid = "Player-1-0000A" },
        { name = "Alt Dabei", rank = "Mitglied", rankIndex = 3, online = true, guid = "Player-1-0000B" },
        { name = "Chef Sache", rank = "Offizier", rankIndex = 1, online = true, guid = "Player-1-0000C" },
    } }
    for k, v in pairs(extra or {}) do opts[k] = v end
    local w = login(opts)
    local roster = opts.roster
    w.env.GetGuildInfo = function(u) if u == "player" then return "Elternabend", "Gildenleitung", opts.myRank or 0 end end
    w.env.GetGuildRosterInfo = function(i)
        local m = roster[i]
        if not m then return nil end
        return m.name, m.rank, m.rankIndex, 60, "Krieger", "Elwynn", "", "", m.online or false, 0, "WARRIOR",
            0, 0, false, false, 0, m.guid
    end
    w.env.GetCursorPosition = function() return 400, 400 end
    w.env.GuildControlGetNumRanks = function() return #RANGS end
    w.env.GuildControlGetRankName = function(i) return RANGS[i] end
    w.env.CanGuildPromote = function() return opts.canPromote ~= false end
    w.env.CanGuildDemote = function() return opts.canPromote ~= false end
    local gesetzt = {}
    w.env.C_GuildInfo.SetGuildRankOrder = function(guid, order)
        if opts.blockiert then w:fire("ADDON_ACTION_FORBIDDEN", "Elternabend", "C_GuildInfo.SetGuildRankOrder()") return end
        table.insert(gesetzt, guid .. "=" .. order)
        for _, m in ipairs(roster) do if m.guid == guid then m.rankIndex, m.rank = order - 1, RANGS[order] end end
    end
    if opts.ohneDirekt then w.env.C_GuildInfo.SetGuildRankOrder = nil end
    local anfragen = 0
    w.env.C_GuildInfo.GuildRoster = function() anfragen = anfragen + 1 w:fire("GUILD_ROSTER_UPDATE") end
    w:advance(30)
    w:fire("GUILD_ROSTER_UPDATE")
    w:advance(10)
    w:clear()
    w:slash("/ea gilde")
    local p = w.ns.UI.panels.mitglieder
    local function Menue(name)
        local e = w.ns.Members.byKey[w.ns.NameKey(name)]
        check(e, "nicht in der Gildenliste: " .. name)
        w:call(p.guildList.onClick, nil, e, "RightButton")
        local zeilen = {}
        for _, b in ipairs(p.ctx.buttons) do
            if b:IsShown() then zeilen[#zeilen + 1] = (b:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
        end
        return zeilen
    end
    local function Klick(text)
        for _, b in ipairs(p.ctx.buttons) do
            if b:IsShown() and b:GetText():find(text, 1, true) then b:Click() return true end
        end
        return false
    end
    return w, Menue, Klick, gesetzt, function() return anfragen end
end

local function hat(zeilen, text)
    for _, z in ipairs(zeilen) do if z == text then return true end end
    return false
end

test("Rang: vom Initianden gleich zum Mitglied – ein Klick setzt den Zielrang direkt", function()
    local w, Menue, Klick, gesetzt = Welt()
    local zeilen = Menue("Neu Hier")
    check(hat(zeilen, "Befördern: Twink"), "eine Stufe fehlt")
    check(hat(zeilen, "Befördern: Mitglied"), "zwei Stufen fehlen")
    check(hat(zeilen, "Befördern: Offizier"), "höchster erlaubter Rang fehlt")
    check(not hat(zeilen, "Befördern: Gildenleitung"), "eigener Rang darf nicht angeboten werden")
    check(Klick("Befördern: Mitglied"), "Zeile nicht anklickbar")
    equal(gesetzt[1], "Player-1-0000A=4")
    seen(w, "print", "Neu Hier wird befördert – neuer Rang: Mitglied")
    w:advance(5)
    equal(w.ns.Members.byKey[w.ns.NameKey("Neu Hier")].rank, "Mitglied")
    noErrors(w)
end)

test("Rang: eine Stufe bleibt beim sicheren Knopf, kein direkter Aufruf", function()
    local w, Menue, Klick, gesetzt = Welt()
    Menue("Neu Hier")
    Klick("Befördern: Twink")
    equal(#gesetzt, 0)
    noErrors(w)
end)

test("Rang: zurückstufen geht ebenfalls über mehrere Stufen", function()
    local w, Menue, Klick, gesetzt = Welt()
    local zeilen = Menue("Alt Dabei")
    check(hat(zeilen, "Befördern: Veteran") and hat(zeilen, "Befördern: Offizier"), "Beförderungen fehlen")
    check(hat(zeilen, "Zurückstufen: Twink") and hat(zeilen, "Zurückstufen: Initiand"), "Zurückstufungen fehlen")
    Klick("Zurückstufen: Initiand")
    equal(gesetzt[1], "Player-1-0000B=6")
    seen(w, "print", "Alt Dabei wird zurückgestuft – neuer Rang: Initiand")
    noErrors(w)
end)

test("Rang: lehnt das Spiel den direkten Aufruf ab, gibt es danach wieder nur einzelne Stufen", function()
    local w, Menue, Klick, gesetzt = Welt({ blockiert = true })
    check(hat(Menue("Neu Hier"), "Befördern: Mitglied"), "zwei Stufen fehlen vor dem ersten Versuch")
    Klick("Befördern: Mitglied")
    equal(#gesetzt, 0)
    seen(w, "print", "lässt Addons den Rang nicht direkt setzen")
    check(w.ns.db.settings.rankDirectBlocked == true, "Ablehnung nicht gemerkt")
    local zeilen = Menue("Neu Hier")
    check(hat(zeilen, "Befördern: Twink"), "eine Stufe fehlt")
    check(not hat(zeilen, "Befördern: Mitglied"), "zwei Stufen werden weiter angeboten")
    noErrors(w)
end)

test("Rang: Client ohne die Funktion oder ohne GUID – nur einzelne Stufen", function()
    local w, Menue = Welt({ ohneDirekt = true })
    local zeilen = Menue("Neu Hier")
    check(hat(zeilen, "Befördern: Twink") and not hat(zeilen, "Befördern: Mitglied"), "ohne Funktion")
    noErrors(w)
end)

test("Rang: fremde Blockade-Meldungen und andere Addons ändern nichts", function()
    local w, Menue = Welt()
    w:fire("ADDON_ACTION_FORBIDDEN", "AnderesAddon", "C_GuildInfo.SetGuildRankOrder()")
    w:fire("ADDON_ACTION_BLOCKED", "Elternabend", "CastSpellByName()")
    check(not w.ns.db.settings.rankDirectBlocked, "fälschlich als blockiert gemerkt")
    check(hat(Menue("Neu Hier"), "Befördern: Mitglied"), "zwei Stufen fehlen")
    noErrors(w)
end)

test("Rang: wer nicht befördern darf oder nicht über dem Ziel steht, bekommt keine Rang-Zeilen", function()
    local w, Menue = Welt({ canPromote = false })
    for _, z in ipairs(Menue("Neu Hier")) do check(not z:find("Befördern", 1, true), "Zeile trotz fehlendem Recht: " .. z) end
    local w2, Menue2 = Welt({ myRank = 1 })
    for _, z in ipairs(Menue2("Chef Sache")) do check(not z:find("stufen", 1, true) and not z:find("Befördern", 1, true), "Rang-Zeile für Gleichrangige: " .. z) end
    local zeilen = Menue2("Neu Hier")
    check(hat(zeilen, "Befördern: Veteran") and not hat(zeilen, "Befördern: Offizier"), "Grenze am eigenen Rang")
    noErrors(w); noErrors(w2)
end)

test("Rang: nach dem Wechsel wird die Gildenliste mehrmals nachgefragt, bis der Rang da ist", function()
    local w, Menue, Klick, _, anfragen = Welt()
    -- Die Liste antwortet zunächst mit dem alten Stand (Anfragen werden verworfen)
    local alt = w.env.GetGuildRosterInfo
    local zeigtNeu = false
    w.env.GetGuildRosterInfo = function(i)
        local r = { alt(i) }
        if i == 1 and not zeigtNeu then r[2], r[3] = "Initiand", 5 end
        return unpack(r, 1, 17)
    end
    Menue("Neu Hier")
    local vorher = anfragen()
    Klick("Befördern: Mitglied")
    w:advance(6)
    check(anfragen() - vorher >= 2, "nur " .. (anfragen() - vorher) .. " Anfrage(n) in 6 Sekunden")
    zeigtNeu = true
    w:advance(4)
    local stand = anfragen()
    w:advance(20)
    check(anfragen() - stand <= 1, "fragt weiter, obwohl der Rang angekommen ist")
    equal(w.ns.Members.byKey[w.ns.NameKey("Neu Hier")].rank, "Mitglied")
    noErrors(w)
end)
