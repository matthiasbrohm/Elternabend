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

