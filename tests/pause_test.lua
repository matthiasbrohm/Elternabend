-- Raid-Pause: Ende kommt sofort an (an der Warteschlange vorbei, notfalls über die Chatzeile), „Weiter geht's!“ nur kurz

local function Raid(lead)
    local w = login({ guild = "Elternabend", raid = true, leader = lead })
    w:advance(30)
    local ns = w.ns
    local me = ns.UnitFullName("player")
    ns.IsTrusted = function(name) return lead and ns.SameName(name, me) or (not lead and ns.SameName(name, "Beta Lux")) end
    w:clear()
    return w
end

test("Pause: „Beenden“ überholt eine volle Warteschlange", function()
    local w = Raid(true)
    local ns = w.ns
    ns.Pause:Start(5)
    w:advance(1)
    seen(w, "comm", "PAUSE 300")
    -- Viel los in der Gruppe: 30 Nachrichten warten
    for i = 1, 30 do ns.Comm:Send("TEST", tostring(i)) end
    w:clear()
    ns.Pause:End()
    w:advance(0.2)
    seen(w, "comm", "PAUSEEND")
    notSeen(w, "comm", "TEST 30")
    noErrors(w)
end)

test("Pause: Chatzeile der Leitung schließt sofort, „Weiter geht's!“ verschwindet nach 5 Sekunden", function()
    local w = Raid(false)
    local P = w.ns.Pause
    w:receive("PAUSE\t300", "RAID", "Beta Lux")
    check(P:IsRunning(), "Pause läuft nicht")
    check(P.frame:IsShown(), "Fenster fehlt")
    -- Nur die Chatzeile kommt an (Addon-Nachricht steckt noch fest)
    w:fire("CHAT_MSG_RAID_WARNING", "[Elternabend] Pause vorbei – weiter geht's!", "Beta Lux")
    check(not P:IsRunning(), "Pause läuft noch")
    check(P.frame:IsShown() and P.frame.close:IsShown(), "„Weiter geht's!“ mit OK fehlt")
    w:advance(6)
    check(not P.frame:IsShown(), "Fenster nach 6 Sekunden noch offen")
    -- Fremde dürfen die Pause nicht beenden
    w:receive("PAUSE\t300", "RAID", "Beta Lux")
    w:fire("CHAT_MSG_RAID", "[Elternabend] Pause vorbei – weiter geht's!", "Greta Glutherz")
    check(P:IsRunning(), "Fremder hat die Pause beendet")
    -- OK schließt sofort
    w:receive("PAUSEEND", "RAID", "Beta Lux")
    P.frame.close:Click()
    check(not P.frame:IsShown(), "OK schließt nicht")
    noErrors(w)
end)
