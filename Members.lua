-- Elternabend: Mitgliederübersicht – Twinks und Mains
--
-- Wer wessen Twink ist, regelt das Addon selbst (seit 4.6.0) – die Offiziersnotiz ist nicht
-- mehr nötig, weil Addons sie in WoW Forever ohnehin nicht schreiben dürfen.
--
-- Quellen, die erste passende gilt:
--   1. Zuordnung im Addon (ns.db.links), Schlüssel = Twink:
--        k = "o"  ein Offizier hat sie im Addon gesetzt (Rechtsklick » „Twink von …“)
--        k = "s"  der Spieler hat sie selbst gemeldet („Diesen Charakter als Main festlegen“)
--        main = "" heißt ausdrücklich: kein Twink
--      Offiziers-Zuordnungen schlagen selbst gemeldete; sonst gewinnt die neueste.
--   2. Offiziersnotiz mit dem Namen des Mains (alte Vereinbarung, wird weiter gelesen)
--   3. die von Offizieren verteilte Notiz-Zuordnung (für alle ohne Leserecht)
--   4. eigene Charaktere auf diesem Account (nur lokal)
--
-- Nachrichten:
--   CHARS  <Main>\t<A;B;C>   „Das sind meine Charaktere“ (selbst gemeldet)
--   LNK    <Eintrag>          eine Zuordnung wurde geändert
--   LNQ    <neuester Stand>   beim Einloggen: wer Neueres hat, schickt LNA
--   LNA    <Einträge>         alle Zuordnungen (SendLarge)
--   Eintrag: Twink^Main^Zeit^Von^Art, mehrere mit „~“ getrennt
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

    for _, e in ipairs(self.list) do
        if e.main then e.source, e.trusted = "note", true end
    end

    -- Zuordnungen aus dem Addon gehen vor
    for _, e in ipairs(self.list) do
        local r = ns.db.links[e.key]
        if r then
            local m = r.main ~= "" and self:Find(r.main) or nil
            if r.main == "" then
                e.main, e.source, e.link = nil, "addon", r
                wipe(e.issues)
            elseif m and m ~= e then
                e.main, e.source, e.link = m, "addon", r
                -- Selbst gemeldet von einem Twink: zählt nicht für Offiziersrechte (sonst könnte sich
                -- jeder einen Offizier als Main eintragen)
                e.trusted = r.k == "o" or ns.SameName(r.by, r.main)
                wipe(e.issues)
            end
        end
    end

    -- Eigene Charaktere auf diesem Account kennt das Addon selbst (nur hier)
    local myMain = ns.db.myMain and self.byKey[ns.db.myMain]
    if myMain then
        for key in pairs(ns.db.myChars) do
            local e = self.byKey[key]
            if e and e ~= myMain and not e.main and not e.link then
                e.main, e.fromAccount, e.source, e.trusted = myMain, true, "account", true
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
            if isTwinkRank then table.insert(e.issues, { short = "Kein Main", long = "Rang „Twink“, aber kein Main zugeordnet (Rechtsklick » „Twink von …“)" }) end
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

    -- Offiziere merken sich die Zuordnung accountweit: Twinks ohne Leserecht auf
    -- demselben Account sehen sie dann sofort, auch wenn kein Offizier online ist
    if canView then
        local pairsByKey = {}
        for _, e in ipairs(self.list) do
            if e.main and e.source == "note" then pairsByKey[e.key] = ns.ShortName(e.main.name) end
        end
        ns.db.twinkMap = { time = time(), from = ns.ShortName(ns.UnitFullName("player")), pairs = pairsByKey }
    end
    if self.pending then
        local p = self.pending
        self.pending = nil
        self:Receive(p.sender, p.data)
    end
    if self.linkQueue then
        local q = self.linkQueue
        self.linkQueue = nil
        for _, item in ipairs(q) do item() end
    end
end

-- Zuordnung verteilen (Offiziere) und empfangen (alle) --------------------------
function Members:BuildMap()
    local parts = {}
    for _, e in ipairs(self.list) do
        if e.main and e.source == "note" then table.insert(parts, ns.ShortName(e.name) .. "=" .. ns.ShortName(e.main.name)) end
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

function Members:NoteFits(name)
    return #(ns.ShortName(name) or "") <= NOTE_MAX
end

-- Zuordnung im Addon -------------------------------------------------------------
local function CleanName(s) return (tostring(s or ""):gsub("[%^~\t\r\n|]", "")) end

local function Encode(r)
    return table.concat({ CleanName(r.twink), CleanName(r.main), r.t, CleanName(r.by), r.k }, "^")
end

local function Decode(text)
    local twink, main, t, by, k = strsplit("^", text)
    t = tonumber(t)
    if not twink or twink == "" or not t or (k ~= "o" and k ~= "s") then return nil end
    return { twink = twink, main = main or "", t = t, by = by or "", k = k }
end

-- Ist die Gildenliste noch nicht da, später prüfen (Rechte hängen am Rang)
local function WhenListReady(fn)
    if #Members.list > 0 then return fn() end
    Members.linkQueue = Members.linkQueue or {}
    table.insert(Members.linkQueue, fn)
end

-- Eintrag übernehmen, wenn er gültig und neuer ist. Gibt true zurück, wenn sich etwas geändert hat.
function Members:AcceptLink(r)
    local key = ns.NameKey(r.twink)
    if not key then return false end
    if r.k == "o" then
        if not ns.Board:IsOfficer(r.by) then return false end
    elseif not (ns.SameName(r.by, r.twink) or (r.main ~= "" and ns.SameName(r.by, r.main))) then
        return false -- selbst melden darf man nur für die eigenen Charaktere
    end
    local old = ns.db.links[key]
    if old then
        if old.k == "o" and r.k == "s" then return false end -- Offizier schlägt Selbstmeldung
        local newer = r.t > old.t or (r.k == "o" and old.k == "s")
        if not newer then return false end
        if old.main == r.main and old.k == r.k then
            old.t = r.t
            return false
        end
    end
    ns.db.links[key] = r
    return true
end

function Members:NewestLink()
    local t = 0
    for _, r in pairs(ns.db.links) do
        if r.t > t then t = r.t end
    end
    return t
end

local function Changed()
    Members:Scan()
    ns:Fire("MEMBERS_UPDATE")
end

-- Offizier: Twink zuordnen (mainName = nil oder "" → kein Twink)
function Members:SetLink(twinkName, mainName)
    if not ns.Board:AmOfficer() then
        ns.Print("Twinks zuordnen dürfen nur Offiziere.")
        return
    end
    local key = ns.NameKey(twinkName)
    local old = key and ns.db.links[key]
    local r = {
        twink = twinkName, main = mainName or "", by = ns.UnitFullName("player") or "", k = "o",
        t = math.max(time(), old and old.t + 1 or 0),
    }
    ns.db.links[key] = r
    ns.Comm:Send("LNK", Encode(r), "GUILD")
    Changed()
    ns.Print(ns.ShortName(twinkName) .. (r.main == "" and " ist jetzt als Main eingetragen."
        or (" ist jetzt ein Twink von " .. ns.ShortName(r.main) .. ".")))
end

function Members:Links()
    local list = {}
    for _, r in pairs(ns.db.links) do table.insert(list, r) end
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
end

ns.Comm.handlers.LNK = function(sender, parts)
    local r = Decode(parts[2] or "")
    if not r or not ns.SameName(r.by, sender) then return end
    WhenListReady(function()
        if Members:AcceptLink(r) then Changed() end
    end)
end

-- Einloggen: Stand vergleichen; wer Neueres hat, schickt alles (zufällig verzögert –
-- kommt in der Zeit schon eine Antwort von jemand anderem, entfällt die eigene)
ns.Comm.handlers.LNQ = function(_, parts)
    local theirs = tonumber(parts[2]) or 0
    if Members:NewestLink() <= theirs then return end
    Members.linkAnswer = true
    C_Timer.After(3 + math.random() * 6, function()
        if not Members.linkAnswer then return end
        Members.linkAnswer = nil
        local items = {}
        for _, r in pairs(ns.db.links) do table.insert(items, Encode(r)) end
        if #items > 0 then
            ns.WhenChatFree(function() ns.Comm:SendLarge("LNA", table.concat(items, "~"), "GUILD") end)
        end
    end)
end

ns.Comm.handlers.LNA = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if not data then return end
    Members.linkAnswer = nil
    WhenListReady(function()
        local changed = false
        for item in data:gmatch("[^~]+") do
            local r = Decode(item)
            if r and Members:AcceptLink(r) then changed = true end
        end
        if changed then Changed() end
    end)
end

function Members:RequestLinks()
    if self.linksRequested or not IsInGuild() then return end
    self.linksRequested = true
    ns.Comm:Send("LNQ", tostring(self:NewestLink()), "GUILD")
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
    ns.Print("Dieser Charakter ist jetzt dein Main. Deine Twinks werden der Gilde gemeldet.")
    self:SelfLinks(ns.UnitFullName("player"), self:MyChars(), ns.UnitFullName("player"))
    self:AnnounceMine(true)
    ns:Fire("MEMBERS_UPDATE")
end

-- Eigene Charaktere in dieser Gilde
function Members:MyChars()
    local guild = IsInGuild() and GetGuildInfo("player")
    local names = {}
    for _, c in pairs(ns.db.myChars) do
        if guild and c.guild == guild then table.insert(names, c.name) end
    end
    return names
end

-- An die Gilde: „Main ist X, meine Charaktere in dieser Gilde sind A;B;C“
function Members:AnnounceMine(force)
    if not IsInGuild() then return end
    if self.announced and not force then return end
    local main = self:MyMain()
    local guild = GetGuildInfo("player")
    if not main or not guild or main.guild ~= guild then return end
    local names = self:MyChars()
    if #names < 2 then return end
    self.announced = true
    ns.Comm:Send("CHARS", main.name .. "\t" .. table.concat(names, ";"), "GUILD")
end

-- Selbst gemeldete Charaktere als Zuordnung übernehmen (bei allen, auch beim Absender)
function Members:SelfLinks(main, chars, sender)
    local changed = false
    for _, name in ipairs(chars) do
        local key = ns.NameKey(name)
        local old = key and ns.db.links[key]
        if ns.SameName(name, main) then
            -- Der Main selbst: eine alte Selbstmeldung als Twink aufheben
            if old and old.k == "s" and old.main ~= "" then
                changed = self:AcceptLink({ twink = name, main = "", t = math.max(time(), old.t + 1), by = sender, k = "s" }) or changed
            end
        elseif not (old and ns.SameName(old.main, main)) then
            changed = self:AcceptLink({ twink = name, main = main, t = math.max(time(), old and old.t + 1 or 0), by = sender, k = "s" }) or changed
        end
    end
    return changed
end

ns.Comm.handlers.CHARS = function(sender, parts)
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
    WhenListReady(function()
        if Members:SelfLinks(main, chars, sender) then Changed() end
    end)
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
    Members:RequestLinks()
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
