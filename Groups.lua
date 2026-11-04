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
    local text = "Suche Gruppe für " .. Clean(m.what) .. ": " .. Groups.NeedText(m.need)
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
    self.mine = mine
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

-- Beim Einloggen nach offenen Gesuchen fragen
ns:On("PLAYER_LOGIN", function()
    C_Timer.After(20 + math.random() * 10, function()
        if IsInGuild() then ns.Comm:Send("LFGQ", nil, "GUILD") end
    end)
end)
-- Ausloggen beendet das eigene Gesuch
ns:On("PLAYER_LOGOUT", function()
    if Groups.mine then C_ChatInfo.SendAddonMessage(ns.PREFIX, "LFGEND\t" .. Groups.mine.id, "GUILD") end
end)
