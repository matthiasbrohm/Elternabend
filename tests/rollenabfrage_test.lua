-- Knopf „Rollenabfrage“ in der Raid-Übersicht: startet Blizzards Abfrage für die ganze Gruppe.

local function Welt(opts)
    local w = login(opts)
    w:advance(30)
    w:clear()
    local gestartet = 0
    w.env.InitiateRolePoll = function() gestartet = gestartet + 1 end
    return w, function() return gestartet end
end

local RAID = { guild = "Elternabend", raid = true, leader = true, officer = true }

test("Rollenabfrage: der Knopf steht im Raid-Reiter und startet die Abfrage", function()
    local w, gestartet = Welt(RAID)
    w:slash("/ea raid")
    local knopf
    for _, f in ipairs(w.frames) do
        if f:GetText() == "Rollenabfrage" and f:GetScript("OnClick") then knopf = f end
    end
    check(knopf, "Knopf „Rollenabfrage“ fehlt")
    knopf:Click()
    equal(gestartet(), 1)
    noErrors(w)
end)

test("Rollenabfrage: ohne Gruppe nur ein Hinweis", function()
    local w, gestartet = Welt({ guild = "Elternabend", officer = true })
    w:call(w.ns.Raid.RolePoll, w.ns.Raid)
    equal(gestartet(), 0)
    seen(w, "print", "erst in einer Gruppe")
    noErrors(w)
end)

test("Rollenabfrage: wer nicht leitet, darf sie nicht starten", function()
    local w, gestartet = Welt({ guild = "Elternabend", raid = true })
    w:call(w.ns.Raid.RolePoll, w.ns.Raid)
    equal(gestartet(), 0)
    seen(w, "print", "leitet oder Assistent")
    noErrors(w)
end)

test("Rollenabfrage: Client ohne die Funktion – Hinweis statt Fehler", function()
    local w, gestartet = Welt(RAID)
    w.env.InitiateRolePoll = nil
    rawset(w.env, "InitiateRolePoll", false)
    w:call(w.ns.Raid.RolePoll, w.ns.Raid)
    equal(gestartet(), 0)
    seen(w, "print", "kennt keine Rollenabfrage")
    noErrors(w)
end)

test("Rollenabfrage: Antworten ziehen die Übersicht nach", function()
    local w = Welt(RAID)
    w:fire("PLAYER_ROLES_ASSIGNED")
    noErrors(w)
end)
