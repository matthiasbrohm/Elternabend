-- Rechtsklick in der Gildenliste: Rang ändern. Das Spiel erlaubt Addons nur /gpromote und /gdemote über einen
-- sicheren Knopf, eine Stufe je Klick. Für mehrere Stufen führt ein kleines Fenster durch die übrigen Klicks.
-- Die Tests spielen das Spiel nach: Der Rang ändert sich „auf dem Server“, die Gildenliste des Clients hinkt
-- nach (höchstens eine Antwort alle zehn Sekunden).

local RANGS = { "Gildenleitung", "Offizier", "Veteran", "Mitglied", "Twink", "Initiand" }

local function Welt(extra)
    local opts = { guild = "Elternabend", officer = true, roster = {
        { name = "Neu Hier", rankIndex = 5, online = true },
        { name = "Alt Dabei", rankIndex = 3, online = true },
        { name = "Chef Sache", rankIndex = 1, online = true },
    } }
    for k, v in pairs(extra or {}) do opts[k] = v end
    local w = login(opts)
    local echt, sicht = {}, {} -- Rang auf dem Server / Rang, den der Client kennt
    for i, m in ipairs(opts.roster) do echt[i], sicht[i] = m.rankIndex, m.rankIndex end
    local function Nummer(name) for i, m in ipairs(opts.roster) do if m.name == name then return i end end end
    w.env.ERR_GUILD_PROMOTE_SSS = "%s hat %s zum Rang %s befördert."
    w.env.ERR_GUILD_DEMOTE_SSS = "%s hat %s zum Rang %s degradiert."
    w.env.GetCVarBool = function() return false end
    w.env.GetCursorPosition = function() return 400, 400 end
    w.env.GetGuildInfo = function(u) if u == "player" then return "Elternabend", RANGS[(opts.myRank or 0) + 1], opts.myRank or 0 end end
    w.env.GetGuildRosterInfo = function(i)
        local m = opts.roster[i]
        if not m then return nil end
        return m.name, RANGS[sicht[i] + 1], sicht[i], 60, "Krieger", "Elwynn", "", "", m.online or false, 0, "WARRIOR"
    end
    w.env.GuildControlGetNumRanks = function() return #RANGS end
    w.env.GuildControlGetRankName = function(i) return RANGS[i] end
    w.env.CanGuildPromote = function() return opts.canPromote ~= false end
    w.env.CanGuildDemote = function() return opts.canPromote ~= false end
    local letzteAntwort = -100
    w.env.C_GuildInfo.GuildRoster = function()
        if w.env.GetTime() - letzteAntwort < 10 then return end -- zu früh: das Spiel verwirft die Anfrage
        letzteAntwort = w.env.GetTime()
        for i = 1, #echt do sicht[i] = echt[i] end
        w:fire("GUILD_ROSTER_UPDATE")
    end
    -- Sichere Knöpfe: Makrotext mitschreiben
    local orig = w.env.CreateFrame
    local function Merken(f) rawset(f, "SetAttribute", function(self, k, v) rawset(self, "attr_" .. k, v) end) return f end
    w.env.CreateFrame = function(kind, name, parent, template, ...)
        local f = orig(kind, name, parent, template, ...)
        return template == "SecureActionButtonTemplate" and Merken(f) or f
    end
    w:advance(30)
    w.env.C_GuildInfo.GuildRoster()
    w:advance(10)
    w:clear()
    w:slash("/ea gilde")
    local p = w.ns.UI.panels.mitglieder
    Merken(p.chainOverlay)
    for _, o in ipairs(p.rankOverlays) do Merken(o) end

    local t = { w = w, p = p, klicks = 0 }
    function t.rang(name) return RANGS[echt[Nummer(name)] + 1] end
    function t.menue(name)
        local e = w.ns.Members.byKey[w.ns.NameKey(name)]
        check(e, "nicht in der Gildenliste: " .. name)
        w:call(p.guildList.onClick, nil, e, "RightButton")
        local zeilen = {}
        for _, b in ipairs(p.ctx.buttons) do
            if b:IsShown() then zeilen[#zeilen + 1] = (b:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
        end
        return zeilen
    end
    -- Klick auf einen sicheren Knopf: erst läuft das Makro (hier: der nachgespielte Server), dann der Rest
    function t.druecke(o)
        local makro = rawget(o, "attr_macrotext")
        local befehl, name = tostring(makro):match("^/(g%a+) (.+)$")
        check(befehl == "gpromote" or befehl == "gdemote", "unerwartetes Makro: " .. tostring(makro))
        local i = Nummer(name)
        local richtung = befehl == "gpromote" and -1 or 1
        local vorher = echt[i]
        -- Rechnet das Spiel vom Rang, den der Client kennt (cache), oder vom echten Rang?
        echt[i] = math.max(1, math.min(#RANGS - 1, (opts.cache and sicht[i] or echt[i]) + richtung))
        t.klicks = t.klicks + 1
        o:Click()
        if opts.meldung and echt[i] ~= vorher then
            w:fire("CHAT_MSG_SYSTEM", string.format(befehl == "gpromote" and w.env.ERR_GUILD_PROMOTE_SSS or w.env.ERR_GUILD_DEMOTE_SSS,
                "Chef Sache", name, RANGS[echt[i] + 1]))
        end
    end
    function t.waehle(text)
        for i, b in ipairs(p.ctx.buttons) do
            if b:IsShown() and b:GetText():find(text, 1, true) then
                for _, o in ipairs(p.rankOverlays) do
                    if o:IsShown() and o.visual == b then t.druecke(o) return true end
                end
                error("kein sicherer Knopf über der Zeile „" .. text .. "“ (Zeile " .. i .. ")")
            end
        end
        error("Zeile fehlt: " .. text)
    end
    -- Auf „Weiter“ klicken, wann immer es angeboten wird
    function t.weiter(sekunden)
        for _ = 1, sekunden * 2 do
            w:advance(0.5)
            if p.chainOverlay:IsShown() and p.chainBox:IsShown() then t.druecke(p.chainOverlay) end
        end
    end
    return t
end

local function hat(zeilen, text)
    for _, z in ipairs(zeilen) do if z == text then return true end end
    return false
end

test("Rang: das Menü bietet alle Ränge an, die ich vergeben darf", function()
    local t = Welt()
    local zeilen = t.menue("Neu Hier")
    for _, r in ipairs({ "Twink", "Mitglied", "Veteran", "Offizier" }) do check(hat(zeilen, "Befördern: " .. r), "fehlt: " .. r) end
    check(not hat(zeilen, "Befördern: Gildenleitung"), "eigener Rang darf nicht angeboten werden")
    zeilen = t.menue("Alt Dabei")
    check(hat(zeilen, "Befördern: Veteran") and hat(zeilen, "Zurückstufen: Twink") and hat(zeilen, "Zurückstufen: Initiand"), "Mitglied: hoch und runter")
    noErrors(t.w)
end)

test("Rang: eine Stufe – ein Klick, kein Fenster", function()
    local t = Welt()
    t.menue("Neu Hier")
    t.waehle("Befördern: Twink")
    equal(t.rang("Neu Hier"), "Twink")
    check(not t.p.chainBox:IsShown(), "Fenster erscheint bei einer einzelnen Stufe")
    seen(t.w, "print", "Neu Hier wird befördert – neuer Rang: Twink")
    t.w:advance(15)
    equal(t.w.ns.Members.byKey[t.w.ns.NameKey("Neu Hier")].rank, "Twink")
    noErrors(t.w)
end)

test("Rang: gleich zum Mitglied – mit Bestätigung des Spiels reichen zwei schnelle Klicks", function()
    local t = Welt({ meldung = true })
    t.menue("Neu Hier")
    t.waehle("Befördern: Mitglied")
    equal(t.rang("Neu Hier"), "Twink")
    check(t.p.chainBox:IsShown(), "Fenster für die zweite Stufe fehlt")
    seen(t.w, "print", "Ziel: Mitglied")
    t.w:advance(0.5)
    check(t.p.chainOverlay:IsShown(), "„Weiter“ ist nach der Bestätigung nicht sofort bereit")
    check(t.p.chainBox.go:GetText():find("Weiter: Befördern zu Mitglied", 1, true), "Beschriftung: " .. t.p.chainBox.go:GetText())
    t.druecke(t.p.chainOverlay)
    t.w:advance(0.5)
    equal(t.rang("Neu Hier"), "Mitglied")
    check(not t.p.chainBox:IsShown(), "Fenster bleibt nach dem Ziel offen")
    seen(t.w, "print", "Neu Hier ist jetzt Mitglied.")
    equal(t.klicks, 2)
    noErrors(t.w)
end)

test("Rang: ohne Bestätigung und mit nachhinkender Gildenliste – nie mehr Klicks als Stufen", function()
    local t = Welt()
    t.menue("Neu Hier")
    t.w.env.C_GuildInfo.GuildRoster() -- eben erst gefragt: die nächste Antwort kommt frühestens in zehn Sekunden
    t.waehle("Befördern: Mitglied")
    t.w:advance(1)
    check(not t.p.chainOverlay:IsShown(), "„Weiter“ ist ohne Bestätigung sofort klickbar")
    t.weiter(8) -- nach drei Sekunden bereit, danach auf die Liste warten
    equal(t.klicks, 2)
    equal(t.rang("Neu Hier"), "Mitglied")
    t.weiter(30)
    equal(t.klicks, 2)
    check(not t.p.chainBox:IsShown(), "Fenster bleibt offen, obwohl das Ziel erreicht ist")
    seen(t.w, "print", "Neu Hier ist jetzt Mitglied.")
    noErrors(t.w)
end)

test("Rang: drei Stufen zum Veteranen – endet genau auf dem Ziel, nie darüber", function()
    for _, meldung in ipairs({ false, true }) do
        local t = Welt({ meldung = meldung })
        t.menue("Neu Hier")
        t.waehle("Befördern: Veteran")
        t.weiter(60)
        equal(t.rang("Neu Hier"), "Veteran")
        equal(t.klicks, 3)
        check(not t.p.chainBox:IsShown(), "Fenster bleibt offen")
        noErrors(t.w)
    end
end)

test("Rang: rechnet das Spiel vom alten Stand, verpufft ein Klick – das Ziel wird trotzdem erreicht", function()
    local t = Welt({ cache = true })
    t.menue("Neu Hier")
    t.waehle("Befördern: Mitglied")
    t.weiter(90)
    equal(t.rang("Neu Hier"), "Mitglied")
    check(not t.p.chainBox:IsShown(), "Fenster bleibt offen")
    noErrors(t.w)
end)

test("Rang: zurückstufen über zwei Stufen", function()
    local t = Welt({ meldung = true })
    t.menue("Alt Dabei")
    t.waehle("Zurückstufen: Initiand")
    equal(t.rang("Alt Dabei"), "Twink")
    t.weiter(5)
    equal(t.rang("Alt Dabei"), "Initiand")
    equal(t.klicks, 2)
    seen(t.w, "print", "Alt Dabei ist jetzt Initiand.")
    noErrors(t.w)
end)

test("Rang: Abbrechen und Kampfbeginn beenden das Fenster", function()
    local t = Welt()
    t.menue("Neu Hier")
    t.waehle("Befördern: Veteran")
    t.p.chainBox.stop:Click()
    check(not t.p.chainBox:IsShown() and not t.p.chainOverlay:IsShown(), "Abbrechen schließt nicht")
    seen(t.w, "print", "Rangwechsel abgebrochen")
    t.weiter(20)
    equal(t.klicks, 1)
    t.w:advance(15)
    t.menue("Neu Hier")
    t.waehle("Befördern: Veteran")
    t.w:fire("PLAYER_REGEN_DISABLED")
    check(not t.p.chainBox:IsShown() and not t.p.chainOverlay:IsShown(), "Kampf schließt nicht")
    seen(t.w, "print", "wegen Kampf abgebrochen")
    noErrors(t.w)
end)

test("Rang: wer nicht befördern darf oder nicht über dem Ziel steht, bekommt keine Rang-Zeilen", function()
    local t = Welt({ canPromote = false })
    for _, z in ipairs(t.menue("Neu Hier")) do check(not z:find("Befördern", 1, true), "Zeile trotz fehlendem Recht: " .. z) end
    local t2 = Welt({ myRank = 1 })
    for _, z in ipairs(t2.menue("Chef Sache")) do check(not z:find("stufen", 1, true) and not z:find("Befördern", 1, true), "Rang-Zeile für Gleichrangige: " .. z) end
    local zeilen = t2.menue("Neu Hier")
    check(hat(zeilen, "Befördern: Veteran") and not hat(zeilen, "Befördern: Offizier"), "Grenze am eigenen Rang")
    noErrors(t.w); noErrors(t2.w)
end)
