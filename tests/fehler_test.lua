-- Kleine Fehler, die beim Durchsehen aufgefallen sind – jeweils mit dem Fall, an dem man es sieht.

local function Gruppe(extra)
    local opts = {
        guild = "Elternabend", officer = true, group = true, party = { "Beta Lux", "Cora Wind" },
        groupLeader = "Beta Lux",
        roster = {
            { name = "Anna Sturmwind", online = true },
            { name = "Beta Lux", online = true },
            { name = "Cora Wind", online = true },
        },
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    local w = login(opts)
    w:advance(30)
    w:clear()
    return w
end

-- Begrüßung ----------------------------------------------------------------------------------------------
test("Begrüßung nur einmal pro Account, nicht auf jedem Twink", function()
    local w = login({ guild = "Elternabend" })
    w:advance(30)
    seen(w, "window", "^ElternabendFrame$")
    local twink = login({ guild = "Elternabend", name = "Zwergi", surname = "Stein", db = w.env.ElternabendDB })
    twink:advance(30)
    notSeen(twink, "window", "^ElternabendFrame$")
    noErrors(twink)
end)

-- Gildenanfragen per Flüstern ------------------------------------------------------------------------------
local function Whisper(w, msg) w:fire("CHAT_MSG_WHISPER", msg, "Fremder Gast") w:advance(1) end

test("„Gilde heute Abend?“ ist keine Gildenanfrage", function()
    local w = Gruppe({ canInvite = true })
    Whisper(w, "Gilde heute Abend?")
    notSeen(w, "window", "Gildenanfrage")
    notSeen(w, "sound")
    equal(#w.ns.Recruit.queue, 0, "Anfragen")
end)

test("„ginv“, „ginv bitte“, „Ginv!“ und „gilde?“ sind Gildenanfragen", function()
    for _, msg in ipairs({ "ginv", "ginv bitte", "Ginv!", "gilde?", "gildeninvite pls" }) do
        local w = Gruppe({ canInvite = true })
        Whisper(w, msg)
        equal(#w.ns.Recruit.queue, 1, "Anfragen nach „" .. msg .. "“")
    end
end)

test("ohne Einladerecht: Hinweis nur bei einer echten Anfrage", function()
    local w = Gruppe()
    Whisper(w, "Gilde heute Abend?")
    notSeen(w, "print", "möchte in die Gilde")
    Whisper(w, "ginv")
    seen(w, "print", "möchte in die Gilde")
end)

-- Würfeln ---------------------------------------------------------------------------------------------------
local LINK = "|cffa335ee|Hitem:30904::::::::70:::::|h[Savior's Grasp]|h|r"

test("Soft-Reserve-Würfeln nur von der Leitung: ein Mitspieler löst keinen Alarm aus", function()
    local w = Gruppe()
    w.ns.SR:SetEntries({ { itemId = 30904, name = "Anna Sturmwind", plus = 0 } }, "Test")
    w:receive("ROLL\t" .. LINK .. "\t20", "PARTY", "Cora Wind")
    notSeen(w, "print", "Soft%-Reserve wird ausgewürfelt")
    notSeen(w, "sound")
    w:receive("ROLL\t" .. LINK .. "\t20", "PARTY", "Beta Lux")
    seen(w, "print", "Soft%-Reserve wird ausgewürfelt")
    noErrors(w)
end)

test("Vergabe nur von der Leitung: ein Mitspieler markiert nichts als erhalten", function()
    local w = Gruppe()
    w.ns.SR:SetEntries({ { itemId = 30904, name = "Anna Sturmwind", plus = 0 } }, "Test")
    w:receive("AWARD\t" .. LINK .. "\tAnna Sturmwind", "PARTY", "Cora Wind")
    check(not w.ns.SR:GetReservers(30904)[1].won, "als erhalten markiert")
    w:receive("AWARD\t" .. LINK .. "\tAnna Sturmwind", "PARTY", "Beta Lux")
    check(w.ns.SR:GetReservers(30904)[1].won, "nicht als erhalten markiert")
end)

test("Plündermeister ohne Leitungsrang darf würfeln lassen", function()
    local w = Gruppe()
    w.env.C_PartyInfo = { GetLootMethod = function() return "master", 2 end } -- party2 = Cora
    w.ns.SR:SetEntries({ { itemId = 30904, name = "Anna Sturmwind", plus = 0 } }, "Test")
    w:receive("ROLL\t" .. LINK .. "\t20", "PARTY", "Cora Wind")
    seen(w, "print", "Soft%-Reserve wird ausgewürfelt")
    noErrors(w)
end)

-- /ea sync -----------------------------------------------------------------------------------------------------
test("/ea sync schickt die Soft-Reserves an die Gruppe (wie in Hilfe und README)", function()
    local w = Gruppe({ leader = true, groupLeader = "Anna Sturmwind" })
    w.ns.SR:SetEntries({ { itemId = 30904, name = "Beta Lux", plus = 0 } }, "Test")
    w:slash("/ea sync")
    w:advance(5)
    seen(w, "comm", "SRS")
    noErrors(w)
end)

test("/ea abgleich zeigt weiter den Stand der Mac-App", function()
    local w = Gruppe()
    w:slash("/ea abgleich")
    check(#w:entries("print") > 0, "keine Ausgabe")
    notSeen(w, "comm", "SRS")
    noErrors(w)
end)
