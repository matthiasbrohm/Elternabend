-- Kurz ein- und gleich wieder ausgeloggt (Twink-Wechsel): keine Flüster-Antworten mehr an ihn und keine
-- Zeilen „Momentan ist kein Spieler mit dem Namen … online.“ im Chat

local function Gilde()
    local w = login({
        guild = "Elternabend",
        roster = {
            { name = "Anna Sturmwind", online = true },
            { name = "Gimli Eisenhuf", online = true },
        },
    })
    w:advance(30)
    w:clear()
    return w
end

test("Ausgeloggt: Flüstern an ihn wird verworfen, nach dem Wiedereinloggen geht es wieder", function()
    local w = Gilde()
    local C = w.ns.Comm
    w:fire("CHAT_MSG_SYSTEM", "Gimli Eisenhuf ist jetzt offline.")
    C:Send("VER", "1.0", "WHISPER", "Gimli Eisenhuf")
    w:advance(2)
    notSeen(w, "comm", "WHISPER Gimli Eisenhuf")
    -- wieder da (Systemmeldung oder eine Addon-Nachricht von ihm)
    w:fire("CHAT_MSG_SYSTEM", "|Hplayer:Gimli Eisenhuf|h[Gimli Eisenhuf]|h ist jetzt online.")
    C:Send("VER", "1.0", "WHISPER", "Gimli Eisenhuf")
    w:advance(2)
    seen(w, "comm", "WHISPER Gimli Eisenhuf")
    noErrors(w)
end)

test("Ausgeloggt: „kein Spieler online“ zu eigenen Addon-Nachrichten wird verschluckt, sonst nicht", function()
    local w = Gilde()
    local C = w.ns.Comm
    C:Send("VER", "1.0", "WHISPER", "Gimli Eisenhuf")
    w:advance(2)
    seen(w, "comm", "WHISPER Gimli Eisenhuf")
    local line = "Momentan ist kein Spieler mit dem Namen 'Gimli Eisenhuf' online."
    equal(w:chatLine("CHAT_MSG_SYSTEM", line), nil)
    -- danach gilt er als ausgeloggt: weitere Antworten gehen gar nicht erst raus
    w:clear()
    C:Send("PONG", "x", "WHISPER", "Gimli Eisenhuf")
    w:advance(2)
    notSeen(w, "comm", "WHISPER Gimli Eisenhuf")
    -- jemand, dem das Addon nichts geschickt hat: Meldung bleibt
    local other = "Momentan ist kein Spieler mit dem Namen 'Nox Thundercrush' online."
    equal(w:chatLine("CHAT_MSG_SYSTEM", other), other)
    noErrors(w)
end)
