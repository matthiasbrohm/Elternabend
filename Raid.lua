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

-- Raidgruppen aus dem Raidplaner -----------------------------------------------------------
-- Der Export der Webseite enthält die geplanten Fünfergruppen („gruppe;1;Name;…“). Das Addon
-- sortiert den Schlachtzug danach: SetRaidSubgroup (freier Platz) und SwapRaidSubgroup (tauschen)
-- dürfen Addons in WoW Forever aufrufen – geprüft mit /ea gruppentest.
local MAX_GROUPS, GROUP_SIZE = 8, 5

function Raid:PlannedGroups()
    local plan = ns.db.plan
    return plan and plan.groups or nil
end

-- Für die Anzeige: je Gruppe die geplanten Spieler mit Stand
--   state: "ok" (in der richtigen Gruppe), "wrong" (im Raid, andere Gruppe), "missing" (nicht im Raid)
function Raid:GroupView()
    local groups = self:PlannedGroups()
    if not groups then return nil end
    local signups = ns.db.plan.signups or {}
    local view = {}
    for g = 1, MAX_GROUPS do
        view[g] = {}
        for _, name in ipairs(groups[g] or {}) do
            local key = ns.NameKey(name)
            local m = self:Find(name)
            local s = key and signups[key]
            table.insert(view[g], {
                name = name, member = m, class = s and s.class, role = s and s.role,
                state = not m and "missing" or (IsInRaid() and m.group ~= g and "wrong" or "ok"),
            })
        end
    end
    return view
end

-- Zielgruppe für jeden im Schlachtzug: Geplante in ihre Gruppe, alle anderen auf freie Plätze
-- (möglichst da, wo sie schon stehen). Liefert key -> Gruppe.
function Raid:GroupTargets()
    local groups = self:PlannedGroups() or {}
    local target, load = {}, {}
    for g = 1, MAX_GROUPS do load[g] = 0 end
    for g = 1, MAX_GROUPS do
        for _, name in ipairs(groups[g] or {}) do
            local m = self:Find(name)
            if m and not target[m.key] and load[g] < GROUP_SIZE then
                target[m.key] = g
                load[g] = load[g] + 1
            end
        end
    end
    -- Nicht Geplante: bleiben, wenn in ihrer Gruppe noch Platz ist – sonst von hinten auffüllen
    local rest = {}
    for _, m in ipairs(self.members) do
        if not target[m.key] then table.insert(rest, m) end
    end
    for _, m in ipairs(rest) do
        local g = m.group or 1
        if load[g] < GROUP_SIZE then
            target[m.key] = g
            load[g] = load[g] + 1
        end
    end
    for _, m in ipairs(rest) do
        if not target[m.key] then
            for g = MAX_GROUPS, 1, -1 do
                if load[g] < GROUP_SIZE then
                    target[m.key] = g
                    load[g] = load[g] + 1
                    break
                end
            end
        end
    end
    return target
end

-- Wie viele stehen noch falsch?
function Raid:GroupMismatches()
    if not IsInRaid() or not self:PlannedGroups() then return 0 end
    local target, n = self:GroupTargets(), 0
    for _, m in ipairs(self.members) do
        if target[m.key] and target[m.key] ~= m.group then n = n + 1 end
    end
    return n
end

local function RaidIndex(m)
    return tonumber((m.unit or ""):match("^raid(%d+)$"))
end

-- Ein Schritt: so viele Züge wie ohne Widerspruch möglich. Danach wartet der Bau auf die
-- neue Aufstellung vom Server (GROUP_ROSTER_UPDATE) und rechnet neu.
function Raid:BuildStep()
    local b = self.build
    if not b then return end
    if not IsInRaid() or not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return self:BuildStop("Abgebrochen – du bist nicht mehr Leiter oder Assistent im Schlachtzug.")
    end
    self:Update()
    local target = self:GroupTargets()
    local load, byGroup, moved = {}, {}, {}
    for g = 1, MAX_GROUPS do load[g], byGroup[g] = 0, {} end
    for _, m in ipairs(self.members) do
        local g = m.group or 1
        load[g] = load[g] + 1
        table.insert(byGroup[g], m)
    end
    local open, done = 0, 0
    for _, m in ipairs(self.members) do
        local t, idx = target[m.key], RaidIndex(m)
        if t and idx and t ~= m.group then
            open = open + 1
            if not moved[m.key] then
                if load[t] < GROUP_SIZE then
                    SetRaidSubgroup(idx, t)
                    load[t], load[m.group] = load[t] + 1, load[m.group] - 1
                    moved[m.key] = true
                    done = done + 1
                else
                    -- Platz tauschen mit jemandem, der dort nicht hingehört (am liebsten mit einem, der hierher soll)
                    local partner
                    for _, x in ipairs(byGroup[t]) do
                        if not moved[x.key] and target[x.key] ~= t and RaidIndex(x) then
                            if target[x.key] == m.group then partner = x break end
                            partner = partner or x
                        end
                    end
                    if partner then
                        SwapRaidSubgroup(idx, RaidIndex(partner))
                        moved[m.key], moved[partner.key] = true, true
                        done = done + 1
                    end
                end
            end
        end
    end
    if open == 0 then
        return self:BuildStop(b.steps == 0 and "Die Gruppen stehen schon wie geplant." or "Fertig – die Gruppen stehen wie geplant.", true)
    end
    b.steps = b.steps + 1
    if done == 0 or b.steps > 40 then
        return self:BuildStop("Nicht alle ließen sich verschieben (" .. open .. " stehen noch falsch). Bitte nochmal klicken oder von Hand ziehen.")
    end
    -- Weiter, sobald der Server die neue Aufstellung meldet – spätestens nach 1,5 Sekunden
    b.waiting = true
    local step = b.steps
    C_Timer.After(1.5, function()
        if Raid.build == b and b.waiting and b.steps == step then
            b.waiting = false
            Raid:BuildStep()
        end
    end)
end

function Raid:BuildStop(msg, ok)
    self.build = nil
    if msg then ns.Print((ok and "|cff40ff40" or "|cffffb35a") .. "Raidgruppen:|r " .. msg) end
    ns:Fire("ROSTER_UPDATE")
end

function Raid:BuildGroups()
    if not self:PlannedGroups() then
        ns.Print("Kein Raid mit Gruppen geladen. Auf der Webseite im Raidplaner den Text „Für das Addon“ kopieren und unter „Raid einfügen“ einfügen.")
        return
    end
    if not IsInRaid() then
        ns.Print("Gruppen bauen geht erst im Schlachtzug – bitte die Gruppe in einen Schlachtzug umwandeln.")
        return
    end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        ns.Print("Gruppen bauen darf nur, wer den Schlachtzug leitet oder Assistent ist.")
        return
    end
    if self.build then return end
    self.build = { steps = 0 }
    self:BuildStep()
end

ns:On("GROUP_ROSTER_UPDATE", function()
    local b = Raid.build
    if b and b.waiting then
        b.waiting = false
        -- kurz warten: nach mehreren Zügen kommen mehrere Meldungen hintereinander
        C_Timer.After(0.3, function()
            if Raid.build == b and not b.waiting then Raid:BuildStep() end
        end)
    end
end)

-- Geplante Spieler, die online, aber noch nicht im Raid sind, einladen
function Raid:InviteMissing()
    local view = self:GroupView()
    if not view then
        ns.Print("Kein Raid mit Gruppen geladen.")
        return
    end
    if IsInGroup() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        ns.Print("Einladen darf nur, wer die Gruppe leitet oder Assistent ist.")
        return
    end
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    local invited, offline = {}, 0
    local room = IsInRaid() and 40 or 5
    local count = math.max(1, GetNumGroupMembers())
    for g = 1, MAX_GROUPS do
        for _, e in ipairs(view[g]) do
            if e.state == "missing" then
                local gm = ns.Members and ns.Members:Find(e.name)
                -- online mit genau diesem Charakter (nicht mit einem Twink)
                if gm and gm.online and not ns.SameName(gm.name, ns.UnitFullName("player")) then
                    if count + #invited < room then
                        invite(gm.name)
                        table.insert(invited, ns.ShortName(gm.name))
                    end
                else
                    offline = offline + 1
                end
            end
        end
    end
    if #invited > 0 then
        ns.Print("Eingeladen: " .. table.concat(invited, ", ") .. "."
            .. (not IsInRaid() and " Für mehr als fünf bitte in einen Schlachtzug umwandeln und nochmal klicken." or ""))
    else
        ns.Print(offline > 0 and ("Niemand zum Einladen: " .. offline .. " geplante Spieler sind nicht (mit diesem Charakter) online.")
            or "Alle geplanten Spieler sind schon da.")
    end
end

-- Aufstellung im Raidchat ansagen: „Gruppe 1: A, B, C“
function Raid:AnnounceGroups()
    local groups = self:PlannedGroups()
    if not groups then return end
    for g = 1, MAX_GROUPS do
        local names = {}
        for _, name in ipairs(groups[g] or {}) do table.insert(names, ns.ShortName(name)) end
        if #names > 0 then ns.Announce("Gruppe " .. g .. ": " .. table.concat(names, ", ")) end
    end
end
