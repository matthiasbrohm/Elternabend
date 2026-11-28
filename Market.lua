-- Elternabend: Gildenmarkt – ein Auktionshaus nur für die Gilde (Idee von Philipp Wobakoff)
--
-- Zwei Arten von Angeboten, beide zum Festpreis:
--   * Schaufenster („s“): bleibt dauerhaft stehen, Preis pro Stück (z. B. Tränke). Der Vorrat zählt das Addon
--     beim Verkäufer selbst (Taschen und Bank) und meldet ihn mit.
--   * Einzelangebot („e“): ein Gegenstand bzw. Stapel mit Laufzeit 6, 12, 24 oder 48 Stunden (z. B. Ausrüstung).
--     Der erste Kaufwunsch reserviert ihn.
-- Addons können keine Ware und kein Gold bewegen. Der Kauf läuft deshalb so: Der Käufer klickt „Kaufen“
-- (Kaufwunsch), der Verkäufer schickt die Ware per Brief mit Nachnahme – das Addon füllt den Brief vor –
-- und der Käufer zahlt beim Öffnen. Beim Abschicken markiert das Addon den Kauf als „verschickt“.
--
-- Verteilung wie bei der Pinnwand: Angebote wandern von Addon zu Addon, beim Einloggen gleichen die Addons
-- ihre Listen ab. So sieht man Angebote und Kaufwünsche auch, wenn Verkäufer oder Käufer offline sind.
--   MKTN  <Angebot>                 ein Angebot mit allen Kaufwünschen (GUILD)
--   MKTQ  <Anfrage>#<Liste>          Abgleich beim Einloggen: id:prüfsumme;… (GUILD)
--   MKTA  <Anfrage>                  „Ich antworte schon“
--   MKTW  id;id;…                    „Diese kenne ich nicht, schick sie bitte“ (WHISPER)
--
-- Format: Datensätze mit „~“, Felder mit „^“.
--   O^id^seller^created^updated^expires^kind^item^name^quality^count^price^stock^state^note^tiers^whole
--     price: immer pro Stück. tiers: Mengenrabatt „ab:Preis,ab:Preis“ (z. B. „10:4500,20:4000“).
--     whole: „1“ = Einzelangebot nur komplett; sonst darf man auch einen Teil kaufen.
--     count: Einzelangebot – noch zu haben (sinkt mit jedem verschickten Kauf).
--     price 0: Geschenk (nur Einzelangebot, Haken „verschenken“) – Brief ohne Nachnahme.
--   K^buyer^menge^zeit^stand        Kaufwunsch (stand: neu / zurueck / versandt / abgelehnt)
local _, ns = ...

local Market = { recent = {}, answered = {}, notified = {} }
ns.Market = Market

Market.HOURS = { 6, 12, 24, 48 }
local SHOP_DAYS = 30          -- Schaufenster: läuft ab, wenn der Verkäufer so lange nicht online war
local GONE_DAYS = 3           -- Verkauftes und Zurückgezogenes bleibt so lange als „Grabstein“, damit es alle mitbekommen
local MAX_OPEN = 40           -- offene Angebote pro Spieler
local MAX_OFFERS = 600        -- mehr speichert das Addon nicht
local MAX_PRICE = 99999 * 10000
local NOTE_MAX = 80

Market.STATES = {
    neu = { "Kaufwunsch", "goldBright" },
    zurueck = { "Zurückgezogen", "dim" },
    versandt = { "Verschickt", "green" },
    abgelehnt = { "Abgelehnt", "red" },
}

local function DB() return ns.db.market end
local function Now() return GetServerTime and GetServerTime() or time() end
Market.Now = Now

local function Clean(s, max)
    s = tostring(s or ""):gsub("[\t\r\n|^~#;]", " ")
    s = strtrim(s)
    if max and #s > max then s = s:sub(1, max) end
    return s
end

local function Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%x", h)
end

local function Split(s, sep)
    local out, pos = {}, 1
    while true do
        local i = s:find(sep, pos, true)
        if not i then
            table.insert(out, s:sub(pos))
            return out
        end
        table.insert(out, s:sub(pos, i - 1))
        pos = i + 1
    end
end

-- Geld ------------------------------------------------------------------------------------
-- 12345 → „1g 23s 45k“ (ohne Nullen)
function Market.Money(copper)
    copper = math.floor(tonumber(copper) or 0)
    local g, s, k = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. "g") end
    if s > 0 then table.insert(parts, s .. "s") end
    if k > 0 or #parts == 0 then table.insert(parts, k .. "k") end
    return table.concat(parts, " ")
end

-- Restzeit als kurzer Text
function Market.Left(seconds)
    seconds = math.max(0, seconds or 0)
    if seconds >= 86400 then
        local d = math.floor(seconds / 86400)
        return d == 1 and "1 Tag" or (d .. " Tage")
    end
    if seconds >= 3600 then return math.floor(seconds / 3600) .. " Std." end
    return math.max(1, math.floor(seconds / 60)) .. " Min."
end

-- Mengenrabatt: „10:4500,20:4000“ ↔ { { min = 10, price = 4500 }, … } (aufsteigend, höchstens 3 Staffeln)
function Market.ParseTiers(s)
    local list = {}
    for min, price in tostring(s or ""):gmatch("(%d+):(%d+)") do
        min, price = tonumber(min), tonumber(price)
        if min >= 2 and price > 0 and price <= MAX_PRICE and #list < 3 then table.insert(list, { min = min, price = price }) end
    end
    table.sort(list, function(a, b) return a.min < b.min end)
    return list
end

function Market.TiersString(list)
    local parts = {}
    for _, t in ipairs(list or {}) do table.insert(parts, t.min .. ":" .. t.price) end
    return table.concat(parts, ",")
end

-- Stückpreis bei dieser Menge (größte erreichte Staffel)
function Market:UnitPrice(o, qty)
    local price = o.price
    for _, t in ipairs(Market.ParseTiers(o.tiers)) do
        if (qty or 1) >= t.min then price = t.price end
    end
    return price
end

function Market:Total(o, qty)
    qty = qty or 1
    return self:UnitPrice(o, qty) * qty
end

-- Gegenstände -------------------------------------------------------------------------------
-- Aus einem Link den Gegenstandstext („item:…“), aus dem sich der Link überall neu bauen lässt
function Market.ItemString(link)
    if type(link) ~= "string" then return nil end
    return link:match("|H(item:[^|]+)|h") or (link:match("^item:[%d:%-]+$") and link) or nil
end

function Market.ItemID(itemString)
    return tonumber(tostring(itemString or ""):match("^item:(%d+)"))
end

local QUALITY_COLORS = { [0] = "ff9d9d9d", "ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000", "ffe6cc80" }
-- Link zum Anzeigen (Tooltip, Chat). Ohne Daten im Spiel ein selbst gebauter Link mit dem gemerkten Namen.
function Market:Link(o)
    local ok, _, link = pcall(ns.GetItemInfo, o.item)
    if ok and type(link) == "string" then return link end
    local color = QUALITY_COLORS[tonumber(o.quality) or 1] or QUALITY_COLORS[1]
    return "|c" .. color .. "|H" .. o.item .. "|h[" .. (o.name or "?") .. "]|h|r"
end

function Market:Icon(o)
    local id = Market.ItemID(o.item)
    local ok, icon = pcall(ns.GetItemIcon, id)
    return ok and icon or 134400 -- Fragezeichen
end

-- Wie viel davon habe ich (Taschen und Bank)?
local function CountItem(itemString)
    local id = Market.ItemID(itemString)
    if not id then return 0 end
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not f then return 0 end
    local ok, n = pcall(f, id, true)
    return ok and tonumber(n) or 0
end
Market.CountItem = CountItem

-- Serialisieren -------------------------------------------------------------------------------
local BODY = { "id", "seller", "created", "updated", "expires", "kind", "item", "name", "quality", "count", "price", "stock", "state", "note", "tiers", "whole" }
local NUM = { created = true, updated = true, expires = true, quality = true, count = true, price = true, stock = true }

local function BodyString(o)
    local f = {}
    for i, k in ipairs(BODY) do f[i] = tostring(o[k] or "") end
    return "O^" .. table.concat(f, "^")
end

function Market:Serialize(o)
    local parts = { BodyString(o) }
    local keys = {}
    for k in pairs(o.reqs or {}) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local r = o.reqs[k]
        table.insert(parts, table.concat({ "K", r.buyer, r.qty, r.t, r.st }, "^"))
    end
    return table.concat(parts, "~")
end

function Market:Digest(o) return Hash(self:Serialize(o)) end

function Market:Parse(data)
    local records = Split(data or "", "~")
    local f = Split(records[1] or "", "^")
    if f[1] ~= "O" or #f < #BODY + 1 then return nil end
    local o = { reqs = {} }
    for i, k in ipairs(BODY) do
        o[k] = f[i + 1]
        if NUM[k] then o[k] = tonumber(o[k]) end
    end
    if not o.id or o.id == "" or not o.seller or o.seller == "" or not o.created or not o.updated or not o.expires then return nil end
    if o.kind ~= "s" and o.kind ~= "e" then return nil end
    if not Market.ItemID(o.item) then return nil end
    if o.state ~= "offen" and o.state ~= "verkauft" and o.state ~= "entfernt" then o.state = "offen" end
    o.count = math.max(1, math.floor(o.count or 1))
    o.price = math.max(0, math.min(MAX_PRICE, math.floor(o.price or 0)))
    o.stock = math.max(0, math.floor(o.stock or 0))
    o.name, o.note = Clean(o.name, 120), Clean(o.note, NOTE_MAX)
    o.tiers = Market.TiersString(Market.ParseTiers(o.tiers))
    o.whole = o.whole == "1" and "1" or ""
    for i = 2, #records do
        local r = Split(records[i], "^")
        if r[1] == "K" and r[2] and r[2] ~= "" and Market.STATES[r[5] or ""] then
            local key = ns.NameKey(r[2])
            if key then o.reqs[key] = { buyer = r[2], qty = math.max(1, tonumber(r[3]) or 1), t = tonumber(r[4]) or 0, st = r[5] } end
        end
    end
    return o
end

-- Wer bin ich ---------------------------------------------------------------------------------
function Market:Open()
    return IsInGuild() and ns.Info:AtHome()
end

function Market:IsMine(name)
    return ns.Board:IsMePerson(name)
end

-- Kaufwünsche: Reihenfolge nach Zeit; offen = neu oder verschickt
local STATE_RANK = { neu = 1, zurueck = 2, abgelehnt = 3, versandt = 4 }
function Market:Requests(o)
    local list = {}
    for key, r in pairs(o.reqs or {}) do table.insert(list, { key = key, buyer = r.buyer, qty = r.qty, t = r.t, st = r.st }) end
    table.sort(list, function(a, b) if a.t ~= b.t then return a.t < b.t end return a.key < b.key end)
    return list
end

-- Einzelangebot: wer hat es reserviert (erster offener Kaufwunsch)?
function Market:ReservedBy(o)
    if o.kind ~= "e" or o.state ~= "offen" or self:Available(o) > 0 then return nil end
    for _, r in ipairs(self:Requests(o)) do
        if r.st == "neu" then return r end
    end
end

function Market:MyRequest(o)
    for _, r in ipairs(self:Requests(o)) do
        if self:IsMine(r.buyer) and r.st ~= "zurueck" then return r end
    end
end

-- Noch zu haben? Schaufenster: Vorrat abzüglich offener Kaufwünsche
function Market:Available(o)
    if o.state ~= "offen" or o.expires <= Now() then return 0 end
    local wanted = 0
    for _, r in pairs(o.reqs) do
        if r.st == "neu" then wanted = wanted + r.qty end
    end
    if o.kind == "e" then
        if o.whole == "1" then return wanted > 0 and 0 or o.count end
        return math.max(0, o.count - wanted)
    end
    return math.max(0, o.stock - wanted)
end

function Market:HasOpenRequest(o)
    for _, r in pairs(o.reqs) do
        if r.st == "neu" then return true end
    end
    return false
end

function Market:IsGift(o) return (o.price or 0) == 0 end

-- Einzelangebot: Darf man auch einen Teil kaufen?
function Market:Partial(o)
    return o.kind == "s" or (o.count > 1 and o.whole ~= "1")
end

local function CountOpen(seller)
    local n = 0
    for _, o in pairs(DB().offers) do
        if o.state == "offen" and o.expires > Now() and Market:IsSamePerson(o.seller, seller) then n = n + 1 end
    end
    return n
end

function Market:IsSamePerson(a, b)
    return ns.Board:SamePerson(a, b)
end

-- Zusammenführen --------------------------------------------------------------------------------
-- Liefert „neu“, „geändert“ oder nil
function Market:Merge(incoming, fromNetwork)
    local now = Now()
    if incoming.created > now + 86400 then return nil end
    if incoming.kind == "e" and incoming.expires > incoming.created + 49 * 3600 + 86400 * GONE_DAYS then return nil end
    if incoming.expires > now + (SHOP_DAYS + 1) * 86400 then return nil end
    if incoming.expires <= now then return nil end
    local offers = DB().offers
    local mine = offers[incoming.id]
    if not mine then
        if fromNetwork then
            local total = 0
            for _ in pairs(offers) do total = total + 1 end
            if total >= MAX_OFFERS then return nil end
            if incoming.state == "offen" and CountOpen(incoming.seller) >= MAX_OPEN + 5 then return nil end
        end
        offers[incoming.id] = incoming
        return "neu"
    end
    if mine.seller ~= incoming.seller or mine.created ~= incoming.created or mine.item ~= incoming.item then return nil end
    local before = self:Digest(mine)
    local newer = incoming.updated > mine.updated
        or (incoming.updated == mine.updated and BodyString(incoming) > BodyString(mine))
    -- Verkauft/zurückgezogen bleibt so (eine ältere Fassung macht es nicht wieder „offen“)
    if newer and not (mine.state ~= "offen" and incoming.state == "offen") then
        for _, k in ipairs(BODY) do mine[k] = incoming[k] end
    end
    for key, r in pairs(incoming.reqs or {}) do
        local m = mine.reqs[key]
        if not m or r.t > m.t or (r.t == m.t and (STATE_RANK[r.st] or 0) > (STATE_RANK[m.st] or 0)) then
            mine.reqs[key] = r
        end
    end
    if self:Digest(mine) ~= before then return "geändert", mine end
end

-- Senden -----------------------------------------------------------------------------------------
-- urgent: Klick von Käufer oder Verkäufer (Kaufwunsch, Antwort) – geht vor allen Abgleichspaketen raus
function Market:Broadcast(o, urgent)
    if not self:Open() then return end
    local data = self:Serialize(o)
    self.recent[o.id] = { digest = Hash(data), at = GetTime() }
    ns.WhenChatFree(function() ns.Comm:SendLarge("MKTN", data, "GUILD", nil, urgent) end)
end

local function Touch(o)
    o.updated = math.max(Now(), (o.updated or 0) + 1)
end

local function NewId()
    return string.format("%x%04x", Now(), math.random(0, 65535))
end

-- Angebot einstellen. opts: link, kind ("s"/"e"), count, price (Kupfer pro Stück), hours, note,
-- tiers ({ { min, price }, … } Mengenrabatt), whole (Einzelangebot nur komplett), gift (Einzelangebot verschenken)
function Market:Post(opts)
    if not self:Open() then return false, "Den Gildenmarkt gibt es nur für Charaktere in der Gilde." end
    local item = Market.ItemString(opts.link)
    if not item then return false, "Bitte zuerst einen Gegenstand in das Feld ziehen." end
    local kind = opts.kind == "s" and "s" or "e"
    local gift = kind == "e" and opts.gift and true or false
    local price = gift and 0 or math.floor(tonumber(opts.price) or 0)
    if price <= 0 and not gift then return false, "Bitte einen Preis eingeben." end
    if price > MAX_PRICE then return false, "Der Preis ist zu hoch." end
    local me = ns.UnitFullName("player")
    if CountOpen(me) >= MAX_OPEN then return false, "Du hast schon " .. MAX_OPEN .. " Angebote. Nimm erst eines heraus." end
    local have = CountItem(item)
    local count = math.max(1, math.floor(tonumber(opts.count) or 1))
    if kind == "e" and have > 0 and count > have then
        return false, "So viele hast du nicht (Taschen und Bank: " .. have .. ")."
    end
    if kind == "s" then
        for _, o in pairs(DB().offers) do
            if o.kind == "s" and o.state == "offen" and ns.SameName(o.seller, me) and Market.ItemID(o.item) == Market.ItemID(item) then
                return false, "Das steht schon in deinem Schaufenster. Ändere dort den Preis."
            end
        end
    end
    local now = Now()
    local hours = tonumber(opts.hours) or 24
    local valid = false
    for _, h in ipairs(self.HOURS) do if h == hours then valid = true end end
    if not valid then hours = 24 end
    local name, quality = opts.link:match("|h%[(.-)%]|h"), nil
    local okInfo, infoName, _, infoQuality = pcall(ns.GetItemInfo, opts.link)
    if okInfo then name, quality = infoName or name, infoQuality end
    if not quality then
        local hex = ns.Lower(opts.link:match("|c(%x%x%x%x%x%x%x%x)") or "")
        for q, color in pairs(QUALITY_COLORS) do if color == hex then quality = q end end
    end
    local o = {
        id = NewId(), seller = me, created = now, updated = now,
        expires = kind == "s" and (now + SHOP_DAYS * 86400) or (now + hours * 3600),
        kind = kind, item = item, name = Clean(name or "?", 120), quality = quality or 1,
        count = kind == "s" and 1 or count, price = price, stock = kind == "s" and have or count,
        state = "offen", note = Clean(opts.note, NOTE_MAX), reqs = {},
        whole = (kind == "e" and opts.whole and count > 1) and "1" or "",
    }
    local tiers = {}
    if not gift and (kind == "s" or (count > 1 and not opts.whole)) then
        for _, t in ipairs(opts.tiers or {}) do
            local min, tp = math.floor(tonumber(t.min) or 0), math.floor(tonumber(t.price) or 0)
            if min >= 2 and tp > 0 then
                if tp >= price then return false, "Der Mengenrabatt ab " .. min .. " Stück muss günstiger sein als der Grundpreis." end
                table.insert(tiers, { min = min, price = tp })
            end
        end
    end
    o.tiers = Market.TiersString(Market.ParseTiers(Market.TiersString(tiers)))
    DB().offers[o.id] = o
    DB().seen[o.id] = true
    self:Broadcast(o, true)
    ns:Fire("MARKET_UPDATE")
    return true, o
end

function Market:CanManage(o)
    return self:IsMine(o.seller)
end

local function SetRequest(o, buyer, qty, st)
    local key = ns.NameKey(buyer)
    local old = o.reqs[key]
    o.reqs[key] = { buyer = buyer, qty = qty or (old and old.qty) or 1, t = math.max(Now(), old and (old.t + 1) or 0), st = st }
end

-- Zurückziehen (Verkäufer)
function Market:Remove(id)
    local o = DB().offers[id]
    if not o or not self:CanManage(o) or o.state ~= "offen" then return end
    o.state = "entfernt"
    -- Offene Kaufwünsche dazu: als abgelehnt markieren, damit die Käufer Bescheid bekommen
    for _, r in pairs(o.reqs) do
        if r.st == "neu" then SetRequest(o, r.buyer, r.qty, "abgelehnt") end
    end
    o.expires = math.min(o.expires, Now() + GONE_DAYS * 86400)
    Touch(o)
    self:Broadcast(o, true)
    ns:Fire("MARKET_UPDATE")
end

-- Preis im Schaufenster ändern
function Market:SetPrice(id, price)
    local o = DB().offers[id]
    price = math.floor(tonumber(price) or 0)
    if not o or not self:CanManage(o) or o.state ~= "offen" or price <= 0 or price > MAX_PRICE then return false end
    o.price = price
    Touch(o)
    self:Broadcast(o, true)
    ns:Fire("MARKET_UPDATE")
    return true
end


-- Kaufen (Käufer): Kaufwunsch an den Verkäufer
function Market:Buy(id, qty)
    local o = DB().offers[id]
    if not o then return false, "Das Angebot gibt es nicht mehr." end
    if self:IsMine(o.seller) then return false, "Das ist dein eigenes Angebot." end
    if o.state ~= "offen" or o.expires <= Now() then return false, "Das Angebot ist nicht mehr da." end
    local mineReq = self:MyRequest(o)
    if mineReq and mineReq.st == "neu" then return false, "Du hast schon einen Kaufwunsch abgeschickt." end
    local available = self:Available(o)
    qty = self:Partial(o) and math.max(1, math.floor(tonumber(qty) or 1)) or o.count
    if available == 0 then
        return false, o.kind == "e" and "Das ist schon reserviert." or "Gerade nichts mehr vorrätig."
    end
    if qty > available then return false, "Es sind nur noch " .. available .. " da." end
    SetRequest(o, ns.UnitFullName("player"), qty, "neu")
    self:Broadcast(o, true)
    ns:Fire("MARKET_UPDATE")
    return true
end

-- Kaufwunsch zurückziehen (Käufer)
function Market:Cancel(id)
    local o = DB().offers[id]
    local r = o and self:MyRequest(o)
    if not r or r.st ~= "neu" then return end
    SetRequest(o, r.buyer, r.qty, "zurueck")
    self:Broadcast(o, true)
    ns:Fire("MARKET_UPDATE")
end

-- Verkäufer: Kaufwunsch ablehnen oder als verschickt/erledigt markieren
function Market:Answer(id, buyerKey, st)
    local o = DB().offers[id]
    if not o or not self:CanManage(o) then return end
    local r = o.reqs[buyerKey]
    if not r or r.st ~= "neu" or (st ~= "versandt" and st ~= "abgelehnt") then return end
    SetRequest(o, r.buyer, r.qty, st)
    if st == "versandt" then
        if o.kind == "e" then
            o.count = math.max(0, o.count - r.qty)
            if o.count == 0 then
                o.count = r.qty -- für die Anzeige „verkauft“
                o.state = "verkauft"
                o.expires = math.min(o.expires, Now() + GONE_DAYS * 86400)
            end
        else
            o.stock = math.max(0, o.stock - r.qty)
        end
        Touch(o)
    end
    self:Broadcast(o, true)
    ns:Fire("MARKET_UPDATE")
end

-- Liste ---------------------------------------------------------------------------------------------
-- filter: { kind = "s"/"e"/nil, mine = true, search = "text" }
function Market:List(filter)
    filter = filter or {}
    local now = Now()
    local search = filter.search and ns.Lower(strtrim(filter.search)) or ""
    local list = {}
    for _, o in pairs(DB().offers) do
        local mine = self:IsMine(o.seller)
        local show = o.expires > now
        if show and filter.mine then
            show = mine or self:MyRequest(o) ~= nil
        elseif show then
            show = o.state == "offen"
        end
        if show and filter.kind and o.kind ~= filter.kind then show = false end
        if show and search ~= "" and not ns.Lower(o.name or ""):find(search, 1, true)
            and not ns.Lower(ns.ShortName(o.seller)):find(search, 1, true) then show = false end
        if show then table.insert(list, o) end
    end
    local function Waiting(o)
        if o.state ~= "offen" or not self:IsMine(o.seller) then return false end
        for _, r in pairs(o.reqs) do if r.st == "neu" then return true end end
        return false
    end
    table.sort(list, function(a, b)
        local wa, wb = Waiting(a), Waiting(b)
        if wa ~= wb then return wa end -- eigene Angebote mit offenen Kaufwünschen ganz oben
        if a.kind ~= b.kind then return a.kind == "e" end -- Einzelangebote zuerst, sie laufen ab
        if a.kind == "e" and a.expires ~= b.expires then return a.expires < b.expires end
        if a.name ~= b.name then return (a.name or "") < (b.name or "") end
        return a.id < b.id
    end)
    return list
end

-- Offene Kaufwünsche an meine Angebote (für die Plakette)
function Market:OpenRequestCount()
    local n = 0
    for _, o in pairs(DB().offers) do
        -- nur Angebote, die noch im Markt stehen (herausgenommene oder verkaufte zählen nicht mehr)
        if o.state == "offen" and o.expires > Now() and self:IsMine(o.seller) then
            for _, r in pairs(o.reqs) do
                if r.st == "neu" and not self:IsMine(r.buyer) then n = n + 1 end -- eigene Twinks zählen nicht
            end
        end
    end
    return n
end

-- Hinweise ------------------------------------------------------------------------------------------
-- Nach jedem Empfang: neue Kaufwünsche an mich und Antworten auf meine Kaufwünsche melden (je einmal)
function Market:CheckNews(o)
    local mineOffer = self:IsMine(o.seller)
    for key, r in pairs(o.reqs) do
        local tag = o.id .. ":" .. key .. ":" .. r.st .. ":" .. r.t
        if not self.notified[tag] then
            self.notified[tag] = true
            local link = self:Link(o)
            if mineOffer and r.st == "neu" and not self:IsMine(r.buyer) then
                ns.Sound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master", true)
                if self:IsGift(o) then
                    ns.Print(string.format("|cfff3dc9aGildenmarkt:|r %s hätte gern %s%s, das du verschenkst – /ea markt",
                        ns.ShortName(r.buyer), r.qty > 1 and (r.qty .. "x ") or "", link))
                else
                    ns.Print(string.format("|cfff3dc9aGildenmarkt:|r %s möchte %s%s für %s kaufen – /ea markt",
                        ns.ShortName(r.buyer), r.qty > 1 and (r.qty .. "x ") or "", link,
                        Market.Money(self:Total(o, r.qty))))
                end
            elseif not mineOffer and self:IsMine(r.buyer) and r.st == "versandt" then
                ns.Print(string.format("|cfff3dc9aGildenmarkt:|r %s hat dir %s %s – schau in deinen Briefkasten.",
                    ns.ShortName(o.seller), link, self:IsGift(o) and "geschenkt und geschickt" or "per Nachnahme geschickt"))
            elseif not mineOffer and self:IsMine(r.buyer) and r.st == "abgelehnt" then
                ns.Print(string.format("|cfff3dc9aGildenmarkt:|r %s kann dir %s leider nicht verkaufen.", ns.ShortName(o.seller), link))
            end
        end
    end
end

-- Empfang und Abgleich ----------------------------------------------------------------------------------
function Market:Receive(data)
    if not self:Open() then return end
    local o = self:Parse(data)
    if not o then return end
    local result = self:Merge(o, true)
    self.recent[o.id] = { digest = Hash(data), at = GetTime() }
    if result then
        local cur = DB().offers[o.id]
        if not self.quiet then self:CheckNews(cur) end
        ns:Fire("MARKET_UPDATE")
    end
end

function Market:Inventory()
    local parts, now = {}, Now()
    for id, o in pairs(DB().offers) do
        if o.expires > now then table.insert(parts, id .. ":" .. self:Digest(o)) end
    end
    return table.concat(parts, ";")
end

function Market:RequestSync()
    if not self:Open() then return end
    local req = string.format("%x", math.random(0, 16777215))
    ns.WhenChatFree(function() ns.Comm:SendLarge("MKTQ", req .. "#" .. Market:Inventory(), "GUILD") end)
end

function Market:AnswerRequest(sender, data)
    if not self:Open() then return end
    local req, inv = data:match("^([^#]*)#(.*)$")
    if not req then return end
    local theirs = {}
    for id, digest in inv:gmatch("([^:;]+):([^;]+)") do theirs[id] = digest end
    local now = Now()
    local send, want = {}, {}
    for id, o in pairs(DB().offers) do
        if o.expires > now and theirs[id] ~= self:Digest(o) then table.insert(send, id) end
    end
    for id, digest in pairs(theirs) do
        local o = DB().offers[id]
        if not o or self:Digest(o) ~= digest then table.insert(want, id) end
    end
    if #send == 0 and #want == 0 then return end
    local asked = GetTime()
    C_Timer.After(1.5 + math.random() * 6, function()
        if Market.answered[req] then return end
        Market.answered[req] = true
        ns.Comm:Send("MKTA", req, "GUILD")
        for _, id in ipairs(send) do
            local o = DB().offers[id]
            local r = Market.recent[id]
            if o and not (r and r.at > asked and r.digest == Market:Digest(o)) then Market:Broadcast(o) end
        end
        if #want > 0 then
            ns.WhenChatFree(function() ns.Comm:SendLarge("MKTW", table.concat(want, ";"), "WHISPER", sender) end)
        end
    end)
end

function Market:SendWanted(list)
    if not self:Open() then return end
    for id in (list or ""):gmatch("[^;]+") do
        local o = DB().offers[id]
        if o and o.expires > Now() then
            local r = self.recent[id]
            if not (r and GetTime() - r.at < 30 and r.digest == self:Digest(o)) then self:Broadcast(o) end
        end
    end
end

ns.Comm.handlers.MKTN = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if data then Market:Receive(data) end
end
ns.Comm.handlers.MKTQ = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if data and ns.Members:Find(sender) then Market:AnswerRequest(sender, data) end
end
ns.Comm.handlers.MKTA = function(_, parts)
    if parts[2] then Market.answered[parts[2]] = true end
end
ns.Comm.handlers.MKTW = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if data then Market:SendWanted(data) end
end

-- Vorrat (Verkäufer) -----------------------------------------------------------------------------------
-- Schaufenster: Vorrat neu zählen und bei Änderung melden; dabei die Laufzeit verlängern (Verkäufer ist online).
-- Einzelangebot: Ist der Gegenstand weg (nach einem Bankbesuch sicher gezählt), Angebot herausnehmen.
function Market:CheckStock()
    if not self:Open() then return end
    local me = ns.UnitFullName("player")
    local now = Now()
    for _, o in pairs(DB().offers) do
        if o.state == "offen" and o.expires > now and ns.SameName(o.seller, me) then
            local have = CountItem(o.item)
            local changed = false
            if o.kind == "s" then
                if have ~= o.stock then o.stock, changed = have, true end
                if o.expires - now < (SHOP_DAYS - 5) * 86400 then o.expires, changed = now + SHOP_DAYS * 86400, true end
            elseif self.bankSeen and have == 0 and not self:HasOpenRequest(o) then
                o.state = "entfernt"
                changed = true
            end
            if changed then
                Touch(o)
                self:Broadcast(o)
            end
        end
    end
    ns:Fire("MARKET_UPDATE")
end

-- Brief mit Nachnahme ---------------------------------------------------------------------------------------
-- Füllt den offenen Briefkasten aus: Empfänger, Betreff, Nachnahme – und legt die Ware an, wenn das Spiel es zulässt.
function Market:PrepareMail(id, buyerKey)
    local o = DB().offers[id]
    local r = o and o.reqs[buyerKey]
    if not r or r.st ~= "neu" then return false, "Diesen Kaufwunsch gibt es nicht mehr." end
    if not ns.SameName(o.seller, ns.UnitFullName("player")) then
        return false, "Die Ware liegt bei " .. ns.ShortName(o.seller) .. " – bitte dorthin umloggen."
    end
    if not self.mailOpen then return false, "Öffne zuerst einen Briefkasten." end
    local qty = r.qty
    local total = self:Total(o, qty)
    if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, nil, 2) end
    if SendMailNameEditBox then SendMailNameEditBox:SetText(r.buyer) end
    if SendMailSubjectEditBox then
        SendMailSubjectEditBox:SetText((total > 0 and "Gildenmarkt: " or "Geschenk aus dem Gildenmarkt: ")
            .. (qty > 1 and (qty .. "x ") or "") .. (o.name or ""))
    end
    if total > 0 then
        if SendMailRadioButton_OnClick then pcall(SendMailRadioButton_OnClick, 2) end -- 2 = Nachnahme
        if MoneyInputFrame_SetCopper and SendMailMoney then pcall(MoneyInputFrame_SetCopper, SendMailMoney, total) end
    else
        -- Geschenk: ohne Nachnahme, kein Geld
        if SendMailRadioButton_OnClick then pcall(SendMailRadioButton_OnClick, 1) end
        if MoneyInputFrame_SetCopper and SendMailMoney then pcall(MoneyInputFrame_SetCopper, SendMailMoney, 0) end
    end
    local attached, why = self:AttachItem(o, qty)
    self.pendingMail = { id = id, key = buyerKey, buyer = r.buyer, at = GetTime() }
    return true, attached, why
end

-- Ware aus den Taschen anlegen – auch über mehrere Stapel, der letzte wird geteilt.
-- Liefert true, wenn alles im Brief liegt; sonst false und "bank" (nicht genug in den Taschen) oder "fehler".
function Market:AttachItem(o, qty)
    local C = C_Container
    if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo and ClickSendMailItemButton) then return false, "fehler" end
    local wantID = Market.ItemID(o.item)
    local slots, have = {}, 0
    for bag = 0, 4 do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local info = C.GetContainerItemInfo(bag, slot)
            if info and info.itemID == wantID and not info.isLocked
                and (o.kind == "s" or o.count > 1 or Market.ItemString(info.hyperlink) == o.item) then
                table.insert(slots, { bag = bag, slot = slot, n = info.stackCount or 1 })
                have = have + (info.stackCount or 1)
            end
        end
    end
    if have < qty then return false, "bank" end
    table.sort(slots, function(a, b) return a.n > b.n end)
    local maxSlots = tonumber(ATTACHMENTS_MAX_SEND) or 12
    local function FreeSlot()
        for i = 1, maxSlots do
            if not (GetSendMailItem and GetSendMailItem(i)) then return i end
        end
    end
    local rest = qty
    for _, s in ipairs(slots) do
        if rest <= 0 then break end
        local index = FreeSlot()
        if not index then return false, "fehler" end
        local ok
        if s.n > rest and C.SplitContainerItem then
            ok = pcall(C.SplitContainerItem, s.bag, s.slot, rest)
            rest = 0
        else
            ok = pcall(C.PickupContainerItem, s.bag, s.slot)
            rest = rest - s.n
        end
        if ok then ok = pcall(ClickSendMailItemButton, index) end
        if CursorHasItem and CursorHasItem() then
            ClearCursor()
            return false, "fehler"
        end
        if not ok then return false, "fehler" end
    end
    return rest <= 0, rest > 0 and "fehler" or nil
end

-- Events ------------------------------------------------------------------------------------------------
local stockTimer
local function StockSoon()
    if stockTimer then return end
    stockTimer = true
    C_Timer.After(3, function()
        stockTimer = nil
        Market:CheckStock()
    end)
end

ns:On("BAG_UPDATE_DELAYED", StockSoon)
pcall(ns.On, ns, "BANKFRAME_OPENED", function() Market.bankSeen = true end)
pcall(ns.On, ns, "BANKFRAME_CLOSED", StockSoon)
pcall(ns.On, ns, "MAIL_SHOW", function() Market.mailOpen = true ns:Fire("MARKET_UPDATE") end)
pcall(ns.On, ns, "MAIL_CLOSED", function() Market.mailOpen = false ns:Fire("MARKET_UPDATE") end)
-- Neuere Clients melden den Briefkasten auch (oder nur) über den Interaktions-Manager
local function IsMailbox(kind)
    local t = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.MailInfo or 17
    return kind == t
end
pcall(ns.On, ns, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
    if IsMailbox(kind) and not Market.mailOpen then
        Market.mailOpen = true
        ns:Fire("MARKET_UPDATE")
        ns:Fire("MAILBOX_OPENED")
    end
end)
pcall(ns.On, ns, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind)
    if IsMailbox(kind) and Market.mailOpen then
        Market.mailOpen = false
        ns:Fire("MARKET_UPDATE")
        ns:Fire("MAILBOX_CLOSED")
    end
end)
if hooksecurefunc and SendMail then
    hooksecurefunc("SendMail", function(recipient) Market.sendingTo = recipient end)
end
pcall(ns.On, ns, "MAIL_SEND_SUCCESS", function()
    local p = Market.pendingMail
    if p and Market.sendingTo and ns.SameName(Market.sendingTo, p.buyer) and GetTime() - p.at < 900 then
        Market.pendingMail = nil
        Market:Answer(p.id, p.key, "versandt")
        ns.Print("|cfff3dc9aGildenmarkt:|r Brief an " .. ns.ShortName(p.buyer) .. " ist unterwegs – als verschickt markiert.")
    end
    Market.sendingTo = nil
end)

function Market:Prune()
    local now = Now()
    for id, o in pairs(DB().offers) do
        if (o.expires or 0) <= now then
            DB().offers[id] = nil
            DB().seen[id] = nil
        end
    end
end

ns:Listen("INIT", function()
    Market:Prune()
    C_Timer.NewTicker(600, function()
        Market:Prune()
        ns:Fire("MARKET_UPDATE")
    end)
end)

ns:On("PLAYER_LOGIN", function()
    -- Beim Abgleich nach dem Einloggen trotzdem melden, was in der Zwischenzeit kam (z. B. Kaufwünsche)
    C_Timer.After(30 + math.random() * 15, function() Market:RequestSync() end)
    C_Timer.After(20, function() Market:CheckStock() end)
    -- Erinnerung an offene Kaufwünsche (auch an die, die schon vor dem Einloggen da waren)
    C_Timer.After(80, function()
        local n = Market:OpenRequestCount()
        if n > 0 then
            ns.Print("|cfff3dc9aGildenmarkt:|r " .. (n == 1 and "1 offener Kaufwunsch" or (n .. " offene Kaufwünsche"))
                .. " an deine Angebote – /ea markt")
        end
    end)
end)
