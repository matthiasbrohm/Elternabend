-- Elternabend: Mitgliederübersicht – Twinks und Mains
--
-- Vereinbarung der Gilde: Die Offiziersnotiz enthält nur den Namen des Mains.
--   leer            → Main
--   „Anna Sturmwind“ → Twink von Anna Sturmwind
-- Die Notiz liegt auf dem Blizzard-Server; alle Offiziere sehen sie, auch ohne Addon.
--
-- Offiziersnotizen kann nur lesen, wessen Rang es darf. Damit alle Mitglieder sehen,
-- wer welchen Twink hat, verteilt das Addon der Offiziere die Zuordnung über den
-- Gildenkanal; die anderen speichern sie und zeigen den letzten Stand.
--
-- Zusätzlich merkt sich das Addon (accountweit), welche Charaktere einem Spieler
-- gehören. Wer seinen Main festlegt, meldet das über den Gildenkanal; Offiziere
-- bekommen daraus Vorschläge und übernehmen sie per Klick.
local _, ns = ...

local Members = { list = {}, byKey = {}, mains = {} }
ns.Members = Members

local NOTE_MAX = 31 -- Länge der Offiziersnotiz
local SHARE_INTERVAL = 15 * 60 -- unveränderte Zuordnung höchstens alle 15 Minuten neu verteilen
-- Von welchen Rängen wird eine verteilte Zuordnung angenommen? (Rang 1 bis 3 der Gilde)
local TRUSTED_RANKS = 3
-- Twinks mit diesen Rängen brauchen nicht den Rang „Twink“: Die Leitung behält ihre Rechte
-- (z. B. zum Einladen) auch auf Twinks. Vergleich ohne Groß-/Kleinschreibung.
local RANK_EXCEPTIONS = { ["gildenleitung"] = true, ["gildenmeister"] = true }

-- Rechte ------------------------------------------------------------------------
function Members:CanView()
    return IsInGuild() and C_GuildInfo.CanViewOfficerNote ~= nil and C_GuildInfo.CanViewOfficerNote()
end

function Members:CanEdit()
    return IsInGuild() and C_GuildInfo.CanEditOfficerNote ~= nil and C_GuildInfo.CanEditOfficerNote()
end

-- Rang „Twink“ (Rangnummer wie in SetGuildMemberRank, 1 = Gildenleitung)
function Members:TwinkRank()
    if not IsInGuild() or not GuildControlGetNumRanks then return nil end
    for i = 1, GuildControlGetNumRanks() or 0 do
        local name = GuildControlGetRankName(i)
        if name and ns.Lower(strtrim(name)) == "twink" then return i, name end
    end
end

-- Gildenliste auswerten -------------------------------------------------------
function Members:Scan()
    wipe(self.list)
    wipe(self.byKey)
    wipe(self.mains)
    if not IsInGuild() then return end

    -- Offiziere lesen die Notizen selbst, alle anderen nutzen die verteilte Zuordnung
    local canView = self:CanView()
    local shared = ns.db.twinkMap and ns.db.twinkMap.pairs or {}
    for i = 1, GetNumGuildMembers() do
        local name, rankName, rankIndex, level, className, zone, _, officerNote, online, _, classFile = GetGuildRosterInfo(i)
        if name and not ns.IsSecret(name) then
            local e = {
                index = i, name = name, display = ns.ShortName(name), key = ns.NameKey(name),
                rank = rankName, rankOrder = (rankIndex or 0) + 1, level = level,
                class = className, classFile = classFile, zone = zone, online = online,
                note = canView and strtrim(officerNote or "") or (shared[ns.NameKey(name)] or ""),
                twinks = {}, issues = {},
            }
            table.insert(self.list, e)
            self.byKey[e.key] = e
        end
    end

    local twinkRank = self:TwinkRank()
    -- Main zur Offiziersnotiz finden – über Nachschlagetabellen statt jeder-gegen-jeden
    -- (gleiche Regeln wie ns.SameName: gleicher Name, oder Vorname, wenn eine Seite nur den Vornamen hat)
    local byFirst = {}
    for _, e in ipairs(self.list) do
        e.first = ns.FirstKey(e.key) or e.key
        byFirst[e.first] = byFirst[e.first] or {}
        table.insert(byFirst[e.first], e)
    end
    for _, e in ipairs(self.list) do
        if e.note ~= "" then
            local matches, seen = {}, {}
            local function Add(other)
                if other and other ~= e and not seen[other] then
                    seen[other] = true
                    table.insert(matches, other)
                end
            end
            local nk = ns.NameKey(e.note)
            if nk then
                Add(self.byKey[nk])
                local nf = ns.FirstKey(nk) or nk
                if nf == nk then
                    for _, other in ipairs(byFirst[nk] or {}) do Add(other) end -- Notiz nur mit Vornamen
                else
                    local other = self.byKey[nf]
                    if other and other.key == other.first then Add(other) end -- Mitglied heißt nur mit Vornamen
                end
            end
            if #matches == 1 then
                e.main = matches[1]
            elseif #matches > 1 then
                table.insert(e.issues, { short = "Main unklar", long = "Main-Name „" .. e.note .. "“ passt zu mehreren" })
            else
                table.insert(e.issues, { short = "Main fehlt", long = "Main „" .. e.note .. "“ ist nicht in der Gilde" })
            end
        end
    end

    -- Eigene Charaktere auf diesem Account kennt das Addon selbst: ohne Offiziersnotiz
    -- trotzdem unter dem eigenen Main zeigen (nur hier, wird nicht weiterverteilt)
    local myMain = ns.db.myMain and self.byKey[ns.db.myMain]
    if myMain then
        for key in pairs(ns.db.myChars) do
            local e = self.byKey[key]
            if e and e ~= myMain and not e.main and e.note == "" then
                e.main, e.fromAccount = myMain, true
                if canView then
                    table.insert(e.issues, { short = "Notiz fehlt", long = "Laut Addon ein Twink von " .. myMain.display .. ", aber die Offiziersnotiz ist leer" })
                end
            end
        end
    end

    for _, e in ipairs(self.list) do
        local isTwinkRank = twinkRank ~= nil and e.rankOrder == twinkRank
        if e.main then
            if e.main.main then table.insert(e.issues, { short = "Main ist Twink", long = "Der Main ist selbst als Twink eingetragen" }) end
            local exempt = RANK_EXCEPTIONS[ns.Lower(strtrim(e.rank or ""))]
            if twinkRank and not isTwinkRank and not exempt then
                table.insert(e.issues, { short = "Rang fehlt", long = "Rang ist noch nicht „Twink“" })
            end
            table.insert(e.main.twinks, e)
        else
            if isTwinkRank and e.note == "" then table.insert(e.issues, { short = "Kein Main", long = "Rang „Twink“, aber kein Main in der Offiziersnotiz" }) end
            table.insert(self.mains, e)
        end
    end

    -- Online, wenn irgendein Charakter des Spielers online ist
    for _, m in ipairs(self.mains) do
        m.onlineAs = m.online and m or nil
        table.sort(m.twinks, function(a, b) return a.name < b.name end)
        for _, t in ipairs(m.twinks) do
            if t.online and not m.onlineAs then m.onlineAs = t end
        end
    end
    table.sort(self.mains, function(a, b) return a.name < b.name end)
    self:CleanSuggestions()
    -- Offiziere merken sich die Zuordnung accountweit: Twinks ohne Leserecht auf
    -- demselben Account sehen sie dann sofort, auch wenn kein Offizier online ist
    if canView then
        local pairsByKey = {}
        for _, e in ipairs(self.list) do
            if e.main and not e.fromAccount then pairsByKey[e.key] = ns.ShortName(e.main.name) end
        end
        ns.db.twinkMap = { time = time(), from = ns.ShortName(ns.UnitFullName("player")), pairs = pairsByKey }
    end
    if self.pending then
        local p = self.pending
        self.pending = nil
        self:Receive(p.sender, p.data)
    end
end

-- Zuordnung verteilen (Offiziere) und empfangen (alle) --------------------------
function Members:BuildMap()
    local parts = {}
    for _, e in ipairs(self.list) do
        if e.main and not e.fromAccount then table.insert(parts, ns.ShortName(e.name) .. "=" .. ns.ShortName(e.main.name)) end
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

function Members:Share(force)
    if not self:CanView() or #self.list == 0 then return end
    local data = self:BuildMap()
    local now = GetTime()
    if not force and data == self.lastShared and now - (self.lastShareTime or -SHARE_INTERVAL) < SHARE_INTERVAL then return end
    self.lastShared, self.lastShareTime = data, now
    self.shareRequested = false
    ns.Comm:SendLarge("TWM", time() .. "#" .. data, "GUILD")
end

function Members:Receive(sender, data)
    if self:CanView() then return end -- Offiziere haben die echten Notizen
    if #self.list == 0 then
        self.pending = { sender = sender, data = data } -- erst prüfen, wenn die Gildenliste da ist
        return
    end
    local from = self:Find(sender)
    if not from or from.rankOrder > TRUSTED_RANKS then return end
    local stamp, list = data:match("^(%d+)#(.*)$")
    if not stamp then return end
    local pairsByKey = {}
    for twink, main in list:gmatch("([^=;]+)=([^;]+)") do
        pairsByKey[ns.NameKey(twink)] = main
    end
    ns.db.twinkMap = { time = tonumber(stamp), from = from.display, pairs = pairsByKey }
    self:Scan()
    ns:Fire("MEMBERS_UPDATE")
end

ns.Comm.handlers.TWM = function(sender, parts)
    Members.shareRequested = false -- ein anderer Offizier verteilt gerade
    local data = ns.Comm:Assemble(sender, parts)
    if data then Members:Receive(sender, data) end
end

-- Mitglied fragt nach der Zuordnung: ein Offizier antwortet, zufällig verzögert,
-- damit nicht alle gleichzeitig senden
ns.Comm.handlers.TWQ = function()
    if not Members:CanView() or Members.shareRequested then return end
    Members.shareRequested = true
    C_Timer.After(2 + math.random() * 5, function()
        if Members.shareRequested then Members:Share(true) end
    end)
end

function Members:RequestMap()
    if self.requested or self:CanView() or not IsInGuild() then return end
    self.requested = true
    ns.Comm:Send("TWQ", nil, "GUILD")
end

function Members:Find(name)
    local key = ns.NameKey(name)
    if not key then return nil end
    if self.byKey[key] then return self.byKey[key] end
    for _, e in ipairs(self.list) do
        if ns.SameName(e.name, key) then return e end
    end
end

-- Schreiben können Addons nichts: C_GuildInfo.SetNote (Offiziersnotiz) und das Ändern von
-- Rängen sind im aktuellen Client für Addons gesperrt (ADDON_ACTION_FORBIDDEN, auch mit
-- pcall). Das Addon legt deshalb nur den Main-Namen zum Kopieren bereit; eingefügt wird er
-- im Gildenfenster.
function Members:NoteFits(name)
    return #(ns.ShortName(name) or "") <= NOTE_MAX
end

-- Eigene Charaktere (accountweit) -----------------------------------------------
function Members:RememberMe()
    local name = ns.UnitFullName("player")
    local key = ns.NameKey(name)
    if not key then return end
    local class, classFile = UnitClass("player")
    ns.db.myChars[key] = {
        name = name, class = class, classFile = classFile, level = UnitLevel("player"),
        guild = IsInGuild() and GetGuildInfo("player") or nil, seen = time(),
    }
end

function Members:MyMain()
    local main = ns.db.myMain and ns.db.myChars[ns.db.myMain]
    return main
end

function Members:SetMyMain()
    self:RememberMe()
    ns.db.myMain = ns.PlayerKey()
    ns.Print("Dieser Charakter ist jetzt dein Main. Die Offiziere bekommen einen Vorschlag für deine Twinks.")
    self:AnnounceMine(true)
    ns:Fire("MEMBERS_UPDATE")
end

-- An die Gilde: „Main ist X, meine Charaktere in dieser Gilde sind A;B;C“
function Members:AnnounceMine(force)
    if not IsInGuild() then return end
    if self.announced and not force then return end
    local main = self:MyMain()
    local guild = GetGuildInfo("player")
    if not main or not guild or main.guild ~= guild then return end
    local names = {}
    for _, c in pairs(ns.db.myChars) do
        if c.guild == guild then table.insert(names, c.name) end
    end
    if #names < 2 then return end
    self.announced = true
    ns.Comm:Send("CHARS", main.name .. "\t" .. table.concat(names, ";"), "GUILD")
end

-- Vorschläge (bei Offizieren) ------------------------------------------------
ns.Comm.handlers.CHARS = function(sender, parts)
    if not Members:CanEdit() then return end
    local main, list = parts[2], parts[3]
    if not main or not list then return end
    local chars = {}
    for name in list:gmatch("[^;]+") do table.insert(chars, name) end
    -- Nur übernehmen, wenn der Absender selbst einer dieser Charaktere ist
    local fromOwner = false
    for _, name in ipairs(chars) do
        if ns.SameName(name, sender) then fromOwner = true end
    end
    if not fromOwner then return end

    for _, name in ipairs(chars) do
        if not ns.SameName(name, main) then
            ns.db.memberSuggestions[ns.NameKey(name)] = { twink = name, main = main, time = time() }
        end
    end
    Members:CleanSuggestions()
    ns:Fire("MEMBERS_UPDATE")
end

-- Vorschläge entfernen, die schon stimmen oder nicht mehr passen
function Members:CleanSuggestions()
    if #self.list == 0 then return end
    for key, s in pairs(ns.db.memberSuggestions) do
        local twink = self:Find(s.twink)
        if not twink or not self:Find(s.main) or (twink.main and ns.SameName(twink.main.name, s.main)) then
            ns.db.memberSuggestions[key] = nil
        end
    end
end

function Members:Suggestions()
    local list = {}
    for _, s in pairs(ns.db.memberSuggestions) do table.insert(list, s) end
    table.sort(list, function(a, b) return a.main == b.main and a.twink < b.twink or a.main < b.main end)
    return list
end

-- Events -------------------------------------------------------------------------
-- Die Gildenliste meldet sich in großen Gilden alle paar Sekunden. Auswerten höchstens alle
-- 5 Sekunden (gesammelt), damit es beim Spielen nicht ruckelt.
local SCAN_GAP = 5
Members.perf = { scans = 0, events = 0, lastMs = 0, maxMs = 0, since = 0 }
local lastScan, scanQueued = -SCAN_GAP, false
local function RunScan()
    scanQueued = false
    lastScan = GetTime()
    local start = debugprofilestop and debugprofilestop()
    Members:Scan()
    Members:RememberMe()
    Members:AnnounceMine()
    Members:Share()
    Members:RequestMap()
    ns:Fire("MEMBERS_UPDATE")
    if start then
        local ms = debugprofilestop() - start
        local p = Members.perf
        p.scans, p.lastMs, p.maxMs = p.scans + 1, ms, math.max(p.maxMs, ms)
    end
end
ns:On("GUILD_ROSTER_UPDATE", function()
    Members.perf.events = Members.perf.events + 1
    if scanQueued then return end
    local wait = lastScan + SCAN_GAP - GetTime()
    if wait <= 0 then
        RunScan()
    else
        scanQueued = true
        C_Timer.After(wait, RunScan)
    end
end)
ns:On("PLAYER_LOGIN", function()
    Members.perf.since = GetTime()
    Members:RememberMe()
    C_Timer.After(8, function()
        if IsInGuild() then C_GuildInfo.GuildRoster() end
    end)
end)
