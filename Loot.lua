-- Elternabend Raid: Plündermeister (Beute erkennen, Würfelrunden, Vergabe, Verlauf)
local _, ns = ...

local Loot = { items = {}, current = nil }
ns.Loot = Loot

-- Plündermethode (verschiedene APIs je nach Classic-Version) -----------
function ns.GetLootMethod()
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        local method, partyID, raidID = C_PartyInfo.GetLootMethod()
        if type(method) == "number" then
            local ml = (Enum and Enum.LootMethod and (Enum.LootMethod.Masterlooter or Enum.LootMethod.MasterLooter)) or 2
            method = method == ml and "master" or tostring(method)
        end
        return method, partyID, raidID
    end
    if GetLootMethod then return GetLootMethod() end
end

-- Kann der Client Beute direkt per Plündermeister zuteilen?
function ns.CanGiveMasterLoot()
    return GiveMasterLoot ~= nil and GetMasterLootCandidate ~= nil and ns.IsMasterLooter()
end

function ns.IsMasterLooter()
    local method, partyID, raidID = ns.GetLootMethod()
    if method ~= "master" then return false end
    if IsInRaid() then
        return raidID ~= nil and UnitIsUnit("raid" .. raidID, "player")
    end
    return partyID == 0
end

-- Würfelergebnisse aus dem Systemchat lesen (funktioniert in jeder Sprache)
local rollPattern
local function GetRollPattern()
    if not rollPattern then
        local fmt = RANDOM_ROLL_RESULT or "%s rolls %d (%d-%d)"
        fmt = fmt:gsub("%%%d%$", "%%")
        fmt = fmt:gsub("([%(%)%.%-%+%[%]%*%?%^%$])", "%%%1")
        fmt = fmt:gsub("%%s", "(.+)")
        fmt = fmt:gsub("%%d", "(%%d+)")
        rollPattern = "^" .. fmt .. "$"
    end
    return rollPattern
end

-- Beute im Plündern-Fenster ------------------------------------------
function Loot:Scan()
    wipe(self.items)
    if ns.IsMasterLooter() then
        local minQuality = ns.db.settings.minQuality
        for slot = 1, GetNumLootItems() do
            local link = GetLootSlotLink(slot)
            local itemId = ns.ItemIDFromLink(link)
            if itemId then
                local quality = ns.GetItemQuality(link) or 0
                if quality >= minQuality or #ns.SR:GetReservers(itemId) > 0 then
                    table.insert(self.items, { slot = slot, link = link, itemId = itemId, quality = quality })
                end
            end
        end
        if #self.items > 0 and ns.db.settings.autoOpenLoot then ns.UI:Show("loot") end
    end
    ns:Fire("LOOT_UPDATE")
end

function Loot:FindSlot(itemId, preferredSlot)
    if preferredSlot and ns.ItemIDFromLink(GetLootSlotLink(preferredSlot)) == itemId then
        return preferredSlot
    end
    for slot = 1, GetNumLootItems() do
        if ns.ItemIDFromLink(GetLootSlotLink(slot)) == itemId then return slot end
    end
end

function Loot:FindCandidate(slot, key)
    for i = 1, 40 do
        local candidate = GetMasterLootCandidate(slot, i)
        if candidate and ns.SameName(candidate, key) then return i end
    end
end

-- SR-Spieler, die gerade in der Gruppe sind
function Loot:GetPresentReservers(itemId)
    local present = {}
    for _, n in ipairs(ns.SR:GetReserverNames(itemId)) do
        if ns.Raid:IsMember(n.key) and not n.won then table.insert(present, n) end
    end
    return present
end

-- Würfelrunde ------------------------------------------------------------
local function NewRound(item)
    return { itemId = item.itemId, link = item.link, slot = item.slot, rolls = {}, order = 0 }
end

function Loot:StartRoll(item)
    if self.current and self.current.active then
        ns.Print("Es läuft bereits eine Würfelrunde.")
        return
    end
    local s = ns.db.settings
    local cur = NewRound(item)
    local reservers = self:GetPresentReservers(item.itemId)
    cur.active = true
    cur.hasSR = #reservers > 0
    cur.duration = s.rollTime
    cur.endsAt = GetTime() + s.rollTime
    self.current = cur

    local msg
    if cur.hasSR then
        local names = {}
        for _, n in ipairs(reservers) do table.insert(names, n.label) end
        msg = string.format("%s – SR: %s – nur SR-Spieler /roll %d (%ds)", item.link, table.concat(names, ", "), s.msMax, s.rollTime)
        if #msg > 250 then
            msg = string.format("%s – %d SR-Spieler – /roll %d (%ds)", item.link, #names, s.msMax, s.rollTime)
        end
    else
        msg = string.format("%s – Hauptspec /roll %d, Off-Spec & Twinks /roll %d (%ds)", item.link, s.msMax, s.osMax, s.rollTime)
    end
    ns.Announce(msg, true)
    ns.Comm:Send("ROLL", item.link .. "\t" .. s.rollTime)

    self.lastCount = nil
    self.ticker = C_Timer.NewTicker(0.5, function() Loot:Tick() end)
    ns:Fire("ROLL_UPDATE")
end

function Loot:Tick()
    local cur = self.current
    if not cur or not cur.active then return end
    local left = math.ceil(cur.endsAt - GetTime())
    if left <= 0 then
        self:EndRoll()
        return
    end
    if (left == 5 or left <= 3) and self.lastCount ~= left then
        self.lastCount = left
        ns.Announce(left .. "…")
    end
end

function Loot:GetSortedRolls()
    local list = {}
    local cur = self.current
    if not cur then return list end
    local s = ns.db.settings
    for _, r in pairs(cur.rolls) do
        local tier, label
        if r.min ~= 1 then
            tier, label = 9, "ungültig"
        elseif r.max == s.msMax then
            if r.sr and cur.hasSR and s.srPriority then
                tier, label = 1, "SR"
            else
                tier, label = 2, "MS"
            end
        elseif r.max == s.osMax then
            tier, label = 3, "OS/Twink"
        else
            tier, label = 9, "ungültig"
        end
        r.tier, r.label, r.valid = tier, label, tier < 9
        table.insert(list, r)
    end
    table.sort(list, function(a, b)
        if a.tier ~= b.tier then return a.tier < b.tier end
        if a.roll ~= b.roll then return a.roll > b.roll end
        return a.order < b.order
    end)
    return list
end

function Loot:EndRoll(silent)
    local cur = self.current
    if not cur or not cur.active then return end
    cur.active = false
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    if not silent then
        local sorted = self:GetSortedRolls()
        local w, second = sorted[1], sorted[2]
        if not w or not w.valid then
            ns.Announce("Keine gültigen Würfe für " .. cur.link)
        elseif second and second.valid and second.tier == w.tier and second.roll == w.roll then
            ns.Announce(string.format("Gleichstand für %s: %s und %s (%d) – bitte nochmal würfeln!",
                cur.link, ns.ShortName(w.name), ns.ShortName(second.name), w.roll))
        else
            ns.Announce(string.format("Höchster Wurf für %s: %s (%d, %s)", cur.link, ns.ShortName(w.name), w.roll, w.label))
        end
    end
    ns:Fire("ROLL_UPDATE")
end

function Loot:CancelRoll()
    local cur = self.current
    if not cur then return end
    if cur.active then
        self:EndRoll(true)
        ns.Announce("Würfeln abgebrochen: " .. cur.link)
    end
    self.current = nil
    ns:Fire("ROLL_UPDATE")
end

-- Vergabe ----------------------------------------------------------------
-- Wenn das Plündern-Fenster offen ist, wird das Item direkt per Plündermeister
-- vergeben, sonst nur notiert (zum Handeln innerhalb von 2 Stunden).
function Loot:Award(name, item)
    if item then
        if self.current and self.current.active then self:EndRoll(true) end
        self.current = NewRound(item)
    end
    local cur = self.current
    if not cur or not name or strtrim(name) == "" then return end
    if cur.active then self:EndRoll(true) end

    local key = ns.NameKey(name)
    local member = ns.Raid:Find(name)
    local displayName = member and ns.ShortName(member.name) or strtrim(name)
    local viaTrade = true

    local slot = ns.CanGiveMasterLoot() and self:FindSlot(cur.itemId, cur.slot)
    if slot then
        local candidate = self:FindCandidate(slot, key)
        if not candidate then
            ns.Print(displayName .. " kann dieses Item nicht erhalten (nicht berechtigt oder nicht in der Nähe).")
            return
        end
        GiveMasterLoot(slot, candidate)
        viaTrade = false
    end

    local roll = cur.rolls[key]
    local sr = ns.SR:HasReserved(cur.itemId, key)
    if sr then ns.SR:MarkWon(cur.itemId, key) end

    table.insert(ns.db.history, 1, {
        time = time(), itemId = cur.itemId, link = cur.link, winner = displayName,
        roll = roll and roll.roll, label = roll and roll.label or "direkt",
        sr = sr, trade = viaTrade, zone = GetRealZoneText(),
        session = ns.Web:IsRunning() and ns.db.session.id or nil,
    })

    ns.Announce(string.format("%s erhält %s%s", displayName, cur.link, viaTrade and " (per Handel)" or ""))
    ns.Comm:Send("AWARD", cur.link .. "\t" .. displayName)
    self.current = nil
    ns:Fire("ROLL_UPDATE")
    ns:Fire("HISTORY_UPDATE")
end

-- Events -----------------------------------------------------------------
ns:On("LOOT_OPENED", function() Loot:Scan() end)
ns:On("LOOT_CLOSED", function()
    wipe(Loot.items)
    ns:Fire("LOOT_UPDATE")
end)
ns:On("LOOT_SLOT_CLEARED", function(slot)
    for i = #Loot.items, 1, -1 do
        if Loot.items[i].slot == slot then table.remove(Loot.items, i) end
    end
    ns:Fire("LOOT_UPDATE")
end)

ns:On("CHAT_MSG_SYSTEM", function(msg)
    local cur = Loot.current
    if not cur or not cur.active then return end
    -- Während der Chat-Sperre ist der Text verschleiert und nicht lesbar
    if ns.IsSecret(msg) then
        cur.secretRolls = true
        ns:Fire("ROLL_UPDATE")
        return
    end
    local name, roll, min, max = msg:match(GetRollPattern())
    if not name then return end
    local key = ns.NameKey(name)
    local existing = cur.rolls[key]
    if existing then
        existing.rerolls = (existing.rerolls or 0) + 1
    else
        cur.order = cur.order + 1
        cur.rolls[key] = { name = name, key = key, roll = tonumber(roll), min = tonumber(min), max = tonumber(max),
            order = cur.order, sr = ns.SR:HasReserved(cur.itemId, key) }
    end
    ns:Fire("ROLL_UPDATE")
end)

-- Hinweise für Raidmitglieder ohne Plündermeister-Rolle ----------------
ns.Comm.handlers.ROLL = function(sender, parts)
    local link, seconds = parts[2], parts[3]
    local itemId = ns.ItemIDFromLink(link)
    if not itemId then return end
    if ns.SR:HasReserved(itemId, ns.PlayerKey()) then
        ns.Print(string.format("|cff40ff40Deine Soft-Reserve wird ausgewürfelt:|r %s – /roll %d (%ss)", link, ns.db.settings.msMax, seconds or "?"))
        ns.Sound(SOUNDKIT.RAID_WARNING, nil, true)
    end
end

ns.Comm.handlers.AWARD = function(sender, parts)
    local link, winner = parts[2], parts[3]
    local itemId = ns.ItemIDFromLink(link)
    if itemId and winner then
        ns.SR:MarkWon(itemId, ns.NameKey(winner))
    end
end
