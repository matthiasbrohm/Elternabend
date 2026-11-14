-- Grundlagen: Das Addon lädt, startet und läuft eine Stunde ohne Lua-Fehler.

test("alle Dateien der .toc gibt es und sie laden ohne Fehler", function()
    local w = world()
    noErrors(w)
    check(w.ns.UI and w.ns.Comm and w.ns.Members, "Module fehlen im Namensraum")
end)

test("Einloggen ohne Gilde", function()
    local w = login()
    w:advance(120)
    noErrors(w)
end)

test("Einloggen in der Gilde: eine Stunde ohne Fehler", function()
    local w = login({ guild = "Elternabend" })
    w:advance(3600)
    noErrors(w)
end)

test("Einloggen in einer Gruppe: eine Stunde ohne Fehler", function()
    local w = login({ guild = "Elternabend", group = true })
    w:advance(3600)
    noErrors(w)
end)

test("Einloggen als Offizier im Schlachtzug: eine Stunde ohne Fehler", function()
    local w = login({ guild = "Elternabend", raid = true, leader = true, officer = true, canInvite = true })
    w:advance(3600)
    noErrors(w)
end)

test("beim Einloggen meldet das Addon seine Version in der Gilde", function()
    local w = login({ guild = "Elternabend", version = "9.9.9" })
    w:advance(20)
    seen(w, "comm", "^GUILD VER 9%.9%.9")
end)

test("gespeicherte Daten überstehen ein /reload", function()
    local w = login({ guild = "Elternabend" })
    w:advance(60)
    local db = w.env.ElternabendDB
    check(type(db) == "table" and db.settings, "ElternabendDB wurde nicht angelegt")
    local w2 = login({ guild = "Elternabend", db = db })
    w2:advance(60)
    noErrors(w2)
end)
