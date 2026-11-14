-- Einstellungen: feinere Schalter und die Voreinstellung „Ruhig“.
-- Grundsatz: Information ja, Unterbrechung nein. Töne nur, wenn jemand gerade auf dich wartet.

local function Gruppe(extra)
    local opts = {
        guild = "Elternabend", officer = true, group = true, party = { "Beta Lux" }, groupLeader = "Beta Lux",
        roster = {
            { name = "Anna Sturmwind", online = true },
            { name = "Beta Lux", online = true },
            { name = "Alpha Elternabend", online = true, officerNote = "Beta Lux" },
        },
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    local w = login(opts)
    w:advance(30)
    w:clear()
    return w
end

local function Ruhig(w) w:call(w.ns.SetPreset, "ruhig") end

-- Töne -------------------------------------------------------------------------------------------------
test("„Übrige Töne“ aus: der Ton der Pause bleibt (die Leitung wartet)", function()
    local w = Gruppe()
    w.ns.SetOpt("sounds", false)
    w:receive("PAUSE\t60", "PARTY", "Beta Lux")
    seen(w, "sound", "RAID_WARNING")
    w:advance(70)
    seen(w, "sound", "READY_CHECK") -- Pause vorbei
    noErrors(w)
end)

test("„Übrige Töne“ aus: Auftrag ohne Ton", function()
    local w = Gruppe()
    w.ns.SetOpt("sounds", false)
    w:receive("ORDER\tauftrag1\t2580\tAnna Sturmwind\t", "WHISPER", "Beta Lux")
    notSeen(w, "sound")
    seen(w, "print", "Neuer Auftrag")
end)

test("„Töne, wenn jemand wartet“ aus: Pause ohne Ton", function()
    local w = Gruppe()
    w.ns.SetOpt("soundsWaiting", false)
    w:receive("PAUSE\t60", "PARTY", "Beta Lux")
    w:advance(70)
    notSeen(w, "sound")
end)

test("wer vorher alle Töne abgeschaltet hatte, bleibt ohne Töne", function()
    local w = Gruppe({ db = { options = { sounds = false } } })
    equal(w.ns.Opt("soundsWaiting"), false, "Töne, wenn jemand wartet")
    w:receive("PAUSE\t60", "PARTY", "Beta Lux")
    notSeen(w, "sound")
end)

-- Pinnwand ---------------------------------------------------------------------------------------------
local function Zettel(w, to)
    local n = { id = "z1", title = "Wer hat Kupfer?", author = "Beta Lux", to = to }
    w:call(w.ns.Board.Notify, w.ns.Board, n, "neu")
    w:advance(6)
end

test("Zettel an alle aus: Zettel an dich kommen trotzdem", function()
    local w = Gruppe()
    w.ns.SetOpt("chatBoard", false)
    Zettel(w, "all")
    notSeen(w, "print", "Pinnwand")
    Zettel(w, "p:anna")
    seen(w, "print", "Neuer Zettel von Beta")
    noErrors(w)
end)

test("Zettel an dich aus: auch keine Antworten auf deine Zettel", function()
    local w = Gruppe()
    w.ns.SetOpt("chatBoardMine", false)
    w:call(w.ns.Board.Notify, w.ns.Board, { id = "z2", title = "Kupfer", author = "Anna Sturmwind", to = "all" },
        "reply", "Beta hat geantwortet")
    w:advance(6)
    notSeen(w, "print", "Pinnwand")
    Zettel(w, "all")
    seen(w, "print", "Neuer Zettel von Beta")
end)

test("wer vorher die Pinnwand-Meldungen abgeschaltet hatte, bleibt ohne", function()
    local w = Gruppe({ db = { options = { chatBoard = false } } })
    equal(w.ns.Opt("chatBoardMine"), false, "Zettel an dich")
end)

-- Elternknopf -------------------------------------------------------------------------------------------
test("Elternknopf „nur wenn jemand weg ist“: erscheint erst mit „Kind wach“", function()
    local w = Gruppe()
    w.ns.SetOpt("awayButtonIdle", false)
    w:call(w.ns.Away.UpdateButton, w.ns.Away)
    local knopf = w.env.ElternabendElternknopf
    check(not (knopf and knopf:IsShown()), "Knopf ist zu sehen, obwohl niemand weg ist")
    w:receive("AWAY\t300\tKind wach", "PARTY", "Beta Lux")
    w:advance(1)
    knopf = w.env.ElternabendElternknopf
    check(knopf and knopf:IsShown(), "Knopf fehlt, obwohl Beta weg ist")
    noErrors(w)
end)

test("Elternknopf wie bisher: in der Gruppe immer da", function()
    local w = Gruppe()
    w:call(w.ns.Away.UpdateButton, w.ns.Away)
    check(w.env.ElternabendElternknopf and w.env.ElternabendElternknopf:IsShown(), "Knopf fehlt")
end)

-- Raid-Erinnerung ---------------------------------------------------------------------------------------
local function RaidIn(w, minutes)
    w.env.ElternabendDB.nextRaid = { id = 7, title = "Karazhan",
        date = os.date("%Y-%m-%d %H:%M", w.env.time() + minutes * 60) }
end

test("Erinnerung vor dem Raid: groß in der Mitte, mit Ton und im Chat", function()
    local w = Gruppe()
    RaidIn(w, 10)
    w:advance(40)
    seen(w, "screen", "Raid in")
    seen(w, "sound", "RAID_WARNING")
    seen(w, "print", "Raid in")
end)

test("Erinnerung ohne Bildschirmmitte: nur eine Zeile im Chat, kein Ton", function()
    local w = Gruppe()
    w.ns.SetOpt("raidReminderScreen", false)
    RaidIn(w, 10)
    w:advance(40)
    notSeen(w, "screen")
    notSeen(w, "sound")
    seen(w, "print", "Raid in")
end)

-- Quiz ----------------------------------------------------------------------------------------------------
local function QuizStart(w)
    local rev = w.ns.QuizFragen.rev
    w:receive("QZ\tS\tq1\t" .. rev .. "\t20\t1,2,3", "PARTY", "Beta Lux")
end

test("Quiz der Leitung öffnet das Fenster", function()
    local w = Gruppe()
    QuizStart(w)
    seen(w, "window", "^ElternabendQuiz$")
    noErrors(w)
end)

test("Quizfenster aus: nur eine Zeile, /ea quiz holt die laufende Runde", function()
    local w = Gruppe()
    w.ns.SetOpt("quizOpen", false)
    QuizStart(w)
    notSeen(w, "window", "Quiz")
    seen(w, "print", "/ea quiz")
    w:slash("/ea quiz")
    seen(w, "window", "^ElternabendQuiz$")
    check(w.ns.Quiz.round and w.ns.Quiz.round.id == "q1", "die Runde der Leitung ist nicht offen")
    noErrors(w)
end)

-- Statusmeldungen -----------------------------------------------------------------------------------------
test("Statusmeldungen aus: Ping anderer ohne Zeile, die Antwort geht trotzdem raus", function()
    local w = Gruppe()
    w.ns.SetOpt("notices", false)
    w:receive("PING\tabc\t1\tx", "GUILD", "Beta Lux")
    w:advance(3)
    notSeen(w, "print", "Ping")
    seen(w, "comm", "PONG")
end)

test("Statusmeldungen an: Ping anderer zeigt eine Zeile", function()
    local w = Gruppe()
    w:receive("PING\tabc\t1\tx", "GUILD", "Beta Lux")
    seen(w, "print", "Ping 1 von Beta")
end)

-- Voreinstellung „Ruhig“ ------------------------------------------------------------------------------
test("„Ruhig“: genau diese Schalter aus, alle anderen an", function()
    local w = Gruppe()
    w.ns.SetOpt("chatMain", false) -- wird von „Ruhig“ wieder angeschaltet
    Ruhig(w)
    local off = { minimap = true, sounds = true, chatBoard = true, raidReminderScreen = true, quizOpen = true,
        notices = true, awayButtonIdle = true, recruitPopup = true }
    for _, o in ipairs(w.ns.OPTIONS) do
        if o.key then equal(w.ns.Opt(o.key), not off[o.key], o.key) end
    end
    noErrors(w)
end)

test("„Ruhig“: eine Stunde Gildenleben ohne Unterbrechung, das Wichtige kommt an", function()
    local w = Gruppe()
    Ruhig(w)
    w:clear()
    RaidIn(w, 30)
    QuizStart(w)
    w:receive("ORDER\tauftrag1\t2580\tAnna Sturmwind\t", "WHISPER", "Beta Lux")
    w:receive("PING\tabc\t1\tx", "GUILD", "Beta Lux")
    w:advance(3600)
    notSeen(w, "window")
    notSeen(w, "screen")
    notSeen(w, "sound")
    notSeen(w, "print", "Ping")
    seen(w, "print", "Neuer Auftrag")
    seen(w, "print", "Raid in")
    seen(w, "print", "/ea quiz")
    -- Twinks im Chat bleiben
    local line = w:chatLine("CHAT_MSG_GUILD", "Wer kommt mit?", "Alpha Elternabend")
    check(line and line:find("Beta"), "kein Main vor der Nachricht")
    noErrors(w)
end)

test("„Ruhig“: Pause der Leitung kommt mit Ton", function()
    local w = Gruppe()
    Ruhig(w)
    w:receive("PAUSE\t60", "PARTY", "Beta Lux")
    seen(w, "sound", "RAID_WARNING")
end)

test("„Alles an“ nach „Ruhig“: wieder wie vorher", function()
    local w = Gruppe()
    Ruhig(w)
    w:call(w.ns.SetPreset, "an")
    for _, o in ipairs(w.ns.OPTIONS) do
        if o.key then equal(w.ns.Opt(o.key), true, o.key) end
    end
end)

test("Einstellungsfenster mit allen Schaltern und den drei Knöpfen", function()
    local w = Gruppe()
    w:slash("/ea einstellungen")
    seen(w, "window", "^ElternabendOptions$")
    noErrors(w)
end)

test("nach der Umstellung: „Töne, wenn jemand wartet“ wieder an bleibt auch nach dem Neuladen an", function()
    local w = Gruppe({ db = { options = { sounds = false } } })
    w.ns.SetOpt("soundsWaiting", true)
    local w2 = Gruppe({ db = w.env.ElternabendDB })
    equal(w2.ns.Opt("soundsWaiting"), true, "Töne, wenn jemand wartet")
    equal(w2.ns.Opt("sounds"), false, "Übrige Töne")
end)

test("Knöpfe im Einstellungsfenster: „Ruhig“, „Alles an“, „Alles aus“", function()
    local w = Gruppe()
    w:slash("/ea einstellungen")
    local d = w.ns.UI.optionsDialog
    local byText = {}
    for _, f in ipairs(w.frames) do
        if f:GetParent() == d and f:GetText() then byText[f:GetText()] = f end
    end
    check(byText["Ruhig"] and byText["Alles an"] and byText["Alles aus"], "Knöpfe fehlen")
    byText["Ruhig"]:Click()
    equal(w.ns.Opt("minimap"), false, "Minimap nach „Ruhig“")
    equal(w.ns.Opt("chatMain"), true, "Twinks im Chat nach „Ruhig“")
    byText["Alles aus"]:Click()
    equal(w.ns.Opt("chatMain"), false, "Twinks im Chat nach „Alles aus“")
    byText["Alles an"]:Click()
    equal(w.ns.Opt("minimap"), true, "Minimap nach „Alles an“")
    noErrors(w)
end)

test("„Übrige Töne“ aus: deine Soft-Reserve wird ausgewürfelt – mit Ton", function()
    local w = Gruppe()
    w.ns.SR:SetEntries({ { itemId = 30904, name = "Anna Sturmwind", plus = 0 } }, "Test")
    w.ns.SetOpt("sounds", false)
    w:receive("ROLL\t|cffa335ee|Hitem:30904::::::::70:::::|h[Savior's Grasp]|h|r\t20", "PARTY", "Beta Lux")
    seen(w, "print", "Deine Soft%-Reserve wird ausgewürfelt")
    seen(w, "sound", "RAID_WARNING")
    noErrors(w)
end)
