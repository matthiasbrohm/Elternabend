-- Elternabend: Gildenbank – Bestand für alle sichtbar, Anfragen an die Leitung, Versand per Brief
--
-- Bestand: Wer die Gildenbank öffnet, dessen Addon liest die Fächer, die er sehen darf, und verteilt sie –
-- je Fach mit Zeitstempel; das neuere Fach gewinnt. Auslesen geht nur bei offener Bank.
-- Anfragen: Mitglieder (Rang „Mitglied“ und höher; Twinks zählen mit dem Rang ihres Mains) fragen Gegenstand
-- und Menge an. Offiziere und Gildenleitung geben frei oder lehnen ab. Freigegebenes holt ein Offizier an der
-- Bank in seine Taschen („Aus der Bank holen“) und verschickt es am Briefkasten („Brief vorbereiten“, ohne Nachnahme).
-- Verteilung wie Gildenmarkt und Pinnwand: Datensätze wandern von Addon zu Addon, beim Einloggen gleichen die
-- Addons ab – Anfragen erreichen die Leitung auch, wenn gerade niemand online ist.
--   BNKN  <Datensatz>            ein Fach oder eine Anfrage (GUILD)
--   BNKQ  <Anfrage>#<Liste>      Abgleich: id:prüfsumme;… (GUILD)
--   BNKA  <Anfrage>              „Ich antworte schon“
--   BNKW  id;id;…                „Diese kenne ich nicht, schick sie bitte“ (WHISPER)
-- Datensätze (Felder mit „^“, Einträge mit „~“):
--   T^id^fach^name^zeit^von~I^item^name^qualität^anzahl~…          id = „t<fach>“
--   R^id^wer^erstellt^geändert^item^name^qualität^menge^grund^stand^von
--     stand: neu / frei / abgelehnt / versandt / zurueck; von = wer zuletzt entschieden hat
local _, ns = ...

local Bank = { recent = {}, answered = {}, notified = {}, live = {} }
ns.GuildBank = Bank

local KEEP_OPEN_DAYS = 30      -- offene Anfragen
local KEEP_DONE_DAYS = 14      -- erledigte bleiben so lange sichtbar
local MAX_OPEN = 10            -- offene Anfragen pro Person
local MAX_RECORDS = 400
local NOTE_MAX = 80
local SLOTS = 98               -- Plätze pro Fach

Bank.STATES = {
    neu = { "Angefragt", "goldBright" },
    frei = { "Freigegeben", "green" },
    abgelehnt = { "Abgelehnt", "red" },
    versandt = { "Verschickt", "green" },
    zurueck = { "Zurückgezogen", "dim" },
}
local OPEN_STATES = { neu = true, frei = true }
local RANK = { neu = 1, zurueck = 2, abgelehnt = 3, frei = 4, versandt = 5 }

local function DB() return ns.db.guildbank end
local function Now() return GetServerTime and GetServerTime() or time() end
Bank.Now = Now

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

-- Gegenstandstext ohne Einzelstück-Kennung (damit gleiche Sachen zusammengezählt werden)
local function ItemKey(link)
    local s = ns.Market.ItemString(link)
    if not s then return nil end
    local f = Split(s, ":")
    f[9] = "" -- uniqueID
    return table.concat(f, ":")
end
Bank.ItemKey = ItemKey

-- Wer darf was ----------------------------------------------------------------------------------
-- Rang „Mitglied“ (Nummer in der Gildenliste); ohne diesen Rang darf jeder in der Gilde anfragen
local function MemberRank()
    if not GuildControlGetNumRanks then return nil end
    for i = 1, GuildControlGetNumRanks() or 0 do
        local name = GuildControlGetRankName(i)
        if type(name) == "string" and ns.Lower(strtrim(name)) == "mitglied" then return i end
    end
end

function Bank:MayRequest(name)
    if not IsInGuild() or not ns.Info:AtHome() then return false end
    local e = ns.Members:Find(name)
    if not e then return false end
    local limit = MemberRank()
    if not limit then return true end
    local person = (e.main and e.trusted ~= false) and e.main or e
    return (person.rankOrder or 99) <= limit or (e.rankOrder or 99) <= limit
end

function Bank:IsOfficer(name) return ns.Board:IsOfficer(name) end
function Bank:AmOfficer() return ns.Board:AmOfficer() end
function Bank:Open() return IsInGuild() and ns.Info:AtHome() end

-- Serialisieren -----------------------------------------------------------------------------------
local REQ = { "id", "who", "created", "updated", "item", "name", "quality", "qty", "note", "st", "by" }
local REQ_NUM = { created = true, updated = true, quality = true, qty = true }

function Bank:Serialize(r)
    if r.kind == "T" then
        local parts = { table.concat({ "T", r.id, r.tab, r.tabName or "", r.time, r.by or "" }, "^") }
        for _, it in ipairs(r.items or {}) do
            table.insert(parts, table.concat({ "I", it.item, it.name or "", it.quality or 1, it.count }, "^"))
        end
        return table.concat(parts, "~")
    end
    local f = {}
    for i, k in ipairs(REQ) do f[i] = tostring(r[k] or "") end
    return "R^" .. table.concat(f, "^")
end

function Bank:Digest(r) return Hash(self:Serialize(r)) end

function Bank:Parse(data)
    local records = Split(data or "", "~")
    local f = Split(records[1] or "", "^")
    if f[1] == "T" then
        local r = { kind = "T", id = f[2], tab = tonumber(f[3]), tabName = Clean(f[4], 40), time = tonumber(f[5]), by = f[6], items = {} }
        if not r.tab or r.id ~= ("t" .. r.tab) or not r.time then return nil end
        for i = 2, #records do
            local it = Split(records[i], "^")
            if it[1] == "I" and ns.Market.ItemID(it[2]) then
                table.insert(r.items, { item = it[2], name = Clean(it[3], 120), quality = tonumber(it[4]) or 1, count = math.max(1, tonumber(it[5]) or 1) })
            end
        end
        return r
    elseif f[1] == "R" and #f >= #REQ + 1 then
        local r = { kind = "R" }
        for i, k in ipairs(REQ) do
            r[k] = f[i + 1]
            if REQ_NUM[k] then r[k] = tonumber(r[k]) end
        end
        if not r.id or r.id == "" or not r.who or r.who == "" or not r.created or not r.updated then return nil end
        if not Bank.STATES[r.st or ""] or not ns.Market.ItemID(r.item) then return nil end
        r.qty = math.max(1, math.floor(r.qty or 1))
        r.name, r.note = Clean(r.name, 120), Clean(r.note, NOTE_MAX)
        return r
    end
end

-- Zusammenführen -------------------------------------------------------------------------------------
function Bank:Merge(incoming, fromNetwork)
    local recs = DB().records
    local mine = recs[incoming.id]
    if incoming.kind == "T" then
        if incoming.time > Now() + 3600 then return nil end
        if mine and mine.time >= incoming.time then return nil end
        recs[incoming.id] = incoming
        return mine and "geändert" or "neu"
    end
    if incoming.created > Now() + 86400 then return nil end
    if fromNetwork and not mine then
        local n = 0
        for _ in pairs(recs) do n = n + 1 end
        if n >= MAX_RECORDS then return nil end
    end
    if not mine then
        recs[incoming.id] = incoming
        return "neu"
    end
    if mine.who ~= incoming.who or mine.created ~= incoming.created then return nil end
    local newer = incoming.updated > mine.updated
        or (incoming.updated == mine.updated and (RANK[incoming.st] or 0) > (RANK[mine.st] or 0))
    if not newer then return nil end
    -- Erledigtes bleibt erledigt
    if (mine.st == "versandt" or mine.st == "abgelehnt" or mine.st == "zurueck") and OPEN_STATES[incoming.st] then return nil end
    recs[incoming.id] = incoming
    return "geändert"
end

-- Senden ----------------------------------------------------------------------------------------------
function Bank:Broadcast(r, urgent)
    if not self:Open() then return end
    local data = self:Serialize(r)
    self.recent[r.id] = { digest = Hash(data), at = GetTime() }
    ns.WhenChatFree(function() ns.Comm:SendLarge("BNKN", data, "GUILD", nil, urgent) end)
end

local function Touch(r) r.updated = math.max(Now(), (r.updated or 0) + 1) end

-- Bestand ------------------------------------------------------------------------------------------------
-- Alles zusammengezählt: { item, name, quality, count, tabs = { [fach] = true } }
function Bank:Stock(search)
    search = search and ns.Lower(strtrim(search)) or ""
    local byItem, list = {}, {}
    for _, r in pairs(DB().records) do
        if r.kind == "T" then
            for _, it in ipairs(r.items) do
                local e = byItem[it.item]
                if not e then
                    e = { item = it.item, name = it.name, quality = it.quality, count = 0, tabs = {} }
                    byItem[it.item] = e
                end
                e.count = e.count + it.count
                e.tabs[r.tabName ~= "" and r.tabName or ("Fach " .. r.tab)] = true
            end
        end
    end
    for _, e in pairs(byItem) do
        if search == "" or ns.Lower(e.name or ""):find(search, 1, true) then table.insert(list, e) end
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    return list
end

function Bank:StockOf(item)
    for _, e in ipairs(self:Stock()) do
        if e.item == item then return e.count end
    end
    return 0
end

-- Stand: jüngstes Fach
function Bank:LastScan()
    local best
    for _, r in pairs(DB().records) do
        if r.kind == "T" and (not best or r.time > best.time) then best = r end
    end
    return best
end

-- Gildenbank auslesen (nur bei offener Bank): Fächer, die man sehen darf
local function TabInfo(tab)
    if not GetGuildBankTabInfo then return nil end
    local name, _, viewable = GetGuildBankTabInfo(tab)
    return name, viewable
end

function Bank:ReadTab(tab)
    local items, byItem = {}, {}
    self.live[tab] = {}
    for slot = 1, SLOTS do
        local link = GetGuildBankItemLink and GetGuildBankItemLink(tab, slot)
        if link then
            local _, count = GetGuildBankItemInfo(tab, slot)
            local key = ItemKey(link)
            if key then
                count = math.max(1, tonumber(count) or 1)
                table.insert(self.live[tab], { slot = slot, item = key, id = ns.Market.ItemID(key), count = count })
                local it = byItem[key]
                if not it then
                    local name = link:match("|h%[(.-)%]|h")
                    local ok, iname, _, quality = pcall(ns.GetItemInfo, link)
                    it = { item = key, name = Clean((ok and iname) or name or "?", 120), quality = (ok and quality) or 1, count = 0 }
                    byItem[key] = it
                    table.insert(items, it)
                end
                it.count = it.count + count
            end
        end
    end
    table.sort(items, function(a, b) return a.item < b.item end)
    return items
end

function Bank:Scan()
    if not self.bankOpen or not GetNumGuildBankTabs then return end
    local me = ns.UnitFullName("player")
    for tab = 1, GetNumGuildBankTabs() or 0 do
        local name, viewable = TabInfo(tab)
        if viewable then
            local items = self:ReadTab(tab)
            local r = { kind = "T", id = "t" .. tab, tab = tab, tabName = Clean(name or "", 40), time = Now(), by = me, items = items }
            local old = DB().records[r.id]
            -- Nur melden, wenn sich der Inhalt geändert hat (oder der letzte Stand älter als eine Stunde ist)
            local function Body(x) return (self:Serialize(x):gsub("^[^~]*", "")) end
            local changed = not old or Body(old) ~= Body(r) or old.tabName ~= r.tabName
            if changed or Now() - old.time > 3600 then
                DB().records[r.id] = r
                self:Broadcast(r)
            end
        end
    end
    ns:Fire("GUILDBANK_UPDATE")
end

local scanTimer
local function ScanSoon(delay)
    if scanTimer then return end
    scanTimer = true
    C_Timer.After(delay or 1.5, function()
        scanTimer = nil
        Bank:Scan()
    end)
end

function Bank:BankOpened()
    self.bankOpen = true
    if GetNumGuildBankTabs and QueryGuildBankTab then
        for tab = 1, GetNumGuildBankTabs() or 0 do
            C_Timer.After(0.3 * tab, function() if Bank.bankOpen then pcall(QueryGuildBankTab, tab) end end)
        end
    end
    ScanSoon(3)
    ns:Fire("GUILDBANK_UPDATE")
end

function Bank:BankClosed()
    self.bankOpen = false
    ns:Fire("GUILDBANK_UPDATE")
end

-- Anfragen -------------------------------------------------------------------------------------------------
function Bank:Requests(filter)
    local list, now = {}, Now()
    for _, r in pairs(DB().records) do
        if r.kind == "R" and (not filter or filter(r)) then table.insert(list, r) end
    end
    table.sort(list, function(a, b)
        local oa, ob = OPEN_STATES[a.st] and 1 or 0, OPEN_STATES[b.st] and 1 or 0
        if oa ~= ob then return oa > ob end
        if a.st ~= b.st then return (RANK[a.st] or 0) < (RANK[b.st] or 0) end
        return a.created > b.created
    end)
    return list
end

local function CountOpen(who)
    local n = 0
    for _, r in pairs(DB().records) do
        if r.kind == "R" and OPEN_STATES[r.st] and ns.Board:SamePerson(r.who, who) then n = n + 1 end
    end
    return n
end

function Bank:Ask(item, qty, note)
    local me = ns.UnitFullName("player")
    if not self:Open() then return false, "Die Gildenbank gibt es nur für Charaktere in der Gilde." end
    if not self:MayRequest(me) then return false, "Anfragen dürfen Mitglieder ab dem Rang „Mitglied“." end
    local stock
    for _, e in ipairs(self:Stock()) do if e.item == item then stock = e end end
    if not stock then return false, "Das liegt nicht (mehr) in der Gildenbank." end
    qty = math.max(1, math.floor(tonumber(qty) or 1))
    if qty > stock.count then return false, "In der Gildenbank liegen nur " .. stock.count .. "." end
    if CountOpen(me) >= MAX_OPEN then return false, "Du hast schon " .. MAX_OPEN .. " offene Anfragen." end
    local now = Now()
    local r = { kind = "R", id = string.format("%x%04x", now, math.random(0, 65535)), who = me, created = now, updated = now,
        item = item, name = stock.name, quality = stock.quality, qty = qty, note = Clean(note, NOTE_MAX), st = "neu", by = "" }
    DB().records[r.id] = r
    self.notified[r.id .. ":neu"] = true
    self:Broadcast(r, true)
    ns:Fire("GUILDBANK_UPDATE")
    return true, r
end

function Bank:Withdraw(id)
    local r = DB().records[id]
    if not r or r.st ~= "neu" or not ns.Board:IsMePerson(r.who) then return end
    r.st = "zurueck"
    Touch(r)
    self:Broadcast(r, true)
    ns:Fire("GUILDBANK_UPDATE")
end

-- Offizier: frei / abgelehnt / versandt
function Bank:Decide(id, st)
    local r = DB().records[id]
    if not r or not self:AmOfficer() then return false end
    if st == "frei" or st == "abgelehnt" then
        if r.st ~= "neu" then return false end
    elseif st == "versandt" then
        if not OPEN_STATES[r.st] then return false end
    else
        return false
    end
    r.st, r.by = st, ns.UnitFullName("player")
    Touch(r)
    self:Broadcast(r, true)
    ns:Fire("GUILDBANK_UPDATE")
    return true
end

-- Wartet auf die Leitung (neu) bzw. auf den Versand (frei)
function Bank:OpenCount()
    if not self:AmOfficer() then return 0 end
    local n = 0
    for _, r in pairs(DB().records) do
        if r.kind == "R" and OPEN_STATES[r.st] then n = n + 1 end
    end
    return n
end

-- An der Bank: freigegebene Menge in die Taschen holen ------------------------------------------------------
local function FreeBagSlot()
    local C = C_Container
    if not C then return nil end
    for bag = 0, 4 do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            if not C.GetContainerItemInfo(bag, slot) then return bag, slot end
        end
    end
end

function Bank:Take(id, done)
    local r = DB().records[id]
    if not r or r.st ~= "frei" then return false, "Diese Anfrage ist nicht freigegeben." end
    if not self.bankOpen then return false, "Öffne zuerst die Gildenbank." end
    -- Plätze mit dem Gegenstand (frisch gelesen)
    local slots, have = {}, 0
    for tab = 1, GetNumGuildBankTabs and GetNumGuildBankTabs() or 0 do
        local _, viewable = TabInfo(tab)
        if viewable then
            self:ReadTab(tab)
            for _, s in ipairs(self.live[tab] or {}) do
                if s.item == r.item or s.id == ns.Market.ItemID(r.item) then
                    table.insert(slots, { tab = tab, slot = s.slot, n = s.count })
                    have = have + s.count
                end
            end
        end
    end
    if have < r.qty then return false, "In der Gildenbank liegen nur noch " .. have .. "." end
    table.sort(slots, function(a, b) return a.n > b.n end)
    local rest, steps = r.qty, {}
    for _, s in ipairs(slots) do
        if rest <= 0 then break end
        if s.n <= rest then
            table.insert(steps, function() return pcall(AutoStoreGuildBankItem, s.tab, s.slot) end)
            rest = rest - s.n
        else
            local n = rest
            table.insert(steps, function()
                local bag, slot = FreeBagSlot()
                if not bag then return false end
                local ok = pcall(SplitGuildBankItem, s.tab, s.slot, n)
                if ok then ok = pcall(C_Container.PickupContainerItem, bag, slot) end
                if CursorHasItem and CursorHasItem() then ClearCursor() return false end
                return ok
            end)
            rest = 0
        end
    end
    -- Nacheinander mit kurzer Pause: Die Gildenbank sperrt Plätze, bis der Server bestätigt
    local i = 0
    local function Next()
        i = i + 1
        local step = steps[i]
        if not step then
            if done then done(true) end
            return
        end
        if not step() then
            if done then done(false) end
            return
        end
        C_Timer.After(0.8, Next)
    end
    Next()
    return true
end

-- Am Briefkasten: Brief ohne Nachnahme vorbereiten, Ware anlegen
function Bank:PrepareMail(id)
    local r = DB().records[id]
    if not r or r.st ~= "frei" then return false, "Diese Anfrage ist nicht freigegeben." end
    if not ns.Market.mailOpen then return false, "Öffne zuerst einen Briefkasten." end
    if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, nil, 2) end
    if SendMailNameEditBox then SendMailNameEditBox:SetText(r.who) end
    if SendMailSubjectEditBox then
        SendMailSubjectEditBox:SetText("Aus der Gildenbank: " .. (r.qty > 1 and (r.qty .. "x ") or "") .. (r.name or ""))
    end
    if SendMailRadioButton_OnClick then pcall(SendMailRadioButton_OnClick, 1) end
    if MoneyInputFrame_SetCopper and SendMailMoney then pcall(MoneyInputFrame_SetCopper, SendMailMoney, 0) end
    local attached, why = ns.Market:AttachItem({ kind = "s", item = r.item, count = 1 }, r.qty)
    self.pendingMail = { id = id, who = r.who, at = GetTime() }
    return true, attached, why
end

-- Hinweise -------------------------------------------------------------------------------------------------
function Bank:CheckNews(r)
    if r.kind ~= "R" then return end
    local tag = r.id .. ":" .. r.st
    if self.notified[tag] then return end
    self.notified[tag] = true
    local what = (r.qty > 1 and (r.qty .. "x ") or "") .. (r.name or "?")
    local mine = ns.Board:IsMePerson(r.who)
    if r.st == "neu" and not mine and self:AmOfficer() then
        ns.Sound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960, "Master", true)
        ns.Print(string.format("|cfff3dc9aGildenbank:|r %s möchte %s%s – /ea bank",
            ns.ShortName(r.who), what, r.note ~= "" and (" („" .. r.note .. "“)") or ""))
    elseif mine and r.st == "frei" then
        ns.Print(string.format("|cfff3dc9aGildenbank:|r %s hat %s für dich freigegeben – kommt per Brief.", ns.ShortName(r.by), what))
    elseif mine and r.st == "abgelehnt" then
        ns.Print(string.format("|cfff3dc9aGildenbank:|r %s hat deine Anfrage für %s abgelehnt.", ns.ShortName(r.by), what))
    elseif mine and r.st == "versandt" then
        ns.Print(string.format("|cfff3dc9aGildenbank:|r %s ist unterwegs zu dir – schau in deinen Briefkasten.", what))
    end
end

-- Empfang und Abgleich ----------------------------------------------------------------------------------------
function Bank:Receive(data)
    if not self:Open() then return end
    local r = self:Parse(data)
    if not r then return end
    self.recent[r.id] = { digest = Hash(data), at = GetTime() }
    if self:Merge(r, true) then
        self:CheckNews(DB().records[r.id])
        ns:Fire("GUILDBANK_UPDATE")
    end
end

function Bank:Inventory()
    local parts = {}
    for id, r in pairs(DB().records) do table.insert(parts, id .. ":" .. self:Digest(r)) end
    return table.concat(parts, ";")
end

function Bank:RequestSync()
    if not self:Open() then return end
    local req = string.format("%x", math.random(0, 16777215))
    ns.WhenChatFree(function() ns.Comm:SendLarge("BNKQ", req .. "#" .. Bank:Inventory(), "GUILD") end)
end

function Bank:AnswerRequest(sender, data)
    if not self:Open() then return end
    local req, inv = data:match("^([^#]*)#(.*)$")
    if not req then return end
    local theirs = {}
    for id, digest in inv:gmatch("([^:;]+):([^;]+)") do theirs[id] = digest end
    local send, want = {}, {}
    for id, r in pairs(DB().records) do
        if theirs[id] ~= self:Digest(r) then table.insert(send, id) end
    end
    for id, digest in pairs(theirs) do
        local r = DB().records[id]
        if not r or self:Digest(r) ~= digest then table.insert(want, id) end
    end
    if #send == 0 and #want == 0 then return end
    local asked = GetTime()
    C_Timer.After(1.5 + math.random() * 6, function()
        if Bank.answered[req] then return end
        Bank.answered[req] = true
        ns.Comm:Send("BNKA", req, "GUILD")
        for _, id in ipairs(send) do
            local r = DB().records[id]
            local rc = Bank.recent[id]
            if r and not (rc and rc.at > asked and rc.digest == Bank:Digest(r)) then Bank:Broadcast(r) end
        end
        if #want > 0 then
            ns.WhenChatFree(function() ns.Comm:SendLarge("BNKW", table.concat(want, ";"), "WHISPER", sender) end)
        end
    end)
end

function Bank:SendWanted(list)
    if not self:Open() then return end
    for id in (list or ""):gmatch("[^;]+") do
        local r = DB().records[id]
        if r then
            local rc = self.recent[id]
            if not (rc and GetTime() - rc.at < 30 and rc.digest == self:Digest(r)) then self:Broadcast(r) end
        end
    end
end

ns.Comm.handlers.BNKN = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if data then Bank:Receive(data) end
end
ns.Comm.handlers.BNKQ = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if data and ns.Members:Find(sender) then Bank:AnswerRequest(sender, data) end
end
ns.Comm.handlers.BNKA = function(_, parts)
    if parts[2] then Bank.answered[parts[2]] = true end
end
ns.Comm.handlers.BNKW = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if data then Bank:SendWanted(data) end
end

-- Aufräumen ---------------------------------------------------------------------------------------------------
function Bank:Prune()
    local now = Now()
    for id, r in pairs(DB().records) do
        if r.kind == "R" then
            local keep = OPEN_STATES[r.st] and KEEP_OPEN_DAYS or KEEP_DONE_DAYS
            if now - r.updated > keep * 86400 then DB().records[id] = nil end
        end
    end
end

-- Events ------------------------------------------------------------------------------------------------------
pcall(ns.On, ns, "GUILDBANKFRAME_OPENED", function() Bank:BankOpened() end)
pcall(ns.On, ns, "GUILDBANKFRAME_CLOSED", function() Bank:BankClosed() end)
pcall(ns.On, ns, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
    local gb = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker or 10
    if kind == gb then Bank:BankOpened() end
end)
pcall(ns.On, ns, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", function(kind)
    local gb = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker or 10
    if kind == gb then Bank:BankClosed() end
end)
pcall(ns.On, ns, "GUILDBANKBAGSLOTS_CHANGED", function() if Bank.bankOpen then ScanSoon(1.5) end end)

if hooksecurefunc and SendMail then
    hooksecurefunc("SendMail", function(recipient) Bank.sendingTo = recipient end)
end
pcall(ns.On, ns, "MAIL_SEND_SUCCESS", function()
    local p = Bank.pendingMail
    if p and Bank.sendingTo and ns.SameName(Bank.sendingTo, p.who) and GetTime() - p.at < 900 then
        Bank.pendingMail = nil
        Bank:Decide(p.id, "versandt")
        ns.Print("|cfff3dc9aGildenbank:|r Brief an " .. ns.ShortName(p.who) .. " ist unterwegs – als verschickt markiert.")
    end
    Bank.sendingTo = nil
end)

ns:Listen("INIT", function()
    Bank:Prune()
end)

ns:On("PLAYER_LOGIN", function()
    C_Timer.After(35 + math.random() * 15, function() Bank:RequestSync() end)
    C_Timer.After(85, function()
        local n = Bank:OpenCount()
        if n > 0 then
            ns.Print("|cfff3dc9aGildenbank:|r " .. (n == 1 and "1 offene Anfrage" or (n .. " offene Anfragen")) .. " – /ea bank")
        end
    end)
end)
