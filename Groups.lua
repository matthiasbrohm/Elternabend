-- Elternabend: Gruppensuche in der Gilde
--
-- „Suche 2 für Barrow Deeps“: Wer eine Gruppe sucht, trägt ein, was und wen er
-- braucht. Alle mit Addon sehen es im Reiter „Gruppen“ und melden sich mit einem
-- Klick als Tank, Heiler oder DD. Der Suchende sieht die Meldungen und lädt ein.
--   LFG      id Was Tank Heiler DD Notiz Alter Gepostet   (Gilde; Gepostet = "1": steht schon im Gildenchat)
--   LFGEND   id                                  (Gilde)
--   LFGQ                                         (Gilde, beim Einloggen)
--   LFGJOIN  id Rolle Klasse [Twink]             (Flüstern an den Suchenden; Twink: mit diesem Charakter, loggt dafür um)
--   LFGANS   id Antwort                          (Flüstern zurück: invited / full / relog = „jetzt umloggen“)
--   LFGWHO   (SendLarge) id \n Rolle,Name,Klasse,Stand \n …   (Gilde: wer bei diesem Gesuch schon dabei oder gemeldet ist;
--            Stand: dabei / eingeladen / gemeldet / umloggen – der Suchende schickt es bei jeder Änderung)
local _, ns = ...

local Groups = { list = {}, applicants = {}, sent = {} }
ns.Groups = Groups

local MAX_AGE = 90 * 60 -- Gesuche verschwinden nach 90 Minuten
Groups.ROLES = { tank = "Tank", heal = "Heiler", dd = "DD" }
Groups.WEBSITE = "https://www.gilde-elternabend.de/dungeonfinder.php"

local function Clean(s)
    return (tostring(s or ""):gsub("[\t\r\n|]", " "))
end

-- Dungeons zur Auswahl (Reiter „Gruppen“): Name, Ort des Eingangs, empfohlene Stufen.
-- Dieselbe Liste wie im Dungeonfinder der Webseite (dungeons.php) – bei Änderungen beide anpassen.
Groups.DUNGEONS = {
    { name = "Halle der Thanen", zone = "Eisenschmiede", min = 13, max = 18 },
    { name = "Ruinen von Lordaeron", zone = "Tirisfal", min = 15, max = 20 },
    { name = "Die Todesminen", zone = "Westfall", min = 17, max = 26 },
    { name = "Die Höhlen des Wehklagens", zone = "Brachland", min = 17, max = 24 },
    { name = "Burg Schattenfang", zone = "Silberwald", min = 22, max = 30 },
    { name = "Das Verlies", zone = "Sturmwind", min = 22, max = 30 },
    { name = "Tiefschwarze Grotte", zone = "Eschental", min = 24, max = 32 },
    { name = "Ausgrabungsstätte: Sumpfland", zone = "Sumpfland", min = 24, max = 29 },
    { name = "Dalaran", zone = "Alteracgebirge", min = 28, max = 33 },
    { name = "Scharlachrotes Kloster: Friedhof", zone = "Tirisfal", min = 28, max = 34 },
    { name = "Gnomeregan", zone = "Dun Morogh", min = 29, max = 38 },
    { name = "Der Kral der Klingenhauer", zone = "Brachland", min = 29, max = 38 },
    { name = "Scharlachrotes Kloster: Bibliothek", zone = "Tirisfal", min = 30, max = 36 },
    { name = "Scharlachrotes Kloster: Waffenkammer", zone = "Tirisfal", min = 33, max = 38 },
    { name = "Scharlachrotes Kloster: Kathedrale", zone = "Tirisfal", min = 35, max = 42 },
    { name = "Die versunkene Stadt", zone = "Schlingendorntal", min = 35, max = 40 },
    { name = "Die Hügel der Klingenhauer", zone = "Brachland", min = 37, max = 46 },
    { name = "Festung Krol'dok", zone = "Flusslande", min = 40, max = 45 },
    { name = "Uldaman", zone = "Ödland", min = 41, max = 51 },
    { name = "Zul'Farrak", zone = "Tanaris", min = 44, max = 54 },
    { name = "Maraudon", zone = "Desolace", min = 46, max = 55 },
    { name = "Gefängnis der Insel Alcaz", zone = "Insel Alcaz", min = 48, max = 53 },
    { name = "Der Tempel von Atal'Hakkar", zone = "Sümpfe des Elends", min = 50, max = 56 },
    { name = "Schwarzfelstiefen", zone = "Schwarzfels", min = 52, max = 60 },
    { name = "Untere Schwarzfelsspitze", zone = "Schwarzfels", min = 55, max = 60 },
    { name = "Schwarzschlundfeste", zone = "Azshara", min = 55, max = 60 },
    { name = "Düsterbruch", zone = "Feralas", min = 56, max = 60 },
    { name = "Stratholme", zone = "Östliche Pestländer", min = 58, max = 60 },
    { name = "Scholomance", zone = "Westliche Pestländer", min = 58, max = 60 },
    { name = "Terrasse des Formers", zone = "Krater von Un'Goro", min = 58, max = 60 },
}

-- Suchwort je Dungeon: Name ohne Artikel, klein („todesminen“) – so passt auch „Todesminen ab Brücke“
for _, d in ipairs(Groups.DUNGEONS) do
    d.key = d.name:gsub("^Der ", ""):gsub("^Die ", ""):gsub("^Das ", ""):lower()
end

-- Dungeon zu einem Gesuchstext, oder nil (freie Gesuche wie „Hogger“ oder „PvP“). Bei mehreren Treffern
-- gewinnt der längste Name („Scharlachrotes Kloster: Friedhof“ vor allem Kürzeren).
function Groups.Dungeon(what)
    local text = tostring(what or ""):lower()
    local best
    for _, d in ipairs(Groups.DUNGEONS) do
        if text:find(d.key, 1, true) and (not best or #d.key > #best.key) then best = d end
    end
    return best
end

-- Passt die Stufe in den empfohlenen Bereich?
function Groups.Fits(d, level)
    return level ~= nil and level >= d.min and level <= d.max
end

-- Text für den Gildenchat, damit auch Mitglieder ohne Addon das Gesuch sehen
function Groups.ChatText(m)
    local text = "Suche für " .. Clean(m.what) .. " noch " .. Groups.NeedText(m.need)
    if m.note ~= "" then text = text .. " – " .. Clean(m.note) end
    text = text .. ". Mit Addon über /ea gruppen melden, sonst anflüstern!"
    -- Chatnachrichten dürfen höchstens 255 Zeichen haben; nicht mitten im Umlaut kürzen
    if #text > 255 then text = (text:sub(1, 252):gsub("[\192-\255][\128-\191]*$", "")) .. "…" end
    return text
end

-- Nachmeldung im Gildenchat: „Halle der Thanen: noch 1 Tank und 1 DD gesucht …“ oder „… Gruppe ist voll“
local function NeedKey(m)
    return m.full and "voll" or (m.need.tank .. "/" .. m.need.heal .. "/" .. m.need.dd)
end

function Groups.UpdateText(m)
    local need = m.need
    if m.full or need.tank + need.heal + need.dd == 0 then
        return Clean(m.what) .. ": Gruppe ist voll, danke!"
    end
    local parts = {}
    if need.tank > 0 then table.insert(parts, need.tank .. " Tank") end
    if need.heal > 0 then table.insert(parts, need.heal .. " Heiler") end
    if need.dd > 0 then table.insert(parts, need.dd .. " DD") end
    local list = #parts > 1 and (table.concat(parts, ", ", 1, #parts - 1) .. " und " .. parts[#parts]) or parts[1]
    local text = Clean(m.what) .. ": noch " .. list .. " gesucht – anflüstern oder /ea gruppen"
    if #text > 255 then text = (text:sub(1, 252):gsub("[\192-\255][\128-\191]*$", "")) .. "…" end
    return text
end

-- Stand das Gesuch im Gildenchat und ändern sich die offenen Plätze, kommt eine neue Zeile hinterher.
-- Kurz gesammelt: zwei Einladungen hintereinander ergeben nur eine Zeile. Nur mit Häkchen „Auch im Gildenchat posten“.
Groups.CHAT_DELAY = 5
function Groups:ChatUpdate(m)
    if not m or not m.posted or m.chatQueued then return end
    m.chatQueued = true
    C_Timer.After(self.CHAT_DELAY, function()
        m.chatQueued = nil
        if not ns.db.groups.chat or not IsInGuild() then return end
        if m ~= self.mine and not m.full then return end -- per Hand beendet: nichts mehr melden
        local key = NeedKey(m)
        if key == m.chatKey then return end -- z. B. erst mehr, dann wieder weniger: nichts geändert
        m.chatKey = key
        local text = Groups.UpdateText(m)
        ns.SendChat(text, "GUILD")
    end)
end

-- Eigenes Gesuch ---------------------------------------------------------------------
function Groups:Mine()
    return self.mine
end

-- role: als was der Suchende selbst mitgeht (tank/heal/dd) – erscheint bei den anderen unter „Wer ist dabei?“
function Groups:Post(what, need, note, role)
    what = strtrim(what or "")
    if what == "" then
        ns.Print("Bitte eintragen, wofür du eine Gruppe suchst.")
        return false
    end
    if not ns.Info:AtHome() then
        ns.Print("Die Gruppensuche läuft über die Gilde – sie gibt es nur für Charaktere in der Gilde.")
        return false
    end
    local mine = self.mine
    local isNew = mine == nil
    local before = mine and NeedKey(mine)
    if not mine then
        mine = { id = tostring(math.random(100000, 999999)), leader = ns.UnitFullName("player") }
        wipe(self.applicants)
    end
    mine.what, mine.note = what, strtrim(note or "")
    mine.role = Groups.ROLES[role or ""] and role or nil
    mine.need = { tank = need.tank or 0, heal = need.heal or 0, dd = need.dd or 0 }
    mine.started = mine.started or GetTime()
    -- Zielgröße: wer jetzt schon in der Gruppe ist plus die gesuchten Plätze.
    -- Ist die echte Gruppe so groß, endet das Gesuch von selbst (auch wenn per Hand eingeladen wurde).
    local total = mine.need.tank + mine.need.heal + mine.need.dd
    mine.target = math.max(1, GetNumGroupMembers()) + total
    -- Wer jetzt schon in der Gruppe ist: Wer später dazukommt, belegt einen der gesuchten Plätze
    mine.members = Groups.MemberKeys()
    self.mine = mine
    if total == 0 then
        if isNew then self.mine = nil; self.list[mine.id] = nil; ns.Print("Bitte mindestens einen freien Platz angeben.") return false end
        self:Broadcast()
        ns.Print("Keine Plätze mehr frei – dein Gesuch ist beendet.")
        mine.full = true
        self:ChatUpdate(mine)
        self:Close()
        return true
    end
    self.list[mine.id] = mine
    -- Beim Start die ganze Zeile in den Gildenchat; danach nur, wenn sich die offenen Plätze ändern
    if isNew and ns.db.groups.chat then
        mine.posted = true
        mine.chatKey = NeedKey(mine)
        local text = Groups.ChatText(mine)
        ns.WhenChatFree(function() C_ChatInfo.SendChatMessage(text, "GUILD") end)
    elseif not isNew and NeedKey(mine) ~= before then
        self:ChatUpdate(mine)
    end
    self:Broadcast()
    self:QueueWho()
    -- Eigene Nachrichten kommen nicht zurück: deshalb hier bestätigen
    ns.Print(string.format(isNew and "Dein Gesuch für %s ist in der Gilde unterwegs (%s)."
        or "Dein Gesuch für %s ist aktualisiert (%s).", what, self.NeedText(mine.need)))
    ns:Fire("GROUPS_UPDATE")
    return true
end

function Groups:Broadcast(channel, target)
    local m = self.mine
    if not m then return end
    ns.Comm:Send("LFG", table.concat({ m.id, Clean(m.what), m.need.tank, m.need.heal, m.need.dd, Clean(m.note),
        math.floor(GetTime() - m.started), m.posted and "1" or "" }, "\t"), channel or "GUILD", target)
end

function Groups:Close()
    local m = self.mine
    if not m then return end
    ns.Comm:Send("LFGEND", m.id, "GUILD")
    ns.Print("Dein Gesuch für " .. m.what .. " ist beendet.")
    self.list[m.id] = nil
    self.mine = nil
    wipe(self.applicants)
    ns:Fire("GROUPS_UPDATE")
end

-- Gesuch anpassen, sobald jemand eingeladen wurde: eine Stelle weniger
-- Wer sich mit einem anderen Charakter meldet, wird erst eingeladen, wenn dieser online ist.
-- Bis dahin heißt es „umloggen“: der Suchende bekommt Bescheid, sobald der Twink da ist.
local function Online(name)
    local m = ns.Members and ns.Members:Find(name)
    return m ~= nil and m.online == true
end

function Groups:Invite(applicant)
    local name = applicant.name
    if applicant.alt and not ns.SameName(applicant.alt, applicant.name) then
        if not Online(applicant.alt) then
            if applicant.state ~= "relog" then
                applicant.state = "relog"
                ns.Comm:Send("LFGANS", (self.mine and self.mine.id or "") .. "\trelog", "WHISPER", applicant.name)
            end
            ns.Print(string.format("%s ist noch nicht online – %s loggt jetzt um. Sobald er da ist, kannst du einladen.",
                ns.ShortName(applicant.alt), ns.ShortName(applicant.name)))
            self:QueueWho()
            ns:Fire("GROUPS_UPDATE")
            return
        end
        name = applicant.alt
    end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
    applicant.state = "invited"
    self:QueueWho()
    local m = self.mine
    ns.Comm:Send("LFGANS", (m and m.id or "") .. "\tinvited", "WHISPER", name)
    if name ~= applicant.name then ns.Comm:Send("LFGANS", (m and m.id or "") .. "\tinvited", "WHISPER", applicant.name) end
    if m and m.need[applicant.role] and m.need[applicant.role] > 0 then
        m.need[applicant.role] = m.need[applicant.role] - 1
        if m.need.tank + m.need.heal + m.need.dd == 0 then
            ns.Print("Gruppe komplett!")
            m.full = true
            self:ChatUpdate(m)
            self:Close()
            return
        end
        self:Broadcast()
        self:ChatUpdate(m)
    end
    ns:Fire("GROUPS_UPDATE")
end

function Groups:Decline(applicant)
    applicant.state = "declined"
    self:QueueWho()
    ns.Comm:Send("LFGANS", (self.mine and self.mine.id or "") .. "\tfull", "WHISPER", applicant.name)
    ns:Fire("GROUPS_UPDATE")
end

function Groups:Applicants()
    local list = {}
    for _, a in pairs(self.applicants) do table.insert(list, a) end
    table.sort(list, function(a, b) return a.time < b.time end)
    return list
end

-- Wer ist dabei? ------------------------------------------------------------------
-- Für das eigene Gesuch: wer schon in der Gruppe ist (mit gemeldeter Rolle, sonst der im Spiel gesetzten)
-- und wer sich gemeldet hat. Für fremde Gesuche: was der Suchende zuletzt geschickt hat (LFGWHO).
local GAME_ROLES = { TANK = "tank", HEALER = "heal", DAMAGER = "dd" }
local function Safe(v) return v ~= nil and not ns.IsSecret(v) and v or nil end

function Groups:Who(g)
    if not g then return nil end
    if g ~= self.mine then return g.who end
    local out, byName = {}, {}
    local function Add(role, name, classFile, state)
        local key = ns.NameKey(name)
        if not key or byName[key] then return end
        byName[key] = true
        out[#out + 1] = { role = role or "", name = ns.ShortName(name) or name, classFile = classFile or "", state = state }
    end
    -- zuerst der Suchende selbst, mit seiner Rolle
    local me = ns.UnitFullName("player")
    local _, myClass = UnitClass("player")
    if me then Add(g.role, me, Safe(myClass), "leitet") end
    -- Meldungen nach Name, damit Gruppenmitglieder ihre gemeldete Rolle behalten
    local applied = {}
    for _, a in pairs(self.applicants) do
        if a.state ~= "declined" then
            applied[ns.NameKey(a.alt or a.name) or ""] = a
            applied[ns.NameKey(a.name) or ""] = a
        end
    end
    if IsInGroup() then
        local raid = IsInRaid()
        for i = 1, raid and GetNumGroupMembers() or 4 do
            local unit = raid and ("raid" .. i) or ("party" .. i)
            if UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) then
                local name = Safe(ns.UnitFullName(unit))
                if name then
                    local a = applied[ns.NameKey(name) or ""]
                    local _, classFile = UnitClass(unit)
                    local role = a and a.role or GAME_ROLES[Safe(UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit)) or ""]
                    Add(role, name, Safe(classFile), "dabei")
                end
            end
        end
    end
    local list = self:Applicants()
    for _, a in ipairs(list) do
        if a.state ~= "declined" then
            local state = a.state == "invited" and "eingeladen" or a.state == "relog" and "umloggen" or "gemeldet"
            Add(a.role, a.alt or a.name, a.classFile ~= "" and a.classFile or nil, state)
        end
    end
    return out
end

-- Eigene Rolle ändern, während die Suche läuft
function Groups:SetMyRole(role)
    if self.mine then
        self.mine.role = self.ROLES[role or ""] and role or nil
        self:QueueWho()
        ns:Fire("GROUPS_UPDATE")
    end
end

-- Nach jeder Änderung (kurz gesammelt) an die Gilde schicken
local function WhoText(m)
    local lines = { m.id }
    for i, e in ipairs(Groups:Who(m)) do
        if i > 12 then break end
        lines[#lines + 1] = table.concat({ e.role, Clean(e.name):gsub(",", " "), e.classFile, e.state }, ",")
    end
    return table.concat(lines, "\n")
end

function Groups:SendWho(channel, target)
    if not self.mine or not ns.Info:AtHome() then return end
    ns.Comm:SendLarge("LFGWHO", WhoText(self.mine), channel or "GUILD", target)
end

function Groups:QueueWho()
    if not self.mine or self.whoQueued then return end
    self.whoQueued = true
    C_Timer.After(2, function()
        self.whoQueued = nil
        self:SendWho()
    end)
end

-- Neue Meldungen auf das eigene Gesuch (rote Plakette an „Eigene Gruppe“)
function Groups:NewApplicants()
    if not self.mine then return 0 end
    local n = 0
    for _, a in pairs(self.applicants) do
        if a.state == "new" then n = n + 1 end
    end
    return n
end

-- Gesuche der anderen -------------------------------------------------------------
-- Eigene Charaktere in dieser Gilde, mit denen man sich melden kann (der aktuelle zuerst, dann nach Stufe)
function Groups:MyCharacters()
    local guild = IsInGuild() and GetGuildInfo("player")
    local me = ns.PlayerKey()
    local list = {}
    for key, c in pairs(ns.db.myChars or {}) do
        if guild and c.guild == guild and c.name then
            list[#list + 1] = { key = key, name = c.name, classFile = c.classFile, level = c.level or 0, current = key == me }
        end
    end
    table.sort(list, function(a, b)
        if a.current ~= b.current then return a.current end
        if a.level ~= b.level then return a.level > b.level end
        return a.name < b.name
    end)
    return list
end

-- alt: Name eines eigenen anderen Charakters, mit dem man mitkommt (loggt dafür um) – oder nil
function Groups:Join(id, role, alt)
    local g = self.list[id]
    if not g or g == self.mine then return end
    local _, classFile = UnitClass("player")
    if alt and ns.SameName(alt, ns.UnitFullName("player")) then alt = nil end
    if alt then
        local c = ns.db.myChars[ns.NameKey(alt)]
        classFile = c and c.classFile or classFile
    end
    ns.Comm:Send("LFGJOIN", table.concat({ id, role, classFile or "", alt and Clean(alt) or "" }, "\t"), "WHISPER", g.leader)
    self.sent[id] = { role = role, state = "sent", alt = alt }
    ns.Print("Du hast dich bei " .. ns.ShortName(g.leader) .. " als " .. self.ROLES[role] .. " gemeldet"
        .. (alt and (" – mit " .. ns.ShortName(alt) .. ". Zum Einladen loggst du dann um.") or "."))
    ns:Fire("GROUPS_UPDATE")
end

-- Offene Gesuche, neueste zuerst; abgelaufene fallen raus
function Groups:List()
    local list = {}
    for id, g in pairs(self.list) do
        if GetTime() - g.started > MAX_AGE then
            self.list[id] = nil
        else
            table.insert(list, g)
        end
    end
    table.sort(list, function(a, b)
        if (a == self.mine) ~= (b == self.mine) then return a == self.mine end
        return a.started > b.started
    end)
    return list
end

-- Offene Gesuche anderer (für die Plakette am Reiter und an der Minimap)
function Groups:OpenCount()
    local count = 0
    for _, g in ipairs(self:List()) do
        if g ~= self.mine and (g.need.tank + g.need.heal + g.need.dd) > 0 then count = count + 1 end
    end
    return count
end

-- Gesehene Gesuche (Reiter „Gruppen“ war offen) zählen nicht mehr für die Plakette –
-- erst ein neues Gesuch zeigt sie wieder. Gespeichert, damit es nach neu laden so bleibt.
local SEEN_KEEP = 3 * 3600
function Groups:MarkSeen()
    local seen = ns.db.groups.seen
    local now = time()
    for id, g in pairs(self.list) do
        if g ~= self.mine then seen[id] = seen[id] or now end
    end
    for id, t in pairs(seen) do
        if now - t > SEEN_KEEP then seen[id] = nil end
    end
end

function Groups:UnseenCount()
    local count = 0
    local seen = ns.db and ns.db.groups.seen or {}
    for _, g in ipairs(self:List()) do
        if g ~= self.mine and not seen[g.id] and (g.need.tank + g.need.heal + g.need.dd) > 0 then count = count + 1 end
    end
    return count
end

function Groups.NeedText(need)
    local parts = {}
    if need.tank > 0 then table.insert(parts, need.tank .. " Tank") end
    if need.heal > 0 then table.insert(parts, need.heal .. " Heiler") end
    if need.dd > 0 then table.insert(parts, need.dd .. " DD") end
    return #parts > 0 and table.concat(parts, ", ") or "voll"
end

ns.Comm.handlers.LFG = function(sender, parts)
    if not ns.Info:AtHome() then return end -- Gruppensuche nur innerhalb der Gilde
    local id = parts[2]
    if not id or not parts[3] then return end
    local old = Groups.list[id]
    local isNew = old == nil
    Groups.list[id] = {
        id = id, leader = sender, what = parts[3], who = old and old.who or (Groups.whoEarly and Groups.whoEarly[id]),
        need = { tank = tonumber(parts[4]) or 0, heal = tonumber(parts[5]) or 0, dd = tonumber(parts[6]) or 0 },
        note = parts[7] or "", started = GetTime() - (tonumber(parts[8]) or 0),
    }
    -- Steht das Gesuch schon im Gildenchat, nicht noch einmal melden
    if isNew and (tonumber(parts[8]) or 0) < 60 and ns.db.groups.notify and parts[9] ~= "1" then
        local note = Groups.list[id].note
        ns.Print(string.format("%s sucht eine Gruppe für %s (%s)%s – /ea gruppen",
            ns.ShortName(sender), parts[3], Groups.NeedText(Groups.list[id].need), note ~= "" and (" – „" .. note .. "“") or ""))
    end
    ns:Fire("GROUPS_UPDATE")
end

ns.Comm.handlers.LFGEND = function(_, parts)
    if parts[2] then Groups.list[parts[2]] = nil end
    ns:Fire("GROUPS_UPDATE")
end

ns.Comm.handlers.LFGQ = function(sender)
    if Groups.mine and ns.Info:AtHome() then
        C_Timer.After(math.random() * 3, function()
            Groups:Broadcast("WHISPER", sender)
            Groups:SendWho("WHISPER", sender)
        end)
    end
end

-- Wer ist bei einem fremden Gesuch dabei? Nur vom Suchenden selbst angenommen.
ns.Comm.handlers.LFGWHO = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if not data or not ns.Info:AtHome() then return end
    local lines = { strsplit("\n", data) }
    local id = lines[1]
    if not id or id == "" then return end
    local who = {}
    for i = 2, #lines do
        local role, name, classFile, state = strsplit(",", lines[i])
        if name and name ~= "" and #who < 12 then
            who[#who + 1] = { role = Groups.ROLES[role or ""] and role or "", name = name, classFile = classFile or "", state = state or "gemeldet" }
        end
    end
    local g = Groups.list[id]
    if g then
        if not ns.SameName(sender, g.leader) then return end
        g.who = who
    else
        -- LFGWHO kam vor dem Gesuch an: kurz merken
        Groups.whoEarly = Groups.whoEarly or {}
        Groups.whoEarly[id] = who
    end
    ns:Fire("GROUPS_UPDATE")
end

ns.Comm.handlers.LFGJOIN = function(sender, parts)
    local m = Groups.mine
    if not m or parts[2] ~= m.id or not Groups.ROLES[parts[3]] then return end
    local key = ns.NameKey(sender)
    local alt = parts[5] ~= nil and parts[5] ~= "" and not ns.IsSecret(parts[5]) and parts[5] or nil
    Groups.applicants[key] = { name = sender, role = parts[3], classFile = parts[4], alt = alt, time = GetTime(), state = "new" }
    Groups:QueueWho()
    ns.Sound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master", true)
    ns.Print(string.format("%s möchte als %s mit%s – Reiter „Gruppen“ » „Eigene Gruppe“", ns.ShortName(sender), Groups.ROLES[parts[3]],
        alt and (" (mit " .. ns.ShortName(alt) .. ", loggt dafür um)") or ""))
    ns:Fire("GROUPS_UPDATE")
end

ns.Comm.handlers.LFGANS = function(sender, parts)
    local s = Groups.sent[parts[2] or ""]
    if not s then return end
    s.state = parts[3]
    if parts[3] == "full" then ns.Print(ns.ShortName(sender) .. ": Die Gruppe ist leider schon voll.") end
    if parts[3] == "relog" then
        ns.Sound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master", true)
        ns.Print(string.format("%s nimmt dich mit – logg jetzt auf %s um, dann kommt die Einladung.",
            ns.ShortName(sender), s.alt and ns.ShortName(s.alt) or "deinen anderen Charakter"))
    end
    ns:Fire("GROUPS_UPDATE")
end

-- Schlüssel aller, die gerade mit in der Gruppe sind (ohne einen selbst)
function Groups.MemberKeys()
    local keys = {}
    if not IsInGroup() then return keys end
    local raid = IsInRaid()
    for i = 1, raid and GetNumGroupMembers() or 4 do
        local unit = raid and ("raid" .. i) or ("party" .. i)
        if UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) then
            local key = ns.NameKey(Safe(ns.UnitFullName(unit)))
            if key then keys[key] = true end
        end
    end
    return keys
end

-- Per Hand eingeladen (nicht über „Einladen“ im Addon)? Dann sind weniger Plätze frei als gesucht:
-- die Rolle des Neuen abziehen (gemeldet oder im Spiel gesetzt), sonst zuerst DD, dann Heiler, dann Tank.
function Groups:AdjustNeed(members)
    local m = self.mine
    if not m or not m.target then return false end
    local free = m.target - members
    local total = m.need.tank + m.need.heal + m.need.dd
    if free >= total or free <= 0 then return false end
    local extra = total - free
    local before = m.members or {}
    for _, e in ipairs(self:Who(m)) do
        if extra == 0 then break end
        local key = ns.NameKey(e.name)
        if e.state == "dabei" and not before[key or ""] and m.need[e.role] and m.need[e.role] > 0 then
            m.need[e.role] = m.need[e.role] - 1
            extra = extra - 1
        end
    end
    for _, role in ipairs({ "dd", "heal", "tank" }) do
        while extra > 0 and m.need[role] > 0 do
            m.need[role] = m.need[role] - 1
            extra = extra - 1
        end
    end
    m.members = Groups.MemberKeys()
    self:Broadcast()
    self:ChatUpdate(m)
    ns.Print(string.format("Dein Gesuch für %s: jemand ist dazugekommen – gesucht wird noch %s.", m.what, self.NeedText(m.need)))
    ns:Fire("GROUPS_UPDATE")
    return true
end

-- Gruppe voll? Dann das eigene Gesuch automatisch beenden – daran denkt man sonst nicht
function Groups:CheckFull()
    local m = self.mine
    if not m or not m.target then return end
    local members = GetNumGroupMembers()
    if members < m.target then
        self:AdjustNeed(members)
        return
    end
    if members >= m.target then
        ns.Print(string.format("Deine Gruppe ist voll (%d Spieler) – das Gesuch für %s wird geschlossen.", members, m.what))
        m.full = true
        self:ChatUpdate(m)
        self:Close()
    end
end
ns:On("GROUP_ROSTER_UPDATE", function()
    -- kurz warten, falls mehrere gleichzeitig beitreten
    if Groups.fullCheckQueued then return end
    Groups.fullCheckQueued = true
    C_Timer.After(1, function()
        Groups.fullCheckQueued = false
        Groups:CheckFull()
        Groups:QueueWho() -- wer jetzt in der Gruppe ist, steht bei den anderen unter „Wer ist dabei?“
    end)
end)

-- Neu laden der Oberfläche (/reload, Design wechseln) soll das eigene Gesuch nicht beenden.
-- PLAYER_LOGOUT kommt in beiden Fällen; ob neu geladen wird, verrät nur ReloadUI selbst.
if hooksecurefunc and ReloadUI then
    hooksecurefunc("ReloadUI", function() Groups.reloading = true end)
end

local function Snapshot(g)
    return { id = g.id, leader = g.leader, what = g.what, note = g.note, posted = g.posted, chatKey = g.chatKey, target = g.target, role = g.role,
        need = { tank = g.need.tank, heal = g.need.heal, dd = g.need.dd }, members = g.members, age = GetTime() - g.started }
end

-- Beim Einloggen: nach neu laden das Gesuch zurückholen, sonst nach offenen Gesuchen fragen
ns:On("PLAYER_LOGIN", function()
    local saved = ns.db.groups.saved
    ns.db.groups.saved = nil
    local restored = false
    if saved and time() - (saved.at or 0) < 300 then
        local gap = time() - saved.at
        for _, g in ipairs(saved.list or {}) do
            g.started = GetTime() - g.age - gap
            g.age = nil
            Groups.list[g.id] = g
        end
        if saved.mine and saved.list then
            for _, g in ipairs(saved.list) do
                if g.id == saved.mine then Groups.mine = g end
            end
        end
        for key, a in pairs(saved.applicants or {}) do
            a.time = GetTime() - (a.age or 0) - gap
            a.age = nil
            Groups.applicants[key] = a
        end
        restored = Groups.mine ~= nil
        ns:Fire("GROUPS_UPDATE")
    end
    if restored then
        C_Timer.After(5, function()
            if Groups.mine and IsInGuild() then Groups:Broadcast() end
        end)
    end
    C_Timer.After((saved and 5 or 20) + math.random() * 10, function()
        if IsInGuild() then ns.Comm:Send("LFGQ", nil, "GUILD") end
    end)
end)

-- Ausloggen beendet das eigene Gesuch – neu laden nicht (dann merken und nach dem Laden weiter)
ns:On("PLAYER_LOGOUT", function()
    if Groups.reloading then
        -- Nur das eigene Gesuch: die der anderen kommen nach dem Laden frisch per LFGQ
        -- (sonst blieben inzwischen beendete stehen)
        local list = {}
        if Groups.mine then table.insert(list, Snapshot(Groups.mine)) end
        local applicants = {}
        for key, a in pairs(Groups.applicants) do
            applicants[key] = { name = a.name, role = a.role, classFile = a.classFile, state = a.state, age = GetTime() - a.time }
        end
        ns.db.groups.saved = { at = time(), list = list, mine = Groups.mine and Groups.mine.id, applicants = applicants }
        return
    end
    if Groups.mine then C_ChatInfo.SendAddonMessage(ns.PREFIX, "LFGEND\t" .. Groups.mine.id, "GUILD") end
end)

-- Twink eines Bewerbers ist jetzt online: dem Suchenden Bescheid geben (einladen muss er selbst)
ns:Listen("MEMBERS_UPDATE", function()
    if not Groups.mine then return end
    for _, a in pairs(Groups.applicants) do
        if a.state == "relog" and a.alt and not a.altOnline and Online(a.alt) then
            a.altOnline = true
            ns.Sound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master", true)
            ns.Print(string.format("%s ist jetzt online – du kannst einladen (/ea gruppen).", ns.ShortName(a.alt)))
            ns:Fire("GROUPS_UPDATE")
        end
    end
end)
