-- Elternabend: Quiz für Raid, Zeltlager und Lagerfeuer
--
-- Die Leitung startet eine Runde für die ganze Gruppe: Das Addon zieht zufällig zehn
-- der Fragen aus QuizFragen.lua und schickt nur deren Nummern an die Gruppe. Bei allen
-- mit Addon geht das Quizfenster auf; jeder beantwortet dieselben Fragen in seinem
-- Tempo, mit Bedenkzeit je Frage. Am Ende meldet jedes Addon sein Ergebnis, und alle
-- sehen die Rangliste (mehr Richtige zuerst, bei Gleichstand die schnellere Zeit).
-- Ohne Gruppe ist es eine Proberunde für einen allein.
local _, ns = ...
local T = ns.Theme

local Quiz = { streak = 0 }
ns.Quiz = Quiz

Quiz.COUNT = 10   -- Fragen je Runde
Quiz.SECONDS = 20 -- Bedenkzeit je Frage
Quiz.SINCE = "4.15.0" -- ab dieser Addon-Version kann man mitspielen

local SEP = "\t"
local GROUP_CHANNELS = { RAID = true, PARTY = true, INSTANCE_CHAT = true }

local function Pool()
    return ns.QuizFragen.list
end

local function Settings()
    ns.db.quiz = ns.db.quiz or {}
    return ns.db.quiz
end

-- „83,4 s“
function Quiz.FormatTime(seconds)
    return (string.format("%.1f s", seconds):gsub("%.", ","))
end

-- Zufällig „count“ Nummern aus 1..total ziehen. „used“ merkt sich, was schon dran war:
-- Erst wenn (fast) alle Fragen gestellt wurden, geht es von vorn los – so wiederholt
-- sich über mehrere Abende nichts.
function Quiz.Pick(count, total, used, rnd)
    rnd = rnd or math.random
    local picked = {}
    local function Draw(from)
        while #picked < count and #from > 0 do
            table.insert(picked, table.remove(from, rnd(#from)))
        end
    end
    local free = {}
    for i = 1, total do
        if not (used and used[i]) then table.insert(free, i) end
    end
    Draw(free)
    if #picked < count then
        local taken, rest = {}, {}
        for _, i in ipairs(picked) do taken[i] = true end
        if used then
            for k in pairs(used) do used[k] = nil end
        end
        for i = 1, total do
            if not taken[i] then table.insert(rest, i) end
        end
        Draw(rest)
    end
    if used then
        for _, i in ipairs(picked) do used[i] = true end
    end
    return picked
end

-- Runde -----------------------------------------------------------------------
function Quiz:CanHost()
    return IsInGroup() and ns.IsTrusted(ns.UnitFullName("player"))
end

-- Wer in der Gruppe kann mitspielen? Zahl der Addons mit Quiz und die Namen der übrigen
-- (kein Addon, ältere Version oder noch keine Meldung).
function Quiz:Readiness()
    local with, without = 0, {}
    local me = ns.PlayerKey()
    for _, m in ipairs(ns.Raid.members) do
        local version = m.key == me and ns.VERSION or ns.Comm.versions[m.key]
        if version and (version == "dev" or ns.CompareVersions(version, self.SINCE) >= 0) then
            with = with + 1
        else
            table.insert(without, ns.ShortName(m.name) or "?")
        end
    end
    return with, without
end

-- Leitung: Runde für die Gruppe starten. Ohne Gruppe: Proberunde.
function Quiz:Start()
    local total = #Pool()
    if not IsInGroup() then
        self:Begin(nil, Quiz.Pick(self.COUNT, total), self.SECONDS, nil)
        self:NextQuestion()
        return
    end
    if not self:CanHost() then
        ns.Print("Das Quiz startet die Leitung der Gruppe.")
        return
    end
    local s = Settings()
    if s.usedRev ~= ns.QuizFragen.rev or type(s.used) ~= "table" then
        s.used, s.usedRev = {}, ns.QuizFragen.rev
    end
    local list = Quiz.Pick(self.COUNT, total, s.used)
    local id = tostring(math.random(1000, 9999))
    ns.Comm:Send("QZ", table.concat({ "S", id, ns.QuizFragen.rev, self.SECONDS, table.concat(list, ",") }, SEP))
    ns.Announce("Elternabend-Quiz: " .. #list .. " Fragen, je " .. self.SECONDS
        .. " Sekunden Zeit. Mit dem Gildenaddon geht jetzt das Quizfenster auf (sonst /ea quiz).")
    self:Begin(id, list, self.SECONDS, ns.UnitFullName("player"))
end

-- Neue Runde anlegen (eigene oder empfangene). id = nil: Proberunde allein.
-- hidden: Runde vorbereiten, aber das Fenster nicht öffnen (/ea quiz zeigt sie dann)
function Quiz:Begin(id, list, secs, host, hidden)
    self:StopTimer()
    self.round = { id = id, solo = id == nil, list = list, secs = secs, host = host,
        pos = 0, correct = 0, time = 0, results = {} }
    self.view = "intro"
    if not hidden then self:Show() end
end

function Quiz:NextQuestion()
    local r = self.round
    if not r or r.done then return end
    if r.pos >= #r.list then
        self:Finish()
        return
    end
    r.pos = r.pos + 1
    local q = Pool()[r.list[r.pos]]
    -- Antworten mischen (in der Liste steht die richtige immer vorn)
    local order = { 1, 2, 3, 4 }
    for i = 4, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end
    local cur = { text = q[1], answers = {}, started = GetTime() }
    for slot, n in ipairs(order) do
        cur.answers[slot] = q[n + 1]
        if n == 1 then cur.right = slot end
    end
    r.q = cur
    self.view = "question"
    self:StartTimer()
    self:Show()
end

-- Antwort werten; slot = nil heißt: Zeit abgelaufen
function Quiz:Answer(slot)
    local r = self.round
    if not r or self.view ~= "question" then return end
    self:StopTimer()
    local q = r.q
    q.picked, q.timeout = slot, slot == nil
    q.ok = slot ~= nil and slot == q.right
    r.time = r.time + (slot and math.min(r.secs, GetTime() - q.started) or r.secs)
    if q.ok then
        r.correct = r.correct + 1
        self.streak = self.streak + 1
        local s = Settings()
        if self.streak > (s.best or 0) then s.best = self.streak end
    else
        self.streak = 0
    end
    self.view = "feedback"
    self:Refresh()
end

function Quiz:Finish()
    local r = self.round
    r.done, r.q = true, nil
    r.results[ns.PlayerKey()] = { name = ns.UnitFullName("player"), correct = r.correct, time = r.time, me = true }
    if not r.solo then
        ns.Comm:Send("QZ", table.concat({ "R", r.id, r.correct, math.floor(r.time * 10 + 0.5) }, SEP))
    end
    self.view = "result"
    self:Refresh()
end

-- Rangliste: mehr Richtige zuerst, bei Gleichstand die kürzere Zeit
function Quiz:Ranking()
    local list = {}
    if self.round then
        for _, e in pairs(self.round.results) do table.insert(list, e) end
    end
    table.sort(list, function(a, b)
        if a.correct ~= b.correct then return a.correct > b.correct end
        if a.time ~= b.time then return a.time < b.time end
        return a.name < b.name
    end)
    return list
end

-- Leitung: die ersten drei im Gruppenchat ansagen
function Quiz:AnnounceResult()
    local r = self.round
    local rank = self:Ranking()
    if not r or #rank == 0 then return end
    ns.Announce("Elternabend-Quiz – Ergebnis (" .. #rank .. " Teilnehmer):")
    for i = 1, math.min(3, #rank) do
        local e = rank[i]
        ns.Announce(i .. ". Platz: " .. (ns.ShortName(e.name) or "?") .. " – " .. e.correct .. " von " .. #r.list
            .. " richtig in " .. Quiz.FormatTime(e.time))
    end
end

-- Bedenkzeit ------------------------------------------------------------------
function Quiz:StartTimer()
    self:StopTimer()
    self.ticker = C_Timer.NewTicker(0.1, function() Quiz:Tick() end)
end

function Quiz:StopTimer()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function Quiz:TimeLeft()
    local r = self.round
    if not r or not r.q then return 0 end
    return r.secs - (GetTime() - r.q.started)
end

function Quiz:Tick()
    if not self.round or self.view ~= "question" then
        self:StopTimer()
        return
    end
    if self:TimeLeft() <= 0 then
        self:Answer(nil)
    else
        self:UpdateClock()
    end
end

-- Nachrichten -------------------------------------------------------------------
-- QZ  S  id  rev  sekunden  nr,nr,…   Start durch die Leitung
-- QZ  R  id  richtige  zehntelsekunden   eigenes Ergebnis
ns.Comm.handlers.QZ = function(sender, parts, channel)
    if not GROUP_CHANNELS[channel] then return end
    local kind, id = parts[2], parts[3]
    if not id or id == "" then return end
    if kind == "S" then
        if not ns.IsTrusted(sender) then return end
        if tonumber(parts[4]) ~= ns.QuizFragen.rev then
            ns.Print((ns.ShortName(sender) or "Die Leitung") .. " hat ein Quiz gestartet, aber dein Addon hat einen anderen Fragenstand. "
                .. "Bitte das Addon aktualisieren: " .. ns.DOWNLOAD)
            return
        end
        local secs, list, seen = tonumber(parts[5]), {}, {}
        for n in (parts[6] or ""):gmatch("%d+") do
            local i = tonumber(n)
            if Pool()[i] and not seen[i] and #list < 30 then
                seen[i] = true
                table.insert(list, i)
            end
        end
        if not secs or #list == 0 then return end
        local open = ns.Opt("quizOpen")
        Quiz:Begin(id, list, math.max(5, math.min(60, secs)), sender, not open)
        ns.Print((ns.ShortName(sender) or "Die Leitung") .. " hat ein Quiz gestartet – "
            .. (open and "das Fenster ist offen (sonst /ea quiz)." or "mitmachen mit /ea quiz."))
    elseif kind == "R" then
        local r = Quiz.round
        local correct, tenths = tonumber(parts[4]), tonumber(parts[5])
        local key = ns.NameKey(sender)
        if not r or r.solo or r.id ~= id or not correct or not tenths or not key then return end
        r.results[key] = { name = sender, correct = math.max(0, math.min(#r.list, math.floor(correct))),
            time = math.max(0, tenths) / 10 }
        if Quiz.view == "result" then Quiz:Refresh() end
    end
end

-- Fenster ---------------------------------------------------------------------
local W, H = 560, 480
local INNER = W - 40
local ANSWER_TOP, ANSWER_STEP = -150, 38
local RANK_LINES = 12

local function Paint(button, bg, bgAlpha, border, borderAlpha)
    button:SetBackdropColor(bg[1], bg[2], bg[3], bgAlpha)
    button:SetBackdropBorderColor(border[1], border[2], border[3], borderAlpha)
end

local GREEN, RED = { 0.20, 0.55, 0.26 }, { 0.62, 0.20, 0.17 }

function Quiz:Create()
    if self.frame then return end
    local c = T.colors
    local d = CreateFrame("Frame", "ElternabendQuiz", UIParent, "BackdropTemplate")
    d:SetSize(W, H)
    d:SetPoint("CENTER", 0, 40)
    d:SetFrameStrata("DIALOG")
    d:SetToplevel(true)
    d:SetMovable(true)
    d:SetClampedToScreen(true)
    d:EnableMouse(true)
    d:RegisterForDrag("LeftButton")
    d:SetScript("OnDragStart", d.StartMoving)
    d:SetScript("OnDragStop", d.StopMovingOrSizing)
    T.Backdrop(d, c.navy, 0.98, 0.7)

    local kicker = T.Text(d, "kicker")
    kicker:SetPoint("TOPLEFT", 20, -18)
    kicker:SetText("ELTERNABEND")
    d.title = T.Text(d, "heading")
    d.title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -6)
    d.title:SetText("Quiz")
    d.progress = T.Text(d, "muted", "RIGHT")
    d.progress:SetPoint("TOPRIGHT", -20, -34)

    d.question = T.Text(d, "heading")
    d.question:SetPoint("TOPLEFT", 20, -72)
    d.question:SetWidth(INNER)
    d.question:SetJustifyV("TOP")
    d.question:SetSpacing(4)

    -- Bedenkzeit als schmaler Balken
    d.bar = CreateFrame("Frame", nil, d)
    d.bar:SetSize(INNER, 3)
    d.bar:SetPoint("TOPLEFT", 20, ANSWER_TOP + 10)
    local track = d.bar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(c.gold[1], c.gold[2], c.gold[3], 0.18)
    d.bar.fill = d.bar:CreateTexture(nil, "ARTWORK")
    d.bar.fill:SetPoint("TOPLEFT")
    d.bar.fill:SetPoint("BOTTOMLEFT")
    d.bar.fill:SetWidth(INNER)
    d.bar.fill:SetColorTexture(c.goldBright[1], c.goldBright[2], c.goldBright[3], 0.9)

    d.answers = {}
    for i = 1, 4 do
        local b = T.Button(d, "", INNER)
        b:SetHeight(32)
        b:SetPoint("TOPLEFT", 20, ANSWER_TOP - (i - 1) * ANSWER_STEP)
        b:SetScript("OnClick", function() Quiz:Answer(i) end)
        d.answers[i] = b
    end

    d.feedback = T.Text(d, "body")
    d.feedback:SetPoint("TOPLEFT", 20, ANSWER_TOP - 4 * ANSWER_STEP - 6)
    d.feedback:SetWidth(INNER)
    d.feedback:SetSpacing(3)

    -- Fließtext für Start, Einleitung und Rangliste
    d.body = T.Text(d, "body")
    d.body:SetPoint("TOPLEFT", 20, -108)
    d.body:SetWidth(INNER)
    d.body:SetJustifyV("TOP")
    d.body:SetSpacing(5)

    d.next = T.Button(d, "Nächste Frage", 200, "primary")
    d.next:SetPoint("BOTTOMLEFT", 20, 52)
    d.next:SetScript("OnClick", function() Quiz:OnNext() end)
    d.second = T.Button(d, "", 150)
    d.second:SetPoint("LEFT", d.next, "RIGHT", 8, 0)
    d.second:SetScript("OnClick", function() Quiz:OnSecond() end)

    d.footer = T.Text(d, "muted")
    d.footer:SetPoint("BOTTOMLEFT", 20, 24)
    d.close = T.Button(d, "Schließen", 110)
    d.close:SetPoint("BOTTOMRIGHT", -20, 18)
    d.close:SetScript("OnClick", function() d:Hide() end)

    d:SetScript("OnShow", function() Quiz:Refresh() end)
    d:Hide()
    self.frame = d
end

-- /ea quiz und der Knopf im Raid-Reiter
function Quiz:Open()
    local r = self.round
    -- Eine beendete Proberunde nicht stehen lassen: wieder die Startansicht zeigen
    if r and r.solo and r.done then self.round = nil end
    if not self.round then self.view = "start" end
    self:Show()
end

function Quiz:Show()
    self:Create()
    self.frame:Show()
    self:Refresh()
end

function Quiz:UpdateClock()
    local d, r = self.frame, self.round
    if not d or not d:IsShown() or not r or not r.q then return end
    local left = math.max(0, self:TimeLeft())
    d.bar.fill:SetWidth(math.max(1, INNER * left / r.secs))
    d.progress:SetText("Frage " .. r.pos .. " / " .. #r.list .. "  ·  noch " .. math.ceil(left) .. " s")
end

-- Der große Knopf: je nach Ansicht starten, loslegen, weiter oder ansagen
function Quiz:OnNext()
    local r, view = self.round, self.view
    if view == "start" then
        self:Start()
    elseif view == "intro" or view == "feedback" then
        self:NextQuestion()
    elseif view == "result" then
        if r and not r.solo and self:CanHost() then self:AnnounceResult() else self:Start() end
    end
end

-- Der zweite Knopf: neue Runde (Leitung, nach der Auswertung)
function Quiz:OnSecond()
    if self.view == "result" then self:Start() end
end

local function RankLine(i, e, total)
    local line = string.format("%d.  %s  –  %d von %d  ·  %s", i, ns.ShortName(e.name) or "?", e.correct, total,
        Quiz.FormatTime(e.time))
    return e.me and T.Hex("goldBright", line) or line
end

function Quiz:ResultText()
    local r = self.round
    local total = #r.list
    local lines = { "Du hast " .. r.correct .. " von " .. total .. " Fragen richtig beantwortet – in "
        .. Quiz.FormatTime(r.time) .. "." }
    if r.solo then
        table.insert(lines, "")
        table.insert(lines, T.Hex("muted", "Das war eine Proberunde. In der Gruppe startet die Leitung das Quiz für alle, "
            .. "und am Ende gibt es eine Rangliste."))
        return table.concat(lines, "\n")
    end
    local rank = self:Ranking()
    table.insert(lines, "")
    table.insert(lines, T.Hex("gold", "RANGLISTE") .. T.Hex("muted", "  ·  " .. #rank .. " fertig"))
    local mine
    for i, e in ipairs(rank) do
        if e.me then mine = i end
        if i <= RANK_LINES then table.insert(lines, RankLine(i, e, total)) end
    end
    if #rank > RANK_LINES then
        if mine and mine > RANK_LINES then
            table.insert(lines, "…")
            table.insert(lines, RankLine(mine, rank[mine], total))
        else
            table.insert(lines, T.Hex("muted", "… und " .. (#rank - RANK_LINES) .. " weitere"))
        end
    end
    return table.concat(lines, "\n")
end

function Quiz:Refresh()
    local d = self.frame
    if not d or not d:IsShown() then return end
    local c = T.colors
    -- Proberunde beendet und inzwischen in einer Gruppe: Jetzt zählt das Quiz für alle
    if self.round and self.round.solo and self.round.done and IsInGroup() then
        self.round, self.view = nil, "start"
    end
    local r, view = self.round, self.view or "start"
    local asking = (view == "question" or view == "feedback") and r and r.q

    d.bar:SetShown(view == "question")
    d.feedback:SetShown(view == "feedback")
    d.body:SetShown(not asking)
    for _, b in ipairs(d.answers) do b:SetShown(asking and true or false) end
    d.second:Hide()
    d.next:Show()
    d.progress:SetText("")

    if asking then
        local q = r.q
        d.question:SetText(q.text)
        for i, b in ipairs(d.answers) do
            b:SetText(q.answers[i])
            if view == "question" then
                b:SetAlpha(1)
                Paint(b, c.ink, 0.35, c.gold, 0.85)
            elseif i == q.right then
                b:SetAlpha(1)
                Paint(b, GREEN, 0.9, GREEN, 1)
            elseif i == q.picked then
                b:SetAlpha(1)
                Paint(b, RED, 0.9, RED, 1)
            else
                b:SetAlpha(0.45)
                Paint(b, c.ink, 0.35, c.gold, 0.85)
            end
        end
        if view == "question" then
            d.next:Hide()
            self:UpdateClock()
        else
            d.progress:SetText("Frage " .. r.pos .. " / " .. #r.list)
            if q.ok then
                d.feedback:SetText(T.Hex("green", "Richtig!"))
            else
                d.feedback:SetText(T.Hex("red", q.timeout and "Zeit abgelaufen." or "Nicht ganz.")
                    .. "  Richtig ist: " .. q.answers[q.right])
            end
            d.next:SetText(r.pos >= #r.list and "Zur Auswertung" or "Nächste Frage")
        end
    elseif view == "intro" and r then
        if r.solo then
            d.question:SetText("Proberunde")
            d.body:SetText(#r.list .. " zufällige Fragen, je " .. r.secs .. " Sekunden Zeit.")
        else
            d.question:SetText("Das Quiz beginnt!")
            d.body:SetText((ns.ShortName(r.host) or "Die Leitung") .. " hat ein Quiz für die Gruppe gestartet.\n\n"
                .. #r.list .. " Fragen, je " .. r.secs .. " Sekunden Zeit. Die Uhr läuft erst, wenn du auf "
                .. "„Los geht's“ klickst – und dann für jede Frage einzeln.\n\n"
                .. "Es zählt, wie viele Antworten stimmen. Bei Gleichstand gewinnt, wer schneller war.")
        end
        d.next:SetText("Los geht's")
    elseif view == "result" and r then
        d.question:SetText(r.correct == #r.list and "Alles richtig!" or "Geschafft!")
        d.body:SetText(self:ResultText())
        if r.solo then
            d.next:SetText("Noch eine Runde")
        elseif self:CanHost() then
            d.next:SetText("Ergebnis ansagen")
            d.second:SetText("Neue Runde")
            d.second:Show()
        else
            d.next:Hide()
        end
    else
        d.question:SetText("Wer weiß es?")
        local about = self.COUNT .. " Fragen, zufällig aus " .. #Pool() .. " gezogen, je " .. self.SECONDS
            .. " Sekunden Zeit."
        if not IsInGroup() then
            d.body:SetText("Proberunde für dich allein: " .. about .. "\n\n"
                .. T.Hex("muted", "In einer Gruppe oder im Schlachtzug startet die Leitung das Quiz für alle – "
                .. "mit Rangliste am Ende."))
            d.next:SetText("Proberunde starten")
        elseif self:CanHost() then
            local with, without = self:Readiness()
            local ready = "Mitspielen können gerade " .. with .. " von " .. (with + #without)
                .. " in der Gruppe (Addon ab " .. self.SINCE .. ")."
            if #without > 0 then
                local names = {}
                for i = 1, math.min(8, #without) do names[i] = without[i] end
                ready = ready .. "\n" .. T.Hex("muted", "Noch nicht dabei: " .. table.concat(names, ", ")
                    .. (#without > 8 and (" und " .. (#without - 8) .. " weitere") or "") .. ".")
            end
            d.body:SetText("Du leitest die Gruppe und kannst das Quiz für alle starten: " .. about .. "\n\n"
                .. "Bei allen mit dem Gildenaddon geht dieses Fenster auf, jeder bekommt dieselben Fragen. "
                .. "Am Ende siehst du die Rangliste und kannst die ersten drei ansagen.\n\n" .. ready)
            d.next:SetText("Quiz für alle starten")
        else
            d.body:SetText("Das Quiz startet die Leitung der Gruppe. Sobald es losgeht, öffnet sich dieses Fenster von selbst.")
            d.next:Hide()
        end
    end

    local answered = r and (r.pos - (view == "question" and 1 or 0)) or 0
    d.footer:SetText((r and (r.correct .. " / " .. math.max(0, answered) .. " richtig  |  ") or "")
        .. "Serie " .. self.streak .. "  |  Bestwert " .. (Settings().best or 0))
end

-- Gruppe geändert (beigetreten, Leitung gewechselt, Addon-Versionen gemeldet): Ansicht anpassen
ns:Listen("ROSTER_UPDATE", function()
    if Quiz.frame and Quiz.frame:IsShown() and Quiz.view ~= "question" then Quiz:Refresh() end
end)
