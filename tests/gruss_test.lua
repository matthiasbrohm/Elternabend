-- Gruß beim Einloggen und Abschied beim Ausloggen im Gildenchat (standardmäßig aus)

local function Gilde(settings)
    local w = login({
        guild = "Elternabend", db = { settings = settings or {} },
        roster = { { name = "Anna Sturmwind", online = true }, { name = "Beta Lux", online = true } },
    })
    return w
end

local function GuildChats(w)
    for _ = 1, 6 do w:call(w.ns.HardwarePulse) end
    local list = {}
    for _, e in ipairs(w.log) do
        if e.kind == "chat" and e.text:find("^GUILD ") then list[#list + 1] = (e.text:gsub("^GUILD ", "")) end
    end
    return list
end

test("Gruß und Abschied: standardmäßig aus, auch „Alles an“ schaltet sie nicht ein", function()
    local w = Gilde()
    w.ns.SetPreset("an")
    w:advance(30)
    w:fire("PLAYER_CAMPING")
    equal(#GuildChats(w), 0)
    check(not w.ns.Opt("hello") and not w.ns.Opt("bye"), "eingeschaltet")
    noErrors(w)
end)

test("Gruß beim Einloggen: Vorgabe oder eigener Text, nicht nach /reload, nicht doppelt", function()
    local w = Gilde({ hello = true, helloText = "Moin Moin, Elternabend!" })
    w:advance(30)
    local chats = GuildChats(w)
    equal(#chats, 1)
    equal(chats[1], "Moin Moin, Elternabend!")
    -- /reload
    w:fire("PLAYER_ENTERING_WORLD", false, true)
    w:advance(30)
    equal(#GuildChats(w), 1)
    -- leerer Text = Vorgabe; kurz danach neu eingeloggt: kein zweiter Gruß
    w.ns.db.settings.helloText = "  "
    equal(w.ns.Greet:HelloText(), w.ns.Greet.DEFAULT_HELLO)
    w:fire("PLAYER_ENTERING_WORLD", true, false)
    w:advance(30)
    equal(#GuildChats(w), 1)
    noErrors(w)
end)

test("Abschied: beim Ausloggen über Spielmenü oder /camp genau einmal", function()
    local w = Gilde({ bye = true, byeText = "Gute Nacht zusammen!" })
    w:advance(30)
    equal(#GuildChats(w), 0)
    w:fire("PLAYER_CAMPING")
    w.ns.Greet:Bye() -- Haken an Logout()
    local chats = GuildChats(w)
    equal(#chats, 1)
    equal(chats[1], "Gute Nacht zusammen!")
    noErrors(w)
end)

test("Abschied: ohne Gilde nichts", function()
    local w = login({ db = { settings = { bye = true, hello = true } } })
    w:advance(30)
    w:fire("PLAYER_CAMPING")
    equal(#GuildChats(w), 0)
    noErrors(w)
end)

test("Einstellungen: Textfeld für Gruß und Abschied", function()
    local w = Gilde()
    w.ns.UI:ShowOptions()
    local d = w.ns.UI.optionsDialog
    check(d.texts and d.texts.helloText and d.texts.byeText, "Textfelder fehlen")
    d.texts.byeText:SetText("Tschüss!")
    d.texts.byeText:GetScript("OnTextChanged")(d.texts.byeText, true)
    equal(w.ns.db.settings.byeText, "Tschüss!")
    equal(w.ns.Greet:ByeText(), "Tschüss!")
    noErrors(w)
end)
