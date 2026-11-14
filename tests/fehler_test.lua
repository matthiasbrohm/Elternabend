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

