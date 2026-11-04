-- Elternabend Raid: Raid-Übersicht (Mitglieder, Anmeldungen, Bereitschaftscheck)
local _, ns = ...

local Raid = { members = {}, byKey = {}, ready = {} }
ns.Raid = Raid

local PARTY_UNITS = { "player", "party1", "party2", "party3", "party4" }

local ROLE_FROM_CLIENT = { TANK = "tank", HEALER = "heal", DAMAGER = "dd" }

-- Status aus dem Raidplaner → Zeile in der Übersicht (anwesend / fehlt)
local PRESENT_STATE = { ersatz = "bench", abgemeldet = "declined", vielleicht = "maybe" }
local MISSING_STATE = { ersatz = "benchMissing", vielleicht = "maybeMissing" }

local function AddMember(m)
    m.key = ns.NameKey(m.name)
    if not m.key then return end
    table.insert(Raid.members, m)
    Raid.byKey[m.key] = m
end

-- Zusätzlich unter dem Vornamen finden, wenn der im Raid eindeutig ist
local function AddFirstNameAliases()
    local count = {}
    for _, m in ipairs(Raid.members) do
        local first = ns.FirstKey(m.key)
        count[first] = (count[first] or 0) + 1
    end
    for _, m in ipairs(Raid.members) do
        local first = ns.FirstKey(m.key)
        if count[first] == 1 and not Raid.byKey[first] then Raid.byKey[first] = m end
    end
end

function Raid:Update()
    -- Während Bossbegegnungen können Namen verschleiert sein: dann alten Stand behalten
    if IsInRaid() then
        local first = GetRaidRosterInfo(1)
        if ns.IsSecret(first) then return end
    end

    wipe(self.members)
    wipe(self.byKey)

    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local name, rank, subgroup, level, class, classFile, zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(i)
            name = ns.UnitFullName("raid" .. i) or name
            if name and not ns.IsSecret(name) then
                AddMember({ unit = "raid" .. i, name = name, rank = rank, group = subgroup, level = level,
                    class = class, classFile = classFile, zone = zone, online = online, dead = isDead,
                    role = role, isML = isML, combatRole = ROLE_FROM_CLIENT[combatRole] })
            end
        end
    else
        for _, unit in ipairs(PARTY_UNITS) do
            if UnitExists(unit) then
                local name = ns.UnitFullName(unit)
                if name and not ns.IsSecret(name) then
                    local class, classFile = UnitClass(unit)
                    AddMember({ unit = unit, name = name, rank = UnitIsGroupLeader(unit) and 2 or 0,
                        group = 1, level = UnitLevel(unit), class = class, classFile = classFile,
                        zone = unit == "player" and GetRealZoneText() or nil,
                        online = UnitIsConnected(unit), dead = UnitIsDeadOrGhost(unit),
                        combatRole = ROLE_FROM_CLIENT[UnitGroupRolesAssigned(unit)] })
                end
            end
        end
    end

    AddFirstNameAliases()
    table.sort(self.members, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.name < b.name
    end)
    ns:Fire("ROSTER_UPDATE")
end

function Raid:Find(name)
    local key = ns.NameKey(name)
    return key and (self.byKey[key] or self.byKey[ns.FirstKey(key)])
end

function Raid:IsMember(name)
    return self:Find(name) ~= nil
end

function Raid:GetMasterLooterName()
    for _, m in ipairs(self.members) do
        if m.isML then return m.name end
    end
    local method, partyID = ns.GetLootMethod()
    if method == "master" and not IsInRaid() and partyID then
        return ns.UnitFullName(partyID == 0 and "player" or ("party" .. partyID))
    end
end

-- Abgleich mit den Anmeldungen aus dem Raidplaner -------------------------
-- Liefert alle Zeilen für die Raid-Übersicht: anwesende Mitglieder (mit ihrer
-- Anmeldung, falls vorhanden) und angemeldete Spieler, die noch fehlen.
function Raid:GetOverview()
    local rows = {}
    local plan = ns.db.plan
    local signups = plan and plan.signups or {}

    for _, m in ipairs(self.members) do
        local s = signups[m.key] or signups[ns.FirstKey(m.key)]
        table.insert(rows, { member = m, signup = s, key = m.key, name = m.name,
            state = s and (PRESENT_STATE[s.status] or "ok") or (plan and "unplanned" or "ok") })
    end
    for key, s in pairs(signups) do
        if not self:Find(key) and s.status ~= "abgemeldet" then
            table.insert(rows, { signup = s, key = key, name = s.name,
                state = MISSING_STATE[s.status] or "missing" })
        end
    end
    return rows
end

function Raid:AnnounceMissingSR()
    if ns.SR:Count() == 0 then
        ns.Print("Keine Soft-Reserve-Liste geladen.")
        return
    end
    local missing = {}
    for _, m in ipairs(self.members) do
        if #ns.SR:GetPlayerItems(m.key) == 0 then
            table.insert(missing, ns.ShortName(m.name))
        end
    end
    if #missing == 0 then
        ns.Announce("Alle haben ihre Soft-Reserves eingetragen!")
    else
        ns.AnnounceList("Noch keine Soft-Reserve: ", missing)
    end
end

function Raid:AnnounceMissingSignups()
    local plan = ns.db.plan
    if not plan then
        ns.Print("Kein Raid aus dem Raidplaner geladen.")
        return
    end
    local missing = {}
    for _, row in ipairs(self:GetOverview()) do
        if row.state == "missing" then table.insert(missing, ns.ShortName(row.name)) end
    end
    if #missing == 0 then
        ns.Print("Alle Angemeldeten sind da.")
    else
        ns.AnnounceList("Angemeldet, aber noch nicht im Raid: ", missing)
    end
end

-- Bereitschaftscheck ------------------------------------------------------
ns:On("READY_CHECK", function(initiator)
    wipe(Raid.ready)
    for _, m in ipairs(Raid.members) do Raid.ready[m.key] = "waiting" end
    local m = Raid:Find(initiator)
    if m then Raid.ready[m.key] = "ready" end
    ns:Fire("ROSTER_UPDATE")
end)

ns:On("READY_CHECK_CONFIRM", function(unit, isReady)
    local m = Raid:Find(ns.UnitFullName(unit))
    if m then Raid.ready[m.key] = isReady and "ready" or "notready" end
    ns:Fire("ROSTER_UPDATE")
end)

ns:On("READY_CHECK_FINISHED", function()
    for key, state in pairs(Raid.ready) do
        if state == "waiting" then Raid.ready[key] = "afk" end
    end
    ns:Fire("ROSTER_UPDATE")
end)

ns:On("GROUP_ROSTER_UPDATE", function() Raid:Update() end)
ns:On("PLAYER_ENTERING_WORLD", function() Raid:Update() end)
