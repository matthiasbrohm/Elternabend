-- Elternabend: Ruhmeshalle – die Erstkills der Gilde
--
-- Fällt ein Raidboss zum ersten Mal in einer Gildengruppe (mindestens die Hälfte
-- aus der Gilde), merkt sich das Addon: wer, wann, welcher Schwierigkeitsgrad und
-- wer dabei war. Ein Addon aus dem Raid verteilt den Eintrag an die ganze Gilde.
--   FAME     (SendLarge)  Eintrag
--   FAMEQ    Anzahl       „Ich kenne so viele Einträge“ (beim Einloggen)
--   FAMEALL  (SendLarge)  alle Einträge, nur wenn jemand weniger kennt
local _, ns = ...

local Fame = {}
ns.Fame = Fame

local function DB()
    return ns.db.fame
end

local function Clean(s)
    return (tostring(s or ""):gsub("[#~\t\r\n|]", " "))
end

function Fame.Key(encounterID, difficultyID)
    return encounterID .. ":" .. (difficultyID or 0)
end

function Fame:Count()
    local n = 0
    for _ in pairs(DB()) do n = n + 1 end
    return n
end

function Fame:List()
    local list = {}
    for _, e in pairs(DB()) do table.insert(list, e) end
    table.sort(list, function(a, b) return a.time > b.time end)
    return list
end

-- Speichern; ein früherer Kill gewinnt
function Fame:Store(e)
    local key = Fame.Key(e.id, e.diff)
    local old = DB()[key]
    if old and old.time <= e.time then return false end
    DB()[key] = e
    ns:Fire("FAME_UPDATE")
    return true
end

-- Ein Eintrag als Text: Zeit#ID#Boss#Grad-ID#Grad#Raid#Spieler
function Fame:Serialize(e)
    return table.concat({ e.time, e.id, Clean(e.name), e.diff or 0, Clean(e.diffName), Clean(e.instance), Clean(e.players) }, "#")
end

function Fame:Parse(s)
    local f = { strsplit("#", s) }
    local t, id = tonumber(f[1]), tonumber(f[2])
    if not t or not id or not f[3] then return nil end
    return { time = t, id = id, name = f[3], diff = tonumber(f[4]) or 0, diffName = f[5] or "", instance = f[6] or "", players = f[7] or "" }
end

-- Gildengruppe: mindestens die Hälfte der Gruppe ist in der Gilde
function Fame:IsGuildGroup()
    if not IsInGuild() or not IsInGroup() then return false end
    local total, guild = 0, 0
    for _, m in ipairs(ns.Raid.members) do
        total = total + 1
        if m.unit and UnitIsInMyGuild(m.unit) then guild = guild + 1 end
    end
    return total > 0 and guild * 2 >= total
end

function Fame:OnKill(encounterID, encounterName, difficultyID)
    local instance, instanceType = GetInstanceInfo()
    if instanceType ~= "raid" or not self:IsGuildGroup() then return end
    local key = Fame.Key(encounterID, difficultyID)
    if DB()[key] then return end
    local names = {}
    for _, m in ipairs(ns.Raid.members) do
        if m.unit and UnitIsInMyGuild(m.unit) then table.insert(names, ns.ShortName(m.name)) end
    end
    table.sort(names)
    local e = {
        time = time(), id = encounterID, name = encounterName, diff = difficultyID,
        diffName = GetDifficultyInfo and GetDifficultyInfo(difficultyID) or "", instance = instance,
        players = table.concat(names, ", "),
    }
    self:Store(e)
    ns.Print("|cff40ff40Erstkill für die Gilde:|r " .. encounterName .. " – ab in die Ruhmeshalle!")
    -- Nur einer aus dem Raid verteilt: zufällig warten, wer zuerst sendet, gewinnt
    self.waiting = self.waiting or {}
    self.waiting[key] = true
    C_Timer.After(3 + math.random() * 12, function()
        if Fame.waiting[key] then
            Fame.waiting[key] = nil
            ns.WhenChatFree(function() ns.Comm:SendLarge("FAME", Fame:Serialize(e), "GUILD") end)
        end
    end)
end

ns:On("ENCOUNTER_END", function(encounterID, encounterName, difficultyID, _, success)
    if ns.IsSecret(encounterID) or ns.IsSecret(encounterName) or ns.IsSecret(success) or ns.IsSecret(difficultyID) then return end
    if success == 1 then Fame:OnKill(encounterID, encounterName, difficultyID) end
end)

ns.Comm.handlers.FAME = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    local e = data and Fame:Parse(data)
    if not e then return end
    if Fame.waiting then Fame.waiting[Fame.Key(e.id, e.diff)] = nil end
    Fame:Store(e)
end

-- Abgleich beim Einloggen ------------------------------------------------------------
function Fame:SendAll(channel, target)
    local parts = {}
    for _, e in pairs(DB()) do table.insert(parts, self:Serialize(e)) end
    if #parts > 0 then ns.Comm:SendLarge("FAMEALL", table.concat(parts, "~"), channel, target) end
end

ns.Comm.handlers.FAMEQ = function(sender, parts)
    local theirs = tonumber(parts[2]) or 0
    if Fame:Count() <= theirs then return end
    if Fame.answering then return end
    Fame.answering = true
    C_Timer.After(2 + math.random() * 8, function()
        Fame.answering = false
        Fame:SendAll("WHISPER", sender)
    end)
end

ns.Comm.handlers.FAMEALL = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if not data then return end
    for s in data:gmatch("[^~]+") do
        local e = Fame:Parse(s)
        if e then Fame:Store(e) end
    end
end

ns:On("PLAYER_LOGIN", function()
    C_Timer.After(35 + math.random() * 25, function()
        if IsInGuild() then ns.Comm:Send("FAMEQ", tostring(Fame:Count()), "GUILD") end
    end)
end)
