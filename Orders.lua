-- Elternabend: Handwerksaufträge
--
-- Im Reiter „Berufe“ schickt man einem Hersteller mit einem Klick einen Auftrag
-- („Kannst du mir das bauen? Mats habe ich“). Der Hersteller sieht offene Aufträge
-- gesammelt, nimmt sie an, meldet „fertig“ oder lehnt ab.
-- Ist der Empfänger gerade nicht online, geht die Nachricht an einen seiner anderen
-- Charaktere – oder wartet, bis einer von ihnen online kommt.
--   ORDER     id Rezept-ID Hersteller Notiz   Besteller → Hersteller
--   ORDERACK  id                              Hersteller → Besteller: angekommen
--   ORDERST   id Status                       in beide Richtungen
local _, ns = ...

local Orders = {}
ns.Orders = Orders

local KEEP_DAYS = 14
Orders.STATES = {
    wartet = { "Wartet auf Zustellung", "dim" },
    zugestellt = { "Zugestellt", "goldBright" },
    neu = { "Neu", "goldBright" },
    angenommen = { "Angenommen", "green" },
    fertig = { "Fertig", "green" },
    abgelehnt = { "Abgelehnt", "red" },
    storniert = { "Zurückgezogen", "dim" },
}

local function DB()
    return ns.db.orders
end

local function Clean(s)
    return (tostring(s or ""):gsub("[\t\r\n|]", " "))
end

-- Zustellung --------------------------------------------------------------------------
-- Derselbe Spieler (Main und Twinks) bekommt denselben Schlüssel
local function PersonKey(key)
    local e = ns.Members.byKey[key]
    return e and (e.main or e).key or key
end

-- Einen Charakter dieses Spielers finden, der gerade online ist
function Orders:OnlineChar(key)
    local e = ns.Members.byKey[key]
    if not e then return nil end
    if e.online then return e.name end
    local main = e.main or e
    return main.onlineAs and main.onlineAs.name
end

function Orders:Deliver(targetKey, msgType, payload)
    local name = self:OnlineChar(targetKey)
    if name then
        ns.Comm:Send(msgType, payload, "WHISPER", name)
        return true
    end
    local box = DB().outbox
    box[targetKey] = box[targetKey] or {}
    table.insert(box[targetKey], { msgType, payload })
    return false
end

-- Wartende Nachrichten an alle schicken, die jetzt online sind
function Orders:Flush()
    for key, list in pairs(DB().outbox) do
        local name = self:OnlineChar(key)
        if name then
            DB().outbox[key] = nil
            for _, m in ipairs(list) do
                ns.Comm:Send(m[1], m[2], "WHISPER", name)
                if m[1] == "ORDER" then
                    local o = DB().out[m[2]:match("^([^\t]+)")]
                    if o and o.state == "wartet" then o.state = "zugestellt" end
                end
            end
            ns:Fire("ORDERS_UPDATE")
        end
    end
end

-- Besteller ---------------------------------------------------------------------------
function Orders:Send(crafter, recipeId, note)
    local key = ns.NameKey(crafter)
    if not key then return end
    local id = tostring(math.random(100000, 999999)) .. tostring(time() % 1000)
    local o = {
        id = id, crafter = crafter, crafterKey = key, recipeId = recipeId,
        recipe = ns.Professions:RecipeName(recipeId), note = strtrim(note or ""), time = time(), state = "wartet",
    }
    DB().out[id] = o
    local delivered = self:Deliver(key, "ORDER", table.concat({ id, recipeId, Clean(crafter), Clean(o.note) }, "\t"))
    ns.Print(delivered and ("Auftrag an " .. ns.ShortName(crafter) .. " geschickt: " .. (o.recipe or recipeId))
        or (ns.ShortName(crafter) .. " ist gerade nicht online – der Auftrag geht raus, sobald er oder sie da ist."))
    ns:Fire("ORDERS_UPDATE")
end

function Orders:Cancel(id)
    local o = DB().out[id]
    if not o then return end
    if o.state ~= "fertig" and o.state ~= "abgelehnt" then
        self:Deliver(o.crafterKey, "ORDERST", id .. "\tstorniert")
    end
    DB().out[id] = nil
    ns:Fire("ORDERS_UPDATE")
end

-- Hersteller --------------------------------------------------------------------------
function Orders:SetState(id, state)
    local o = DB().inc[id]
    if not o then return end
    o.state = state
    self:Deliver(o.fromKey, "ORDERST", id .. "\t" .. state)
    ns:Fire("ORDERS_UPDATE")
end

function Orders:Remove(id)
    DB().inc[id] = nil
    ns:Fire("ORDERS_UPDATE")
end

-- Listen für die Oberfläche: offene zuerst, dann neueste
local function Sorted(t)
    local list = {}
    for _, o in pairs(t) do table.insert(list, o) end
    local done = { fertig = true, abgelehnt = true, storniert = true }
    table.sort(list, function(a, b)
        if (done[a.state] or false) ~= (done[b.state] or false) then return not done[a.state] end
        return a.time > b.time
    end)
    return list
end

function Orders:Incoming() return Sorted(DB().inc) end
function Orders:Outgoing() return Sorted(DB().out) end

function Orders:OpenCount()
    local n = 0
    for _, o in pairs(DB().inc) do
        if o.state == "neu" or o.state == "angenommen" then n = n + 1 end
    end
    return n
end

-- Nachrichten -------------------------------------------------------------------------
ns.Comm.handlers.ORDER = function(sender, parts)
    local id, recipeId = parts[2], tonumber(parts[3])
    if not id or not recipeId or not ns.Members:Find(sender) then return end
    if not DB().inc[id] then
        DB().inc[id] = {
            id = id, from = sender, fromKey = ns.NameKey(sender), crafter = parts[4], recipeId = recipeId,
            recipe = ns.Professions:RecipeName(recipeId), note = parts[5] or "", time = time(), state = "neu",
        }
        ns.Sound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master")
        ns.Print(string.format("Neuer Auftrag von %s für %s: %s – /ea berufe", ns.ShortName(sender),
            ns.ShortName(parts[4]) or "dich", DB().inc[id].recipe or ("Rezept " .. recipeId)))
        ns:Fire("ORDERS_UPDATE")
    end
    ns.Comm:Send("ORDERACK", id, "WHISPER", sender)
end

ns.Comm.handlers.ORDERACK = function(_, parts)
    local o = DB().out[parts[2] or ""]
    if o and o.state == "wartet" then
        o.state = "zugestellt"
        ns:Fire("ORDERS_UPDATE")
    end
end

ns.Comm.handlers.ORDERST = function(sender, parts)
    local id, state = parts[2], parts[3]
    if not id or not Orders.STATES[state] then return end
    local out = DB().out[id]
    if out and ns.SameName(PersonKey(ns.NameKey(sender)), PersonKey(out.crafterKey)) then
        out.state = state
        local texts = { angenommen = "hat deinen Auftrag angenommen", fertig = "hat deinen Auftrag fertig",
            abgelehnt = "kann deinen Auftrag leider nicht machen" }
        if texts[state] then ns.Print(ns.ShortName(sender) .. " " .. texts[state] .. ": " .. (out.recipe or "")) end
        ns:Fire("ORDERS_UPDATE")
        return
    end
    local inc = DB().inc[id]
    if inc and state == "storniert" then
        inc.state = state
        ns:Fire("ORDERS_UPDATE")
    end
end

-- Aufräumen und Zustellen --------------------------------------------------------------
local function Prune()
    local limit = time() - KEEP_DAYS * 86400
    for _, t in ipairs({ DB().out, DB().inc }) do
        for id, o in pairs(t) do
            if (o.time or 0) < limit then t[id] = nil end
        end
    end
end

ns:Listen("INIT", Prune)
ns:Listen("MEMBERS_UPDATE", function() Orders:Flush() end)
