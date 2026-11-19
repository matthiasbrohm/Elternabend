-- Raid-Reiter: Countdown 5 und 10 Sekunden über Blizzards Countdown

local function Welt(opts)
    local w = login(opts)
    w:advance(30)
    w:clear()
    local runs = {}
    w.env.C_PartyInfo.DoCountdown = function(sec) table.insert(runs, sec) end
    return w, runs
end

local function Knopf(w, text)
    for _, f in ipairs(w.frames) do
        if f:GetText() == text and f:GetScript("OnClick") then return f end
    end
end

test("Countdown: die Knöpfe stehen im Raid-Reiter und starten 5 und 10 Sekunden", function()
    local w, runs = Welt({ guild = "Elternabend", raid = true, leader = true, officer = true })
    w:slash("/ea raid")
    local k5, k10 = Knopf(w, "Countdown 5"), Knopf(w, "10")
    check(k5 and k10, "Knöpfe fehlen")
    k5:Click()
    k10:Click()
    equal(#runs, 2)
    equal(runs[1], 5)
    equal(runs[2], 10)
    noErrors(w)
end)

test("Countdown: ohne Gruppe nur ein Hinweis", function()
    local w, runs = Welt({ guild = "Elternabend" })
    w:call(w.ns.Raid.Countdown, w.ns.Raid, 10)
    equal(#runs, 0)
    seen(w, "print", "erst in einer Gruppe")
    noErrors(w)
end)

test("Countdown: im Schlachtzug nur Leitung und Assistenten", function()
    local w, runs = Welt({ guild = "Elternabend", raid = true })
    w:call(w.ns.Raid.Countdown, w.ns.Raid, 5)
    equal(#runs, 0)
    seen(w, "print", "leitet oder Assistent")
    noErrors(w)
end)

test("Countdown: ohne Countdown im Spiel ein Hinweis statt Fehler", function()
    local w = Welt({ guild = "Elternabend", raid = true, leader = true })
    w.env.C_PartyInfo.DoCountdown = nil
    w:call(w.ns.Raid.Countdown, w.ns.Raid, 5)
    seen(w, "print", "kennt keinen Countdown")
    noErrors(w)
end)
