-- Elternabend Raid: Soft-Reserve-Liste (Import, Abfragen, Sync, Tooltip)
local _, ns = ...

local SR = { byPlayer = {} }
ns.SR = SR

local EMPTY = {}

-- Daten ------------------------------------------------------------------
function SR:Data()
    return ns.db.softres
end

function SR:RebuildIndex()
    wipe(self.byPlayer)
    for itemId, list in pairs(self:Data().items) do
        for _, e in ipairs(list) do
            local items = self.byPlayer[e.key]
            if not items then
                items = {}
                self.byPlayer[e.key] = items
            end
            table.insert(items, itemId)
        end
    end
end

function SR:Count()
    local n = 0
    for _, list in pairs(self:Data().items) do n = n + #list end
    return n
end

function SR:GetReservers(itemId)
    return (itemId and self:Data().items[itemId]) or EMPTY
end

-- Findet die Reserves auch, wenn eine Seite nur den Vornamen kennt
function SR:GetPlayerItems(name)
    local key = ns.NameKey(name)
    if not key then return EMPTY end
    if self.byPlayer[key] then return self.byPlayer[key] end
    for k, items in pairs(self.byPlayer) do
        if ns.SameName(k, key) then return items end
    end
    return EMPTY
end

function SR:HasReserved(itemId, name)
    for _, e in ipairs(self:GetReservers(itemId)) do
        if ns.SameName(e.key, name) then return true end
    end
    return false
end

function SR:MarkWon(itemId, name)
    for _, e in ipairs(self:GetReservers(itemId)) do
        if ns.SameName(e.key, name) and not e.won then
            e.won = true
            ns:Fire("SR_UPDATE")
            return
        end
    end
end

-- Zusammengefasste Namen: "Thrall, Jaina x2"
function SR:GetReserverNames(itemId)
    local counts, order = {}, {}
    for _, e in ipairs(self:GetReservers(itemId)) do
        if not counts[e.key] then
            counts[e.key] = { name = e.name, n = 0, won = false }
            table.insert(order, e.key)
        end
        counts[e.key].n = counts[e.key].n + 1
        counts[e.key].won = counts[e.key].won or e.won
    end
    local result = {}
    for _, key in ipairs(order) do
        local c = counts[key]
        table.insert(result, { key = key, name = c.name, count = c.n, won = c.won,
            label = c.n > 1 and (c.name .. " x" .. c.n) or c.name })
    end
    return result
end

function SR:SetEntries(entries, source, importedAt)
    local data = self:Data()
    wipe(data.items)
    for _, e in ipairs(entries) do
        e.key = ns.NameKey(e.name)
        data.items[e.itemId] = data.items[e.itemId] or {}
        table.insert(data.items[e.itemId], e)
    end
    data.importedAt = importedAt or time()
    data.source = source
    self:RebuildIndex()
    ns:Fire("SR_UPDATE")
    ns:Fire("ROSTER_UPDATE")
end

function SR:Clear()
    self:SetEntries({}, nil, 0)
    ns.Print("Soft-Reserve-Liste geleert.")
end

-- Import -----------------------------------------------------------------
local function ParseCSVLine(line, sep)
    local result, field, inQuotes = {}, {}, false
    local i, len = 1, #line
    while i <= len do
        local c = line:sub(i, i)
        if inQuotes then
            if c == '"' then
                if line:sub(i + 1, i + 1) == '"' then
                    table.insert(field, '"')
                    i = i + 1
                else
                    inQuotes = false
                end
            else
                table.insert(field, c)
            end
        elseif c == '"' then
            inQuotes = true
        elseif c == sep then
            table.insert(result, strtrim(table.concat(field)))
            field = {}
        else
            table.insert(field, c)
        end
        i = i + 1
    end
    table.insert(result, strtrim(table.concat(field)))
    return result
end

local function FindColumn(cols, ...)
    for i = 1, select("#", ...) do
        local idx = cols[select(i, ...)]
        if idx then return idx end
    end
end

-- Unterstützt:
--  1) softres.it CSV-Export (Kopfzeile mit "ItemId" und "Name")
--  2) Einfache Listen, z.B. "Thrall: 19019, 17076" oder "Thrall,19019"
function SR:Parse(text)
    local lines = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        line = strtrim(line)
        if line ~= "" then table.insert(lines, line) end
    end
    if #lines == 0 then return nil, "Kein Text eingefügt." end

    local entries = {}
    local first = lines[1]
    local sep = (first:find(";") and not first:find(",")) and ";" or ","
    local header = ParseCSVLine(first, sep)
    local cols = {}
    for i, h in ipairs(header) do
        local key = h:lower():gsub("[%s_\"]", "")
        cols[key] = i
    end

    local cId = FindColumn(cols, "itemid", "id")
    local cName = FindColumn(cols, "name", "player", "spieler", "charakter", "character")

    if cId and cName then
        local cItem = FindColumn(cols, "item", "itemname")
        local cBoss = FindColumn(cols, "from", "boss", "source")
        local cClass = FindColumn(cols, "class", "klasse")
        local cSpec = FindColumn(cols, "spec")
        local cNote = FindColumn(cols, "note", "notiz")
        local cPlus = FindColumn(cols, "plus")
        for i = 2, #lines do
            local f = ParseCSVLine(lines[i], sep)
            local itemId = tonumber(f[cId])
            local name = f[cName]
            if itemId and name and name ~= "" then
                table.insert(entries, {
                    itemId = itemId,
                    name = name,
                    itemName = cItem and f[cItem] or nil,
                    boss = cBoss and f[cBoss] or nil,
                    class = cClass and f[cClass] or nil,
                    spec = cSpec and f[cSpec] or nil,
                    note = cNote and f[cNote] or nil,
                    plus = cPlus and tonumber(f[cPlus]) or 0,
                })
            end
        end
    else
        for _, line in ipairs(lines) do
            local name = line:match("^([^%d,;:]+)")
            name = name and strtrim(name)
            if name and name ~= "" then
                for id in line:gmatch("(%d+)") do
                    table.insert(entries, { itemId = tonumber(id), name = name, plus = 0 })
                end
            end
        end
    end

    if #entries == 0 then
        return nil, "Keine Einträge erkannt. Bitte den Text aus dem Raidplaner (oder den CSV-Export von softres.it) einfügen."
    end
    return entries
end

function SR:Import(text)
    local entries, err = self:Parse(text)
    if not entries then
        ns.Print("|cffff5555Import fehlgeschlagen:|r " .. err)
        return false
    end
    self:SetEntries(entries, "Import")
    local players = 0
    for _ in pairs(self.byPlayer) do players = players + 1 end
    ns.Print(string.format("%d Soft-Reserves von %d Spielern importiert.", #entries, players))
    if IsInGroup() and ns.IsTrusted(ns.UnitFullName("player")) then
        ns.Print("Tipp: Mit „An Gruppe senden“ sehen alle Raidmitglieder die Liste.")
    end
    return true
end

-- Sync -------------------------------------------------------------------
local function Clean(s)
    return ((s or ""):gsub("[:;\t|]", " "))
end

function SR:Serialize()
    local data = self:Data()
    local parts = { tostring(data.importedAt or 0) }
    for itemId, list in pairs(data.items) do
        for _, e in ipairs(list) do
            table.insert(parts, table.concat({ itemId, Clean(e.name), e.plus or 0, e.won and 1 or 0, Clean(e.boss) }, ":"))
        end
    end
    return table.concat(parts, ";")
end

function SR:ImportSerialized(str, from)
    local importedAt
    local entries = {}
    for token in str:gmatch("[^;]+") do
        if not importedAt then
            importedAt = tonumber(token) or 0
        else
            local itemId, name, plus, won, boss = strsplit(":", token)
            itemId = tonumber(itemId)
            if itemId and name and name ~= "" then
                table.insert(entries, { itemId = itemId, name = name, plus = tonumber(plus) or 0,
                    won = won == "1", boss = (boss and boss ~= "") and boss or nil })
            end
        end
    end
    -- Eine neuere eigene Liste nicht überschreiben
    if (self:Data().importedAt or 0) > (importedAt or 0) then return end
    self:SetEntries(entries, "Sync von " .. from, importedAt)
    ns.Print(string.format("Soft-Reserve-Liste von %s empfangen (%d Einträge).", from, #entries))
    self:PrintOwn()
end

function SR:PrintOwn()
    local items = self:GetPlayerItems(ns.PlayerKey())
    if #items == 0 then
        if self:Count() > 0 then ns.Print("|cffff5555Du hast keine Soft-Reserve eingetragen!|r") end
        return
    end
    local links = {}
    for _, itemId in ipairs(items) do
        local _, link = ns.GetItemInfo(itemId)
        table.insert(links, link or ("Item " .. itemId))
    end
    ns.Print("Deine Soft-Reserves: " .. table.concat(links, ", "))
end

function SR:Broadcast(silent)
    if not IsInGroup() then
        if not silent then ns.Print("Du bist in keiner Gruppe.") end
        return
    end
    if not ns.IsTrusted(ns.UnitFullName("player")) then
        if not silent then ns.Print("Nur Leiter und Assistenten können die Liste verteilen.") end
        return
    end
    if self:Count() == 0 then
        if not silent then ns.Print("Keine Soft-Reserve-Liste geladen.") end
        return
    end
    ns.Comm:SendLarge("SRS", self:Serialize())
    if not silent then ns.Print("Soft-Reserve-Liste wird an die Gruppe gesendet.") end
end

-- Tooltip: Wer hat das Item reserviert? -----------------------------
local function AddTooltipLines(tooltip, itemId)
    if not itemId or not ns.db then return end
    local names = SR:GetReserverNames(itemId)
    if #names == 0 then return end
    local parts = {}
    for _, n in ipairs(names) do
        local color = n.won and "ff888888" or (ns.Raid:IsMember(n.key) and "ff40ff40" or "ffcccccc")
        table.insert(parts, "|c" .. color .. n.label .. (n.won and " (erhalten)" or "") .. "|r")
    end
    tooltip:AddLine(" ")
    tooltip:AddLine("|cfff3dc9aSoft-Reserve:|r " .. table.concat(parts, ", "), 1, 1, 1, true)
end

ns:Listen("INIT", function()
    SR:RebuildIndex()

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if (tooltip == GameTooltip or tooltip == ItemRefTooltip) and data and not ns.IsSecret(data.id)
            and ns.Opt("tooltipSR") then
            AddTooltipLines(tooltip, data.id)
        end
    end)
end)
