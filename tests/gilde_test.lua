-- Twinks und Mains im Chat, Antworten im Protokoll, Schalter aus „Einstellungen“.

-- Eine kleine Gilde: Beta Lux ist Main, Alpha Elternabend sein Twink (Offiziersnotiz „Beta Lux“)
local function Gilde(extra)
    local opts = {
        guild = "Elternabend", officer = true,
        roster = {
            { name = "Anna Sturmwind", online = true },
            { name = "Beta Lux", online = true, classFile = "PRIEST" },
            { name = "Alpha Elternabend", online = true, officerNote = "Beta Lux" },
        },
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    local w = login(opts)
    w:advance(30) -- Gildenliste ist nach 8 s eingelesen
    return w
end

local ONLINE = "|Hplayer:Alpha Elternabend|h[Alpha Elternabend]|h ist jetzt online."

-- Twinks im Chat ------------------------------------------------------------------------------------
test("Einlog-Meldung eines Twinks bekommt den Main dazu", function()
    local w = Gilde()
    local line = w:chatLine("CHAT_MSG_SYSTEM", ONLINE)
    check(line and line:find("%(Twink von .*Beta.*%)$"), "kein Main an der Einlog-Meldung: " .. tostring(line))
    noErrors(w)
end)

test("Einlog-Meldung eines Mains bleibt, wie sie ist", function()
    local w = Gilde()
    local msg = "|Hplayer:Beta Lux|h[Beta Lux]|h ist jetzt online."
    equal(w:chatLine("CHAT_MSG_SYSTEM", msg), msg)
end)

test("Gildenchat: vor Nachrichten von Twinks steht der Vorname des Mains", function()
    local w = Gilde()
    local line = w:chatLine("CHAT_MSG_GUILD", "Wer kommt mit?", "Alpha Elternabend")
    check(line and line:find("Beta") and line:find("Wer kommt mit%?$"), "kein Main vor der Nachricht: " .. tostring(line))
end)

test("Gildenchat: Nachrichten von Mains bleiben, wie sie sind", function()
    local w = Gilde()
    equal(w:chatLine("CHAT_MSG_GUILD", "Hallo", "Beta Lux"), "Hallo")
end)

test("Schalter aus: kein Main an Einlog-Meldung und im Gildenchat", function()
    local w = Gilde()
    w.ns.SetOpt("chatOnline", false)
    w.ns.SetOpt("chatMain", false)
    equal(w:chatLine("CHAT_MSG_SYSTEM", ONLINE), ONLINE)
    equal(w:chatLine("CHAT_MSG_GUILD", "Wer kommt mit?", "Alpha Elternabend"), "Wer kommt mit?")
end)

-- Protokoll: worauf andere Addons warten ------------------------------------------------------------
test("HELLO aus der Gruppe wird mit der eigenen Version beantwortet", function()
    local w = Gilde({ group = true, version = "4.16.0" })
    w:clear()
    w:receive("HELLO\t4.15.0", "PARTY", "Beta Lux")
    w:advance(5)
    seen(w, "comm", "^WHISPER Beta Lux VER 4%.16%.0")
end)

test("eine neuere Version in der Gilde wird einmal gemeldet", function()
    local w = Gilde({ version = "4.15.0" })
    w:clear()
    w:receive("VER\t4.20.0", "GUILD", "Beta Lux")
    w:receive("VER\t4.20.0", "GUILD", "Alpha Elternabend")
    seen(w, "print", "Neue Version 4%.20%.0")
    equal(#w:entries("print"), 1, "Zahl der Hinweise")
end)

-- Töne ------------------------------------------------------------------------------------------------
test("neuer Auftrag: Ton und Chatzeile", function()
    local w = Gilde()
    w:clear()
    w:receive("ORDER\tauftrag1\t2580\tAnna Sturmwind\t", "WHISPER", "Beta Lux")
    w:advance(2) -- Addon-Nachrichten gehen gedrosselt aus einer Warteschlange raus
    seen(w, "sound", ".")
    seen(w, "print", "Neuer Auftrag von Beta")
    seen(w, "comm", "^WHISPER Beta Lux ORDERACK auftrag1")
end)

test("Schalter „Töne“ aus: Auftrag kommt an, aber ohne Ton", function()
    local w = Gilde()
    w.ns.SetOpt("sounds", false)
    w:clear()
    w:receive("ORDER\tauftrag1\t2580\tAnna Sturmwind\t", "WHISPER", "Beta Lux")
    w:advance(2) -- Addon-Nachrichten gehen gedrosselt aus einer Warteschlange raus
    notSeen(w, "sound")
    seen(w, "print", "Neuer Auftrag von Beta")
    seen(w, "comm", "ORDERACK auftrag1")
end)

-- Begrüßung -------------------------------------------------------------------------------------------
test("erster Start in der Gilde: das Fenster öffnet sich einmal zur Begrüßung", function()
    local w = Gilde()
    seen(w, "window", "^ElternabendFrame$")
    local w2 = login({ guild = "Elternabend", db = w.env.ElternabendDB })
    w2:advance(30)
    notSeen(w2, "window", "^ElternabendFrame$")
end)
