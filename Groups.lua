-- Elternabend: Gruppensuche in der Gilde
--
-- „Suche 2 für Barrow Deeps“: Wer eine Gruppe sucht, trägt ein, was und wen er
-- braucht. Alle mit Addon sehen es im Reiter „Gruppen“ und melden sich mit einem
-- Klick als Tank, Heiler oder DD. Der Suchende sieht die Meldungen und lädt ein.
--   LFG      id Was Tank Heiler DD Notiz Alter Gepostet   (Gilde; Gepostet = "1": steht schon im Gildenchat)
--   LFGEND   id                                  (Gilde)
--   LFGQ                                         (Gilde, beim Einloggen)
--   LFGJOIN  id Rolle Klasse                     (Flüstern an den Suchenden)
--   LFGANS   id Antwort                          (Flüstern zurück: eingeladen / voll)
local _, ns = ...

local Groups = { list = {}, applicants = {}, sent = {} }
ns.Groups = Groups

local MAX_AGE = 90 * 60 -- Gesuche verschwinden nach 90 Minuten
Groups.ROLES = { tank = "Tank", heal = "Heiler", dd = "DD" }
Groups.WEBSITE = "https://www.gilde-elternabend.de/dungeonfinder.php"

local function Clean(s)
    return (tostring(s or ""):gsub("[\t\r\n|]", " "))
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

-- Eigenes Gesuch ---------------------------------------------------------------------
function Groups:Mine()
    return self.mine
end

function Groups:Post(what, need, note)
    what = strtrim(what or "")
    if what == "" then
        ns.Print("Bitte eintragen, wofür du eine Gruppe suchst.")
        return false
    end
    if not IsInGuild() then
        ns.Print("Die Gruppensuche läuft über die Gilde.")
        return false
    end
    local mine = self.mine
    local isNew = mine == nil
    if not mine then
        mine = { id = tostring(math.random(100000, 999999)), leader = ns.UnitFullName("player") }
        wipe(self.applicants)
    end
    mine.what, mine.note = what, strtrim(note or "")
    mine.need = { tank = need.tank or 0, heal = need.heal or 0, dd = need.dd or 0 }
    mine.started = mine.started or GetTime()
    -- Zielgröße: wer jetzt schon in der Gruppe ist plus die gesuchten Plätze.
    -- Ist die echte Gruppe so groß, endet das Gesuch von selbst (auch wenn per Hand eingeladen wurde).
    local total = mine.need.tank + mine.need.heal + mine.need.dd
    mine.target = math.max(1, GetNumGroupMembers()) + total
    self.mine = mine
    if total == 0 then
        if isNew then self.mine = nil; self.list[mine.id] = nil; ns.Print("Bitte mindestens einen freien Platz angeben.") return false end
        self:Broadcast()
        ns.Print("Keine Plätze mehr frei – dein Gesuch ist beendet.")
        self:Close()
        return true
    end
    self.list[mine.id] = mine
    -- Nur beim Start einmal in den Gildenchat, nicht bei jeder Aktualisierung
    if isNew and ns.db.groups.chat then
        mine.posted = true
        local text = Groups.ChatText(mine)
        ns.WhenChatFree(function() C_ChatInfo.SendChatMessage(text, "GUILD") end)
    end
    self:Broadcast()
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
function Groups:Invite(applicant)
    local name = applicant.name
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
    applicant.state = "invited"
    local m = self.mine
    ns.Comm:Send("LFGANS", (m and m.id or "") .. "\tinvited", "WHISPER", name)
    if m and m.need[applicant.role] and m.need[applicant.role] > 0 then
        m.need[applicant.role] = m.need[applicant.role] - 1
        if m.need.tank + m.need.heal + m.need.dd == 0 then
            ns.Print("Gruppe komplett!")
            self:Close()
            return
        end
        self:Broadcast()
    end
    ns:Fire("GROUPS_UPDATE")
end

function Groups:Decline(applicant)
    applicant.state = "declined"
    ns.Comm:Send("LFGANS", (self.mine and self.mine.id or "") .. "\tfull", "WHISPER", applicant.name)
    ns:Fire("GROUPS_UPDATE")
end

function Groups:Applicants()
    local list = {}
    for _, a in pairs(self.applicants) do table.insert(list, a) end
    table.sort(list, function(a, b) return a.time < b.time end)
    return list
end

-- Gesuche der anderen -------------------------------------------------------------
function Groups:Join(id, role)
    local g = self.list[id]
    if not g or g == self.mine then return end
    local _, classFile = UnitClass("player")
    ns.Comm:Send("LFGJOIN", table.concat({ id, role, classFile or "" }, "\t"), "WHISPER", g.leader)
    self.sent[id] = { role = role, state = "sent" }
    ns.Print("Du hast dich bei " .. ns.ShortName(g.leader) .. " als " .. self.ROLES[role] .. " gemeldet.")
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
    local id = parts[2]
    if not id or not parts[3] then return end
    local isNew = Groups.list[id] == nil
    Groups.list[id] = {
        id = id, leader = sender, what = parts[3],
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
    if Groups.mine then
        C_Timer.After(math.random() * 3, function() Groups:Broadcast("WHISPER", sender) end)
    end
end

ns.Comm.handlers.LFGJOIN = function(sender, parts)
    local m = Groups.mine
    if not m or parts[2] ~= m.id or not Groups.ROLES[parts[3]] then return end
    local key = ns.NameKey(sender)
    Groups.applicants[key] = { name = sender, role = parts[3], classFile = parts[4], time = GetTime(), state = "new" }
    PlaySound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master")
    ns.Print(string.format("%s möchte als %s mit – /ea gruppen", ns.ShortName(sender), Groups.ROLES[parts[3]]))
    ns:Fire("GROUPS_UPDATE")
end

ns.Comm.handlers.LFGANS = function(sender, parts)
    local s = Groups.sent[parts[2] or ""]
    if not s then return end
    s.state = parts[3]
    if parts[3] == "full" then ns.Print(ns.ShortName(sender) .. ": Die Gruppe ist leider schon voll.") end
    ns:Fire("GROUPS_UPDATE")
end

-- Gruppe voll? Dann das eigene Gesuch automatisch beenden – daran denkt man sonst nicht
function Groups:CheckFull()
    local m = self.mine
    if not m or not m.target then return end
    local members = GetNumGroupMembers()
    if members >= m.target then
        ns.Print(string.format("Deine Gruppe ist voll (%d Spieler) – das Gesuch für %s wird geschlossen.", members, m.what))
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
    end)
end)

-- Neu laden der Oberfläche (/reload, Design wechseln) soll das eigene Gesuch nicht beenden.
-- PLAYER_LOGOUT kommt in beiden Fällen; ob neu geladen wird, verrät nur ReloadUI selbst.
if hooksecurefunc and ReloadUI then
    hooksecurefunc("ReloadUI", function() Groups.reloading = true end)
end

local function Snapshot(g)
    return { id = g.id, leader = g.leader, what = g.what, note = g.note, posted = g.posted, target = g.target,
        need = { tank = g.need.tank, heal = g.need.heal, dd = g.need.dd }, age = GetTime() - g.started }
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
