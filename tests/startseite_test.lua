-- Startseite: unter der Begrüßung steht die Gildeninformation aus dem Spiel, darunter die Nachricht des Tages –
-- beide in einem Feld mit Rollbalken. Die Gildeninformation muss abgefragt werden; das Spiel kann das ablehnen.

local function Welt(extra)
    local opts = { guild = "Elternabend", roster = { { name = "Anna Sturmwind", online = true } } }
    for k, v in pairs(extra or {}) do opts[k] = v end
    local w = login(opts)
    local t = { w = w, abfragen = 0, text = opts.info }
    w.env.C_GuildInfo.GetInfoText = function()
        t.abfragen = t.abfragen + 1
        if opts.abgelehnt then w:fire("ADDON_ACTION_BLOCKED", "Elternabend", "C_GuildInfo.GetInfoText()") return nil end
        return t.text
    end
    w:advance(40)
    w:clear()
    w.ns.UI:Show("start")
    t.p = w.ns.UI.panels.start
    function t.neu() w:call(t.p.Refresh, t.p) end
    return t
end

test("Startseite: die Gildeninformation steht unter der Begrüßung", function()
    local t = Welt({ info = "Raids ab 21 Uhr.\nDiscord: discord.gg/elternabend\nBitte Twinks eintragen." })
    equal(t.p.about.body, "Raids ab 21 Uhr.\nDiscord: discord.gg/elternabend\nBitte Twinks eintragen.")
    equal(t.w.ns.Info:GuildText(), t.p.about.body)
    check(t.abfragen >= 1, "das Spiel wurde nicht gefragt")
    noErrors(t.w)
end)

test("Startseite: ohne Gildeninformation bleibt der Vorstellungstext", function()
    for _, info in ipairs({ "", "   " }) do
        local t = Welt({ info = info })
        equal(t.p.about.body, t.w.ns.Info.GUILD.about)
        noErrors(t.w)
    end
    local t = Welt({}) -- das Spiel liefert gar nichts
    equal(t.p.about.body, t.w.ns.Info.GUILD.about)
    noErrors(t.w)
end)

test("Startseite: geänderte Gildeninformation erscheint nach spätestens 30 Sekunden, gefragt wird nicht öfter", function()
    local t = Welt({ info = "Alt" })
    local vorher = t.abfragen
    t.text = "Neu"
    t.neu(); t.neu(); t.neu()
    equal(t.abfragen, vorher)
    equal(t.p.about.body, "Alt")
    t.w:advance(31)
    t.neu()
    equal(t.abfragen, vorher + 1)
    equal(t.p.about.body, "Neu")
    noErrors(t.w)
end)

test("Startseite: lehnt das Spiel die Abfrage ab, wird nicht weiter gefragt – der gemerkte Text bleibt", function()
    local t = Welt({ info = "Gemerkt", abgelehnt = true })
    equal(t.abfragen, 1)
    equal(t.w.ns.db.settings.guildTextBlocked, t.w.ns.VERSION)
    equal(t.p.about.body, t.w.ns.Info.GUILD.about)
    t.w:advance(120)
    t.neu(); t.w:advance(60); t.neu()
    equal(t.abfragen, 1)
    noErrors(t.w)
end)

test("Startseite: im Kampf und während einer Addon-Sperre wird nicht gefragt", function()
    local t = Welt({ info = "Text" })
    local vorher = t.abfragen
    t.w.env.InCombatLockdown = function() return true end
    t.w:advance(40); t.neu()
    equal(t.abfragen, vorher)
    t.w.env.InCombatLockdown = function() return false end
    t.w.env.Enum = { AddOnRestrictionType = { Combat = 0, Encounter = 1 } }
    t.w.env.C_RestrictedActions = { IsAddOnRestrictionActive = function(kind) return kind == 1 end }
    t.w:advance(40); t.neu()
    equal(t.abfragen, vorher)
    t.w.env.C_RestrictedActions = { IsAddOnRestrictionActive = function() return false end }
    t.w:advance(40); t.neu()
    equal(t.abfragen, vorher + 1)
    noErrors(t.w)
end)

test("Startseite: fremde Sperrmeldungen schalten die Abfrage nicht ab", function()
    local t = Welt({ info = "Text" })
    t.w:fire("ADDON_ACTION_BLOCKED", "AnderesAddon", "C_GuildInfo.GetInfoText()")
    t.w:fire("ADDON_ACTION_BLOCKED", "Elternabend", "CastSpellByName()")
    check(not t.w.ns.db.settings.guildTextBlocked, "fälschlich abgeschaltet")
    noErrors(t.w)
end)

test("Startseite: Nachricht des Tages im Rollfeld, ohne Nachricht ein Hinweis", function()
    local t = Welt({ info = "Text" })
    check(t.p.motdScroll:IsShown() and not t.p.motd:IsShown(), "Rollfeld der Nachricht fehlt")
    check(t.p.motdScroll.body:find("Gerade keine Nachricht des Tages", 1, true), "Hinweis fehlt: " .. tostring(t.p.motdScroll.body))
    t.w:fire("GUILD_MOTD", "Neuer Raid am 19.11. geplant. Gerne anmelden :-)")
    t.w:advance(1)
    equal(t.p.motdScroll.body, "Neuer Raid am 19.11. geplant. Gerne anmelden :-)")
    noErrors(t.w)
end)

test("Startseite: ohne Gilde der Vorstellungstext und der Beitritt statt der Nachricht", function()
    local w = login({})
    local abfragen = 0
    w.env.C_GuildInfo.GetInfoText = function() abfragen = abfragen + 1 return "x" end
    w:advance(40)
    w.ns.UI:Show("start")
    local p = w.ns.UI.panels.start
    equal(p.about.body, w.ns.Info.GUILD.about)
    check(p.motd:IsShown() and not p.motdScroll:IsShown(), "Beitritt wird nicht gezeigt")
    check(p.joinBtn:IsShown(), "Knopf zum Beitreten fehlt")
    equal(abfragen, 0)
    noErrors(w)
end)

test("Startseite: in einer anderen Gilde steht der Vorstellungstext, gefragt wird nicht", function()
    local w = login({ guild = "Andere Gilde", roster = { { name = "Bert", online = true } } })
    local abfragen = 0
    w.env.C_GuildInfo.GetInfoText = function() abfragen = abfragen + 1 return "Text der anderen Gilde" end
    w:advance(40)
    w.ns.UI:Show("start")
    local p = w.ns.UI.panels.start
    equal(p.about.body, w.ns.Info.GUILD.about)
    equal(abfragen, 0)
    noErrors(w)
end)

test("Startseite: ein leerer Text vor dem Laden der Gildenliste löscht den gemerkten nicht", function()
    local t = Welt({ info = "Gemerkt" })
    local list = t.w.ns.Members.list
    t.w.ns.Members.list = {}
    t.text = ""
    t.w:advance(31); t.neu()
    equal(t.p.about.body, "Gemerkt")
    t.w.ns.Members.list = list
    t.w:advance(31); t.neu()
    equal(t.p.about.body, t.w.ns.Info.GUILD.about) -- Liste da und Text leer: die Leitung hat ihn gelöscht
    noErrors(t.w)
end)
