-- Elternabend: Loot-Wunschlisten (Vorbild „That's My BiS“)
--
-- Auf der Webseite (wunschliste.php) sortiert jeder pro Raid seine Wunsch-Items, die Gildenleitung legt pro Item
-- die Reihenfolge fest (Prio). Wird ein Raid nach Wunschliste verteilt, bringt der Raid-Text aus dem Raidplaner
-- diese Zeilen mit:
--   wunsch;Charakter;ItemID;Platz        wer das Item auf welchem Platz seiner Wunschliste hat
--   prio;ItemID;Charakter,Charakter,…    Reihenfolge, in der es vergeben wird
-- Das Addon zeigt die Prio im Tooltip und im Reiter Beute („An Prio“), merkt sich, wer schon etwas bekommen hat,
-- und verteilt die Liste mit „An Gruppe senden“ (zusammen mit den Soft-Reserves) an alle in der Gruppe.
-- Erhaltene Items landen wie immer im Raid-Bericht – die Webseite hakt sie dort ab.
local _, ns = ...

local WL = {}
ns.WL = WL

local SHOW_MAX = 5 -- so viele Namen im Tooltip

function WL:Data()
    return ns.db and ns.db.wishlist
end

-- Anzahl Items mit Prio
function WL:Count()
    local d, n = self:Data(), 0
    if d then for _ in pairs(d.prio) do n = n + 1 end end
    return n
end

-- prio: { [ItemID] = { "Name", … } }, wishes: { [ItemID] = { { name = …, rank = … }, … } }
function WL:Set(prio, wishes, title, importedAt)
    if next(prio) == nil and next(wishes) == nil then
        ns.db.wishlist = nil
    else
        ns.db.wishlist = { prio = prio, wishes = wishes, won = {}, title = title, importedAt = importedAt or time() }
    end
    ns:Fire("WISHLIST_UPDATE")
end

function WL:Clear()
    ns.db.wishlist = nil
    ns:Fire("WISHLIST_UPDATE")
end

-- Platz auf der Wunschliste (1 = am wichtigsten) oder nil
function WL:Rank(itemId, key)
    local d = self:Data()
    for _, w in ipairs(d and d.wishes[itemId] or {}) do
        if ns.NameKey(w.name) == key then return w.rank end
    end
end

-- Prio eines Items ohne die, die es schon bekommen haben: { { name, key, rank }, … }
function WL:Prio(itemId)
    local d = self:Data()
    local out = {}
    if not d or not d.prio[itemId] then return out end
    local won = d.won[itemId] or {}
    for _, name in ipairs(d.prio[itemId]) do
        local key = ns.NameKey(name)
        if key and not won[key] then table.insert(out, { name = name, key = key, rank = self:Rank(itemId, key) }) end
    end
    return out
end

-- Wer ist dran? Der Erste in der Prio, der gerade in der Gruppe ist.
function WL:Next(itemId)
    for _, p in ipairs(self:Prio(itemId)) do
        if ns.Raid:IsMember(p.key) then return p end
    end
end

function WL:MarkWon(itemId, name)
    local d, key = self:Data(), ns.NameKey(name)
    if not d or not key or not itemId then return end
    d.won[itemId] = d.won[itemId] or {}
    d.won[itemId][key] = true
    ns:Fire("WISHLIST_UPDATE")
end

-- Kurztext für Listen: „Beta Lux · danach Mira Mondschein“
function WL:Label(itemId)
    local nextUp = self:Next(itemId)
    if not nextUp then return nil end
    local after
    for _, p in ipairs(self:Prio(itemId)) do
        if p.key ~= nextUp.key and ns.Raid:IsMember(p.key) then after = p break end
    end
    return ns.ShortName(nextUp.name) .. (after and (" · danach " .. ns.ShortName(after.name)) or "")
end

-- Sync in der Gruppe -----------------------------------------------------
-- Format: Zeit;ItemID:Name,Name:Name/Platz,Name/Platz;… (Namen ohne Trennzeichen)
local function Clean(s)
    return ((s or ""):gsub("[:;,/\t|]", " "))
end

function WL:Serialize()
    local d = self:Data()
    if not d then return nil end
    local parts = { tostring(d.importedAt or 0) }
    local ids = {}
    for itemId in pairs(d.prio) do ids[itemId] = true end
    for itemId in pairs(d.wishes) do ids[itemId] = true end
    for itemId in pairs(ids) do
        local prio, wishes = {}, {}
        for _, p in ipairs(self:Prio(itemId)) do table.insert(prio, Clean(p.name)) end
        for _, w in ipairs(d.wishes[itemId] or {}) do
            local key = ns.NameKey(w.name)
            if not (d.won[itemId] and d.won[itemId][key]) then table.insert(wishes, Clean(w.name) .. "/" .. (w.rank or 0)) end
        end
        table.insert(parts, itemId .. ":" .. table.concat(prio, ",") .. ":" .. table.concat(wishes, ","))
    end
    return table.concat(parts, ";")
end

function WL:ImportSerialized(str, from)
    local importedAt
    local prio, wishes = {}, {}
    for token in (str or ""):gmatch("[^;]+") do
        if not importedAt then
            importedAt = tonumber(token) or 0
        else
            local itemId, p, w = strsplit(":", token)
            itemId = tonumber(itemId)
            if itemId then
                for name in (p or ""):gmatch("[^,]+") do
                    prio[itemId] = prio[itemId] or {}
                    table.insert(prio[itemId], strtrim(name))
                end
                for entry in (w or ""):gmatch("[^,]+") do
                    local name, rank = strsplit("/", entry)
                    if name and strtrim(name) ~= "" then
                        wishes[itemId] = wishes[itemId] or {}
                        table.insert(wishes[itemId], { name = strtrim(name), rank = tonumber(rank) or 0 })
                    end
                end
            end
        end
    end
    -- Eine neuere eigene Liste nicht überschreiben
    local own = self:Data()
    if own and (own.importedAt or 0) > (importedAt or 0) then return end
    self:Set(prio, wishes, "Sync von " .. (from or "?"), importedAt)
    self:PrintOwn()
end

-- Was betrifft mich? „Du bist laut Wunschliste als Nächstes dran bei: …“
function WL:PrintOwn()
    local d = self:Data()
    if not d then return end
    local me = ns.PlayerKey()
    local first, later = {}, 0
    for itemId in pairs(d.prio) do
        for i, p in ipairs(self:Prio(itemId)) do
            if p.key == me then
                if i == 1 then
                    local _, link = ns.GetItemInfo(itemId)
                    table.insert(first, link or ("Item " .. itemId))
                else
                    later = later + 1
                end
            end
        end
    end
    if #first > 0 then
        ns.Print("Wunschliste: Du bist als Nächstes dran bei " .. table.concat(first, ", ")
            .. (later > 0 and (" – und auf " .. later .. " weiteren Prio-Listen") or "") .. ".")
    elseif later > 0 then
        ns.Print("Wunschliste: Du stehst auf " .. later .. (later == 1 and " Prio-Liste." or " Prio-Listen."))
    end
end

ns.Comm.handlers.WLS = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if data and ns.IsTrusted(sender) then
        WL:ImportSerialized(data, ns.ShortName(sender))
    end
end

-- Tooltip: Wer ist laut Wunschliste dran? --------------------------------
local function AddTooltipLines(tooltip, itemId)
    if not itemId or not WL:Data() then return end
    local prio = WL:Prio(itemId)
    if #prio == 0 then return end
    local parts = {}
    for i, p in ipairs(prio) do
        if i > SHOW_MAX then
            table.insert(parts, "|cffccccccund " .. (#prio - SHOW_MAX) .. " weitere|r")
            break
        end
        local color = ns.Raid:IsMember(p.key) and "ff40ff40" or "ffcccccc"
        table.insert(parts, i .. ". |c" .. color .. ns.ShortName(p.name) .. "|r" .. (p.rank and (" |cff888888#" .. p.rank .. "|r") or ""))
    end
    tooltip:AddLine(" ")
    tooltip:AddLine("|cfff3dc9aPrio (Wunschliste):|r " .. table.concat(parts, ", "), 1, 1, 1, true)
end

ns:Listen("INIT", function()
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if (tooltip == GameTooltip or tooltip == ItemRefTooltip) and data and not ns.IsSecret(data.id)
            and ns.Opt("tooltipSR") then
            AddTooltipLines(tooltip, data.id)
        end
    end)
end)
