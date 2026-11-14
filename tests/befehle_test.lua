-- Jeder /ea-Befehl und jeder Reiter läuft ohne Lua-Fehler – als Offizier im Schlachtzug
-- (dann sind alle Reiter sichtbar) und als normales Mitglied allein.

local BEFEHLE = {
    "", "start", "raid", "kind", "kind 10", "da", "knopf", "kindchat", "gruppen", "gruppenhinweis", "ruhm",
    "pause 1", "weiter", "vorbereitung", "berufe", "notizen", "leitung", "klassenliste", "spielzeiten",
    "schritte", "einstellungen", "quiz", "abgleich", "lagerfeuer", "raidgruppen", "gruppentest", "design",
    "kalender", "pinnwand", "gilde", "main", "invite", "einlogtest", "anfragen", "ginv", "taktik",
    "verlauf", "import", "bericht", "roll", "rolltime 15", "quality 3", "rw", "ping", "diagnose",
    "minimap", "leistung", "gildenknopf", "gibtsnicht",
}

local OFFIZIER = { guild = "Elternabend", raid = true, leader = true, officer = true, canInvite = true }
local MITGLIED = { guild = "Elternabend" }

for _, cmd in ipairs(BEFEHLE) do
    test("/ea " .. cmd .. " als Offizier im Raid", function()
        local w = login(OFFIZIER)
        w:advance(30)
        w:slash("/ea " .. cmd)
        w:advance(30)
        noErrors(w)
    end)
    test("/ea " .. cmd .. " als Mitglied allein", function()
        local w = login(MITGLIED)
        w:advance(30)
        w:slash("/ea " .. cmd)
        w:advance(30)
        noErrors(w)
    end)
end

test("jeden Reiter öffnen und wieder schließen", function()
    local w = login(OFFIZIER)
    w:advance(30)
    local UI = w.ns.UI
    for _, key in ipairs({ "start", "mitglieder", "kalender", "pinnwand", "berufe", "gruppen", "notizen",
        "raid", "raidgruppen", "sr", "loot", "history", "taktik", "fame", "gilde", "web", "leitung" }) do
        w:call(UI.Show, UI, key)
        w:advance(2)
    end
    w.env.ElternabendFrame:Hide()
    w:advance(5)
    noErrors(w)
end)
