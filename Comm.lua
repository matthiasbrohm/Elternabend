-- Elternabend Raid: Addon-Kommunikation zwischen den Raidmitgliedern
local _, ns = ...

local Comm = { versions = {}, incoming = {}, queue = {}, handlers = {}, seen = {},
    stats = { sent = {}, results = {}, recv = {}, from = {}, guildSent = 0, echo = 0 } }
ns.Comm = Comm

local SEP = "\t"
local CHUNK_SIZE = 200

-- Der Server lässt pro Addon nur 10 Nachrichten am Stück durch, danach eine pro
-- Sekunde – alles darüber verwirft er. Deshalb wird hier selbst mitgezählt.
local BURST = 10
local allowance, lastRefill = BURST, nil
local R = Enum and Enum.SendAddonMessageResult
local THROTTLED = { [R and R.AddonMessageThrottle or 3] = true, [R and R.ChannelThrottle or 8] = true }

-- Nächste Nachricht: kurze zuerst, große Datenpakete (SendLarge) danach
local function NextIndex(queue)
    for i, item in ipairs(queue) do
        if not item[4] then return i end
    end
    return 1
end

function Comm:Pump()
    -- Während der Chat-Sperre bleibt die Warteschlange einfach liegen
    if ns.ChatLocked() then return end
    local now = GetTime()
    if lastRefill then allowance = math.min(BURST, allowance + (now - lastRefill)) end
    lastRefill = now
    if allowance >= 1 and #self.queue > 0 then
        local i = NextIndex(self.queue)
        local item = self.queue[i]
        local result = C_ChatInfo.SendAddonMessage(ns.PREFIX, item[1], item[2], item[3])
        local st = self.stats
        st.results[tostring(result)] = (st.results[tostring(result)] or 0) + 1
        if THROTTLED[result] then
            allowance = 0 -- bleibt in der Schlange, nächster Versuch nach einer Sekunde
        else
            table.remove(self.queue, i)
            allowance = allowance - 1
            local t = item[1]:match("^[^\t]+")
            st.sent[t] = (st.sent[t] or 0) + 1
            if item[2] == "GUILD" then st.guildSent = st.guildSent + 1 end
        end
    end
    if #self.queue == 0 and self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function Comm:Send(msgType, payload, channel, target, bulk)
    channel = channel or ns.GroupChannel()
    if not channel then return end
    local msg = payload and (msgType .. SEP .. payload) or msgType
    table.insert(self.queue, { msg, channel, target, bulk })
    if self.ticker then return end
    self.ticker = C_Timer.NewTicker(0.1, function() Comm:Pump() end)
end

-- Längere Daten in Stücke zerlegen: TYP \t id \t gesamt \t nr \t daten
-- Geschnitten wird nie mitten in einem Umlaut (UTF-8), sonst lehnt der Server das Stück ab.
function Comm.Split(data)
    local chunks, pos = {}, 1
    while pos <= #data do
        local last = math.min(pos + CHUNK_SIZE - 1, #data)
        while last > pos and last < #data do
            local nextByte = data:byte(last + 1)
            if nextByte < 0x80 or nextByte >= 0xC0 then break end
            last = last - 1
        end
        table.insert(chunks, data:sub(pos, last))
        pos = last + 1
    end
    if #chunks == 0 then chunks[1] = "" end
    return chunks
end

function Comm:SendLarge(msgType, data, channel, target)
    local id = tostring(math.random(100000, 999999))
    local chunks = Comm.Split(data)
    for i, chunk in ipairs(chunks) do
        self:Send(msgType, table.concat({ id, #chunks, i, chunk }, SEP), channel, target, true)
    end
end

ns:On("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
    if prefix ~= ns.PREFIX or not sender or ns.IsSecret(msg) or ns.IsSecret(sender) then return end
    if ns.SameName(sender, ns.PlayerKey()) then
        -- Eigene Gildennachrichten kommen als Echo zurück – wenn der Server sie verteilt
        if channel == "GUILD" then Comm.stats.echo = Comm.stats.echo + 1 end
        return
    end
    local senderKey = ns.NameKey(sender)
    if senderKey and not Comm.seen[senderKey] then
        Comm.seen[senderKey] = sender
        ns:Fire("ADDON_USER_SEEN", sender, senderKey)
    end
    local parts = { strsplit(SEP, msg) }
    local st = Comm.stats
    st.recv[parts[1]] = (st.recv[parts[1]] or 0) + 1
    st.from[parts[1]] = sender
    local handler = Comm.handlers[parts[1]]
    if handler then handler(sender, parts, channel) end
end)

-- Versionsabfrage ("Wer hat das Addon?") ------------------------------
-- „3.10.0“ > „3.9.2“: Stelle für Stelle als Zahl vergleichen
function ns.CompareVersions(a, b)
    local pa, pb = {}, {}
    for n in tostring(a):gmatch("%d+") do table.insert(pa, tonumber(n)) end
    for n in tostring(b):gmatch("%d+") do table.insert(pb, tonumber(n)) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y and -1 or 1 end
    end
    return 0
end

-- Unter dem Raid-Eintrag speichern, damit auch Absender ohne Nachnamen passen
function Comm:SetVersion(sender, version)
    local m = ns.Raid:Find(sender)
    self.versions[m and m.key or ns.NameKey(sender)] = version
    self:CheckNewer(version)
end

-- Hat jemand eine neuere Version? Einmal pro Sitzung (und Version) Bescheid geben.
function Comm:CheckNewer(version)
    if not version or ns.VERSION == "dev" or ns.CompareVersions(version, ns.VERSION) <= 0 then return end
    if self.newest and ns.CompareVersions(version, self.newest) <= 0 then return end
    self.newest = version
    ns.Print("|cff40ff40Neue Version " .. version .. " verfügbar|r (du hast " .. ns.VERSION .. ") – Download: " .. ns.DOWNLOAD)
    ns:Fire("INFO_UPDATE")
end

Comm.handlers.HELLO = function(sender, parts)
    Comm:SetVersion(sender, parts[2])
    Comm:Send("VER", ns.VERSION, "WHISPER", sender)
    ns:Fire("ROSTER_UPDATE")
end

Comm.handlers.VER = function(sender, parts, channel)
    Comm:SetVersion(sender, parts[2])
    -- Meldung im Gildenkanal mit älterer Version: einmal die eigene, neuere zurückflüstern
    if channel == "GUILD" and parts[2] and ns.CompareVersions(ns.VERSION, parts[2]) > 0 then
        Comm.answered = Comm.answered or {}
        local key = ns.NameKey(sender)
        if key and not Comm.answered[key] then
            Comm.answered[key] = true
            Comm:Send("VER", ns.VERSION, "WHISPER", sender)
        end
    end
    ns:Fire("ROSTER_UPDATE")
end

-- Beim Einloggen die eigene Version einmal im Gildenkanal melden
ns:On("PLAYER_LOGIN", function()
    C_Timer.After(15, function()
        if IsInGuild() then Comm:Send("VER", ns.VERSION, "GUILD") end
    end)
end)

function Comm:Hello()
    self:Send("HELLO", ns.VERSION)
end

-- Stücke einer SendLarge-Nachricht sammeln; liefert die ganzen Daten, sobald alles da ist
function Comm:Assemble(sender, parts)
    local id, total, idx, chunk = parts[2], tonumber(parts[3]), tonumber(parts[4]), parts[5] or ""
    if not (id and total and idx) then return nil end
    local key = parts[1] .. sender .. id
    local entry = self.incoming[key]
    if not entry then
        -- Abgebrochene Übertragungen (Absender ausgeloggt) nicht ewig aufheben
        local now = GetTime()
        for k, old in pairs(self.incoming) do
            if now - old.last > 300 then self.incoming[k] = nil end
        end
        entry = { total = total, parts = {}, got = 0, msgType = parts[1], sender = sender }
        self.incoming[key] = entry
    end
    entry.last = GetTime()
    if not entry.parts[idx] then
        entry.parts[idx] = chunk
        entry.got = entry.got + 1
    end
    if entry.got >= entry.total then
        self.incoming[key] = nil
        return table.concat(entry.parts)
    end
end

-- Bei manchen Spielern verteilt der Server ihre Addon-Nachrichten im Gildenkanal nicht
-- (Flüstern klappt). Anfragen gehen deshalb zusätzlich per Flüstern an alle, von denen
-- wir schon Addon-Nachrichten bekommen haben und die gerade online sind.
function Comm:SendToSeen(msgType, payload)
    for key, name in pairs(self.seen) do
        local m = ns.Members and ns.Members.byKey[key]
        if m and m.online then self:Send(msgType, payload, "WHISPER", name) end
    end
end

-- Laufende Übertragungen eines Typs: { {sender, got, total}, … }
function Comm:Progress(msgType)
    local list = {}
    for _, e in pairs(self.incoming) do
        if e.msgType == msgType and GetTime() - (e.last or 0) < 120 then
            table.insert(list, { sender = e.sender, got = e.got, total = e.total })
        end
    end
    return list
end

-- /ea diagnose: was wurde gesendet und empfangen?
function Comm:Diagnose()
    local function List(t)
        local out = {}
        for k, n in pairs(t) do table.insert(out, k .. " " .. n) end
        table.sort(out)
        return #out > 0 and table.concat(out, ", ") or "nichts"
    end
    local st = self.stats
    ns.Print("Diagnose – Version " .. ns.VERSION .. (IsInGuild() and ", in einer Gilde" or ", |cffff6060keine Gilde|r"))
    print("  Warteschlange: " .. #self.queue .. " Nachrichten, Kontingent " .. math.floor(allowance))
    print("  Gesendet: " .. List(st.sent))
    local res = {}
    for k, n in pairs(st.results) do res["Code " .. k] = n end
    print("  Antwort des Servers: " .. List(res) .. "  (0 = ok, 3/8 = gedrosselt, 2 = ungültig)")
    print("  Empfangen: " .. List(st.recv))
    if st.guildSent > 0 then
        print(string.format("  Eigene Gildennachrichten als Echo zurück: %d von %d%s", st.echo, st.guildSent,
            st.echo == 0 and "  |cffff6060– der Server verteilt sie offenbar nicht|r" or ""))
    end
    for _, t in ipairs({ "PROF2", "PROF", "VER" }) do
        if st.from[t] then print("  Zuletzt " .. t .. " von " .. st.from[t]) end
    end
    for _, e in pairs(self.incoming) do
        print(string.format("  Unvollständig: %s von %s – %d von %d Stücken", e.msgType or "?", e.sender or "?", e.got, e.total))
    end
    local others, mine = 0, 0
    for _, c in pairs(ns.db.professions) do
        if c.mine then mine = mine + 1 else others = others + 1 end
    end
    print("  Berufe: " .. mine .. " eigene, " .. others .. " fremde Charaktere")
    local seen = {}
    for name, v in pairs(self.versions) do table.insert(seen, name .. " " .. v) end
    print("  Addon gesehen bei: " .. (#seen > 0 and table.concat(seen, ", ") or "niemandem"))
end

-- /ea ping: Kommen Gildennachrichten an? Einmal nur einfache Zeichen, einmal mit Umlauten.
-- Wer das Addon hat, meldet den Empfang im Chat und antwortet per Flüstern und über die Gilde.
local PING_TEXTS = { "abc", "Umlaute äöüî" }

function Comm:Ping()
    if not IsInGuild() then
        ns.Print("Du bist in keiner Gilde.")
        return
    end
    self.pingId = tostring(math.random(1000, 9999))
    for i, text in ipairs(PING_TEXTS) do
        self:Send("PING", table.concat({ self.pingId, i, text }, SEP), "GUILD")
    end
    ns.Print("Ping an die Gilde geschickt (1 ohne, 2 mit Umlauten) – die Antworten erscheinen hier.")
end

Comm.handlers.PING = function(sender, parts, channel)
    local nr = tonumber(parts[3])
    local intact = nr and PING_TEXTS[nr] == parts[4]
    if ns.Opt("notices") then
        ns.Print(string.format("Ping %s von %s über %s angekommen%s", parts[3] or "?", ns.ShortName(sender),
            channel or "?", intact and "" or " – |cffff6060Inhalt verändert|r"))
    end
    local answer = table.concat({ parts[2] or "", parts[3] or "", intact and "ok" or "kaputt" }, SEP)
    Comm:Send("PONG", answer, "WHISPER", sender)
    Comm:Send("PONG", answer, "GUILD")
end

Comm.handlers.PONG = function(sender, parts, channel)
    if not Comm.pingId or parts[2] ~= Comm.pingId then return end
    ns.Print(string.format("%s hat Ping %s %s erhalten%s – Antwort kam über %s", ns.ShortName(sender), parts[3] or "?",
        parts[3] == "2" and "(mit Umlauten)" or "(ohne Umlaute)", parts[4] == "ok" and "" or " |cffff6060(verändert)|r",
        channel == "GUILD" and "die Gilde" or "Flüstern"))
end

-- Softreserve-Sync -------------------------------------------------------
Comm.handlers.SRS = function(sender, parts)
    -- Jemand anderes verteilt die Liste bereits: eigene Antwort sparen
    Comm.srqPending = false
    local data = Comm:Assemble(sender, parts)
    if data and ns.IsTrusted(sender) then
        ns.SR:ImportSerialized(data, ns.ShortName(sender))
    end
end

-- Neues Mitglied fragt nach der Liste: ein Leiter/Assistent mit Daten antwortet,
-- zufällig verzögert, damit nicht alle gleichzeitig senden.
Comm.handlers.SRQ = function(sender)
    if Comm.srqPending or ns.SR:Count() == 0 or not ns.IsTrusted(ns.UnitFullName("player")) then return end
    Comm.srqPending = true
    C_Timer.After(2 + math.random() * 4, function()
        if Comm.srqPending then
            Comm.srqPending = false
            ns.SR:Broadcast(true)
        end
    end)
end

-- Beim Betreten einer Gruppe einmal melden und nach der SR-Liste fragen
local wasInGroup = false
local function CheckGroup()
    local inGroup = IsInGroup()
    if inGroup and not wasInGroup then
        C_Timer.After(3, function()
            if IsInGroup() then
                Comm:Hello()
                Comm:Send("SRQ")
            end
        end)
    end
    wasInGroup = inGroup
end

ns:On("GROUP_ROSTER_UPDATE", CheckGroup)
ns:On("PLAYER_ENTERING_WORLD", CheckGroup)
