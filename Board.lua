-- Elternabend: Pinnwand – das schwarze Brett der Gilde
--
-- Jedes Mitglied heftet Zettel an: an alle, an eine Gruppe (Offiziere, ein Rang, eine
-- Klasse) oder an eine einzelne Person. Zettel laufen nach einer gewählten Zeit ab.
-- Andere reagieren („Bin dabei“, „Ich helfe“ …) oder antworten; der Ersteller hakt ab,
-- Offiziere pinnen an oder nehmen Zettel ab.
--
-- Addons haben keinen Server. Die Zettel wandern deshalb von Addon zu Addon:
--   * Neue oder geänderte Zettel gehen sofort über den Gildenkanal an alle, die online sind.
--   * Beim Einloggen schickt das Addon eine Liste seiner Zettel (Kennung + Prüfsumme).
--     Ein anderes Addon antwortet mit allem, was fehlt oder anders ist, und fragt
--     umgekehrt nach den Zetteln, die es selbst noch nicht kennt.
-- So erreicht ein Zettel auch Leute, die erst später online kommen – solange jemand,
-- der ihn kennt, zur selben Zeit online ist.
--
-- Nachrichten (alle über Comm, große mit SendLarge):
--   BRDN  <Zettel>              ein Zettel mit Reaktionen und Antworten (GUILD)
--   BRDQ  <Anfrage>#<Liste>      Abgleich beim Einloggen: id:prüfsumme;… (GUILD)
--   BRDA  <Anfrage>              „Ich antworte schon“ – andere sparen sich die Antwort
--   BRDW  id;id;…                „Diese Zettel kenne ich nicht, schick sie bitte“ (WHISPER)
--
-- Format eines Zettels: Datensätze mit „~“ getrennt, Felder mit „^“.
--   N^id^author^created^updated^expires^cat^to^when^pinned^state^editedBy^title^text
--   R^name^wert^zeit                       Reaktion (1 = dabei, 0 = zurückgenommen)
--   A^rid^author^zeit^state^text           Antwort (state: "" oder "x" = entfernt)
local _, ns = ...

local Board = { recent = {}, pendingNotify = {}, answered = {} }
ns.Board = Board

local MAX_DAYS = 14          -- längste Laufzeit eines Zettels
local MAX_OPEN = 5           -- offene Zettel pro Spieler (Offiziere: OFFICER_OPEN)
local OFFICER_OPEN = 10
local MAX_NOTES = 250        -- mehr speichert das Addon nicht
local MAX_REPLIES = 25
local TITLE_MAX, TEXT_MAX, REPLY_MAX = 80, 2000, 400 -- Zeichen (nicht Bytes)
Board.TITLE_MAX, Board.TEXT_MAX, Board.REPLY_MAX = TITLE_MAX, TEXT_MAX, REPLY_MAX
local OFFICER_RANKS = 3      -- Rang 1 bis 3 der Gilde zählt als Offizier

Board.CATS = {
    { key = "info", label = "Info", react = "Gefällt mir", reacted = "gefällt das", color = "cream" },
    { key = "aktion", label = "Aktion", react = "Bin dabei", reacted = "ist dabei", color = "goldBright", date = true },
    { key = "suche", label = "Suche", react = "Kann helfen", reacted = "kann helfen", color = "orange" },
    { key = "biete", label = "Biete", react = "Interesse", reacted = "hat Interesse", color = "green" },
    { key = "hilfe", label = "Hilfe gesucht", react = "Ich helfe", reacted = "hilft", color = "red" },
    { key = "dank", label = "Danke", react = "Gefällt mir", reacted = "gefällt das", color = "goldBright" },
}
Board.CAT = {}
for _, c in ipairs(Board.CATS) do Board.CAT[c.key] = c end

Board.DURATIONS = {
    { days = 1, label = "1 Tag" },
    { days = 3, label = "3 Tage" },
    { days = 7, label = "1 Woche" },
    { days = 14, label = "2 Wochen" },
}

local function DB() return ns.db.board end

function Board.Now()
    return GetServerTime and GetServerTime() or time()
end
local Now = Board.Now

-- Texte von allem befreien, was das Format oder den Chat stört
-- Nach max Zeichen abschneiden (UTF-8: Umlaute zählen als ein Zeichen)
local function Cut(s, max)
    local chars, i, n = 0, 1, #s
    while i <= n do
        local b = s:byte(i)
        local len = b < 0x80 and 1 or (b >= 0xF0 and 4) or (b >= 0xE0 and 3) or (b >= 0xC0 and 2) or 1
        chars = chars + 1
        if chars > max then return s:sub(1, i - 1) end
        i = i + len
    end
    return s
end

-- Zeilenumbruch beim Übertragen (Nachrichten und Webseiten-Export sind zeilenweise)
local NL = "\194\166" -- „¦“

-- Text säubern. lines = Zeilenumbrüche behalten (für Beschreibung und Antworten)
local function Clean(s, max, lines)
    s = tostring(s or ""):gsub(NL, "\n"):gsub("[%^~|]", ""):gsub("\t", " ")
    if lines then
        s = s:gsub("\r\n?", "\n"):gsub("[ ]+\n", "\n"):gsub("\n\n\n+", "\n\n"):gsub("[ ]+", " ")
        s = s:gsub("^%s+", ""):gsub("%s+$", "")
    else
        s = strtrim((s:gsub("%s+", " ")))
    end
    if max then s = Cut(s, max) end
    return s
end
Board.Clean = Clean

-- Gegenstände im Text ------------------------------------------------------------------
-- Per Umschalt-Klick landet ein Gegenstandslink im Zettel. Links enthalten „|“ und sind lang; übertragen und
-- gespeichert wird deshalb die Kurzform {Name#Gegenstands-ID}. Beim Anzeigen wird daraus wieder ein Link
-- mit Tooltip (Board.Markup). Ältere Addon-Versionen und die Webseite zeigen die Kurzform bzw. den Namen.
function Board.Pack(text)
    text = tostring(text or "")
    local function Short(id, name)
        name = name:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("[{}#|]", ""):gsub("%s+", " ")
        name = strtrim(name)
        if name == "" then return "" end
        return "{" .. name .. "#" .. id .. "}"
    end
    -- mit Farbe (alt: |cffa335ee…, neu: |cnIQ4:…) und ohne
    text = text:gsub("|c[^|]*|Hitem:(%d+)[^|]*|h%[(.-)%]|h|r", Short)
    text = text:gsub("|Hitem:(%d+)[^|]*|h%[(.-)%]|h", Short)
    return text
end

-- Kurzform → anklickbarer Link in der Farbe der Qualität. plain: nur farbiger Name (für Tooltips)
function Board.Markup(text, plain)
    if not text or not text:find("{", 1, true) then return text end
    return (text:gsub("{([^{}#\n]+)#(%d+)}", function(name, id)
        local quality
        if C_Item and C_Item.GetItemQualityByID then
            local ok, q = pcall(C_Item.GetItemQualityByID, tonumber(id))
            if ok then quality = q end
        end
        local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
        local color = c and c.hex or "|cffffffff"
        if plain then return color .. "[" .. name .. "]|r" end
        return color .. "|Hitem:" .. id .. "::::::::|h[" .. name .. "]|h|r"
    end))
end

local function Encode(s) return (tostring(s or ""):gsub("\n", NL)) end
local function Decode(s) return (tostring(s or ""):gsub(NL, "\n")) end
Board.Clean = Clean

-- Prüfsumme (djb2, 32 Bit) als kurzer Text
local function Hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + s:byte(i)) % 4294967296
    end
    return string.format("%x", h)
end

-- Serialisieren -----------------------------------------------------------------------
local BODY = { "id", "author", "created", "updated", "expires", "cat", "to", "when", "pinned", "state", "editedBy", "title", "text" }
-- Danach optional: keep („1“ = bleibt dauerhaft auf der Webseite). Nur angehängt, wenn gesetzt,
-- damit Zettel ohne Markierung genauso aussehen wie bei älteren Addon-Versionen.

local function BodyString(n)
    local f = {}
    for i, k in ipairs(BODY) do
        local v = n[k]
        if k == "pinned" then v = v and "1" or "0" end
        if k == "text" then v = Encode(v) end
        f[i] = tostring(v or "")
    end
    return "N^" .. table.concat(f, "^") .. (n.keep and "^1" or "")
end

function Board:Serialize(n)
    local parts = { BodyString(n) }
    local keys = {}
    for k in pairs(n.reacts or {}) do table.insert(keys, k) end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local r = n.reacts[k]
        table.insert(parts, table.concat({ "R", r.name, r.v, r.t }, "^"))
    end
    local rids = {}
    for rid in pairs(n.replies or {}) do table.insert(rids, rid) end
    table.sort(rids)
    for _, rid in ipairs(rids) do
        local a = n.replies[rid]
        table.insert(parts, table.concat({ "A", rid, a.author, a.time, a.state or "", Encode(a.text) }, "^"))
    end
    return table.concat(parts, "~")
end

function Board:Digest(n)
    return Hash(self:Serialize(n))
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

function Board:Parse(data)
    local records = Split(data, "~")
    local f = Split(records[1] or "", "^")
    if f[1] ~= "N" or #f < #BODY + 1 then return nil end
    local n = { reacts = {}, replies = {} }
    for i, k in ipairs(BODY) do n[k] = f[i + 1] end
    for _, k in ipairs({ "created", "updated", "expires", "when" }) do n[k] = tonumber(n[k]) end
    n.pinned = n.pinned == "1"
    n.keep = f[#BODY + 2] == "1" or nil
    if n.when == 0 then n.when = nil end
    if not n.id or n.id == "" or not n.author or n.author == "" or not n.created or not n.updated or not n.expires then return nil end
    if not self.CAT[n.cat] then n.cat = "info" end
    if n.state ~= "offen" and n.state ~= "erledigt" and n.state ~= "entfernt" then n.state = "offen" end
    n.title = Clean(n.title, TITLE_MAX)
    n.text = Clean(Decode(n.text), TEXT_MAX, true)
    for i = 2, #records do
        local r = Split(records[i], "^")
        if r[1] == "R" and r[2] and r[2] ~= "" then
            local key = ns.NameKey(r[2])
            if key then n.reacts[key] = { name = r[2], v = tonumber(r[3]) == 1 and 1 or 0, t = tonumber(r[4]) or 0 } end
        elseif r[1] == "A" and r[2] and r[2] ~= "" and r[3] and r[3] ~= "" then
            n.replies[r[2]] = { author = r[3], time = tonumber(r[4]) or 0, state = r[5] == "x" and "x" or "", text = Clean(Decode(r[6]), REPLY_MAX, true) }
        end
    end
    return n
end

-- Wer bin ich, wer ist wer ------------------------------------------------------------
-- Einer meiner Charaktere (accountweit)?
function Board:IsMine(name)
    local key = ns.NameKey(name)
    if not key then return false end
    if ns.db.myChars[key] then return true end
    return ns.SameName(name, ns.PlayerKey())
end

-- Derselbe Spieler (Main und Twinks gelten als eine Person)?
local function PersonKey(name)
    local e = ns.Members:Find(name)
    if e then return (e.main or e).key end
    return ns.NameKey(name)
end

function Board:SamePerson(a, b)
    if ns.SameName(a, b) then return true end
    local ka, kb = PersonKey(a), PersonKey(b)
    return ka ~= nil and ka == kb
end

-- Personenschlüssel meiner Charaktere (wird neu gebaut, wenn sich die Gildenliste ändert)
local myPersons
function Board:IsMePerson(name)
    if self:IsMine(name) then return true end
    if not myPersons then
        myPersons = {}
        for key in pairs(ns.db.myChars) do
            local pk = PersonKey(key)
            if pk then myPersons[pk] = true end
        end
    end
    local pk = PersonKey(name)
    return pk ~= nil and myPersons[pk] == true
end
ns:Listen("MEMBERS_UPDATE", function() myPersons = nil end)

function Board:IsOfficer(name)
    local e = ns.Members:Find(name)
    if not e then return false end
    if (e.rankOrder or 99) <= OFFICER_RANKS then return true end
    -- Twinks von Offizieren – aber nicht, wenn sich jemand nur selbst als deren Twink gemeldet hat
    return e.main ~= nil and e.trusted ~= false and (e.main.rankOrder or 99) <= OFFICER_RANKS
end

function Board:AmOfficer()
    if ns.UI and ns.UI.IsLeader and ns.UI:IsLeader() then return true end
    return self:IsOfficer(ns.UnitFullName("player"))
end

-- Empfänger ---------------------------------------------------------------------------
--   all | off | rank:<Rangname> | class:<KLASSE> | p:<Name>
function Board:ToLabel(to)
    if to == "all" or not to or to == "" then return "Alle" end
    if to == "off" then return "Offiziere" end
    local kind, value = to:match("^(%a+):(.+)$")
    if kind == "rank" then return "Rang " .. value end
    if kind == "class" then
        return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[value]) or value
    end
    if kind == "p" then return ns.ShortName(value) or value end
    return to
end

function Board:IsPersonal(n)
    return (n.to or ""):sub(1, 2) == "p:"
end

function Board:IsForMe(n)
    local to = n.to or "all"
    if to == "all" then return true end
    if to == "off" then return self:AmOfficer() end
    local kind, value = to:match("^(%a+):(.+)$")
    if kind == "rank" then
        local rankName = IsInGuild() and select(2, GetGuildInfo("player"))
        return rankName ~= nil and rankName == value
    end
    if kind == "class" then return select(2, UnitClass("player")) == value end
    if kind == "p" then return self:IsMePerson(value) end
    return false
end

-- Darf ich den Zettel sehen? Persönliche Zettel nur Absender und Empfänger.
-- Die Pinnwand gehört der Gilde. Die Zettel sind zwar accountweit gespeichert, aber ein Charakter, der nicht
-- (mehr) in dieser Gilde ist, sieht sie nicht – weder den Reiter noch einzelne Zettel (siehe Info:AtHome).
function Board:Open()
    return ns.Info:AtHome()
end

function Board:IsVisible(n)
    if not self:Open() then return false end
    if n.state == "entfernt" or (n.expires or 0) <= Now() then return false end
    if self:IsPersonal(n) then return self:IsMePerson(n.author) or self:IsForMe(n) end
    return true
end

-- Speichern und Zusammenführen ----------------------------------------------------------
local function CountOpen(author)
    local count, now = 0, Now()
    for _, n in pairs(DB().notes) do
        if n.state ~= "entfernt" and n.expires > now and Board:SamePerson(n.author, author) then count = count + 1 end
    end
    return count
end

-- Ist eine Änderung am Zettel erlaubt? Inhalt nur vom Ersteller, Anpinnen nur von
-- Offizieren, Erledigt/Abnehmen vom Ersteller oder von Offizieren.
local function BodyAllowed(old, new)
    local editor = new.editedBy ~= "" and new.editedBy or new.author
    local byAuthor = Board:SamePerson(editor, new.author)
    local byOfficer = Board:IsOfficer(editor)
    if not old then
        if (new.pinned or new.keep) and not Board:IsOfficer(new.author) and not byOfficer then return false end
        return true
    end
    if old.author ~= new.author or old.created ~= new.created then return false end
    local contentChanged = old.title ~= new.title or old.text ~= new.text or old.cat ~= new.cat or old.to ~= new.to
        or old.when ~= new.when or old.expires ~= new.expires
    if contentChanged and not byAuthor then return false end
    if (old.pinned ~= new.pinned or (old.keep or false) ~= (new.keep or false)) and not byOfficer then return false end
    if old.state ~= new.state and not byAuthor and not byOfficer then return false end
    return true
end

-- Eingehenden Zettel übernehmen. Liefert „neu“, „geändert“ oder nil.
function Board:Merge(incoming, fromNetwork)
    local now = Now()
    if (incoming.expires or 0) <= now then return nil end
    if incoming.expires > incoming.created + (MAX_DAYS + 1) * 86400 then return nil end
    if incoming.created > now + 86400 then return nil end
    local notes = DB().notes
    local local_ = notes[incoming.id]
    local result

    if not local_ then
        if fromNetwork then
            local total = 0
            for _ in pairs(notes) do total = total + 1 end
            if total >= MAX_NOTES then return nil end
            if incoming.state ~= "entfernt" and CountOpen(incoming.author) >= OFFICER_OPEN + 2 then return nil end
        end
        if not BodyAllowed(nil, incoming) then incoming.pinned, incoming.keep = false, nil end
        notes[incoming.id] = incoming
        return "neu"
    end

    local before = self:Digest(local_)
    -- Inhalt: jüngere Fassung gewinnt (bei Gleichstand entscheidet der Text, damit alle gleich wählen)
    local newer = incoming.updated > local_.updated
        or (incoming.updated == local_.updated and BodyString(incoming) > BodyString(local_))
    if newer and BodyAllowed(local_, incoming) then
        for _, k in ipairs(BODY) do local_[k] = incoming[k] end
        local_.keep = incoming.keep
    end
    -- Reaktionen: pro Person die jüngste
    for key, r in pairs(incoming.reacts or {}) do
        local mine = local_.reacts[key]
        if not mine or r.t > mine.t or (r.t == mine.t and r.v > mine.v) then local_.reacts[key] = r end
    end
    -- Antworten: alle sammeln, „entfernt“ gewinnt
    local count = 0
    for _ in pairs(local_.replies) do count = count + 1 end
    for rid, a in pairs(incoming.replies or {}) do
        local mine = local_.replies[rid]
        if not mine then
            if count < MAX_REPLIES then
                local_.replies[rid] = a
                count = count + 1
            end
        elseif a.state == "x" and mine.state ~= "x" then
            mine.state = "x"
        end
    end
    if self:Digest(local_) ~= before then result = "geändert" end
    return result, local_
end

-- Senden ------------------------------------------------------------------------------
function Board:Broadcast(n)
    if not IsInGuild() then return end
    local data = self:Serialize(n)
    self.recent[n.id] = { digest = Hash(data), at = GetTime() }
    ns.WhenChatFree(function() ns.Comm:SendLarge("BRDN", data, "GUILD") end)
end

local function NewId()
    return string.format("%x%04x", Now(), math.random(0, 65535))
end

-- Neuen Zettel anheften. opts: cat, to, title, text, days, when, pinned
function Board:Post(opts)
    if not self:Open() then return false, "Die Pinnwand gibt es nur für Charaktere in der Gilde." end
    local me = ns.UnitFullName("player")
    local title = Clean(opts.title, TITLE_MAX)
    if title == "" then return false, "Bitte eine Überschrift eingeben." end
    local limit = self:AmOfficer() and OFFICER_OPEN or MAX_OPEN
    if CountOpen(me) >= limit then
        return false, "Du hast schon " .. limit .. " offene Zettel. Nimm erst einen ab oder hake ihn ab."
    end
    local now = Now()
    local days = math.max(1, math.min(MAX_DAYS, tonumber(opts.days) or 3))
    local expires = now + days * 86400
    local when = tonumber(opts.when)
    if when then
        if when < now - 3600 then return false, "Der Termin liegt in der Vergangenheit." end
        -- Aktionen laufen bis kurz nach dem Termin ab, höchstens aber MAX_DAYS
        expires = math.min(now + MAX_DAYS * 86400, when + 6 * 3600)
    end
    local n = {
        id = NewId(), author = me, created = now, updated = now, expires = expires,
        cat = self.CAT[opts.cat] and opts.cat or "info", to = opts.to or "all", when = when,
        pinned = opts.pinned and self:AmOfficer() or false, state = "offen", editedBy = "",
        keep = (opts.keep and self:AmOfficer()) or nil,
        title = title, text = Clean(Board.Pack(opts.text), TEXT_MAX, true), reacts = {}, replies = {},
    }
    DB().notes[n.id] = n
    DB().seen[n.id] = self:Digest(n)
    self:Broadcast(n)
    ns:Fire("BOARD_UPDATE")
    return true, n
end

local function Touch(n)
    n.updated = math.max(Now(), (n.updated or 0) + 1)
    n.editedBy = ns.UnitFullName("player")
end

function Board:CanManage(n)
    return self:IsMePerson(n.author) or self:AmOfficer()
end

function Board:SetState(id, state)
    local n = DB().notes[id]
    if not n or not self:CanManage(n) then return end
    n.state = state
    Touch(n)
    self:Broadcast(n)
    ns:Fire("BOARD_UPDATE")
end

-- Offiziere: Zettel dauerhaft auf der Webseite behalten (im Spiel läuft er trotzdem ab)
function Board:SetKeep(id, keep)
    local n = DB().notes[id]
    if not n or not self:AmOfficer() then return end
    n.keep = keep and true or nil
    Touch(n)
    self:Broadcast(n)
    ns:Fire("BOARD_UPDATE")
end

function Board:SetPinned(id, pinned)
    local n = DB().notes[id]
    if not n or not self:AmOfficer() then return end
    n.pinned = pinned and true or false
    Touch(n)
    self:Broadcast(n)
    ns:Fire("BOARD_UPDATE")
end

function Board:React(id)
    local n = DB().notes[id]
    if not n then return end
    local me = ns.UnitFullName("player")
    local key = ns.NameKey(me)
    local r = n.reacts[key]
    local v = (r and r.v == 1) and 0 or 1
    n.reacts[key] = { name = me, v = v, t = math.max(Now(), r and (r.t + 1) or 0) }
    self:Broadcast(n)
    DB().seen[id] = self:Digest(n)
    ns:Fire("BOARD_UPDATE")
end

function Board:HasReacted(n)
    for _, r in pairs(n.reacts) do
        if r.v == 1 and self:IsMine(r.name) then return true end
    end
    return false
end

function Board:Reactions(n)
    local list = {}
    for _, r in pairs(n.reacts) do
        if r.v == 1 then table.insert(list, r) end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    return list
end

function Board:Reply(id, text)
    local n = DB().notes[id]
    if not n then return false end
    text = Clean(Board.Pack(text), REPLY_MAX, true)
    if text == "" then return false end
    local count = 0
    for _ in pairs(n.replies) do count = count + 1 end
    if count >= MAX_REPLIES then
        ns.Print("Dieser Zettel hat schon " .. MAX_REPLIES .. " Antworten – mehr passen nicht drauf.")
        return false
    end
    local rid = NewId()
    n.replies[rid] = { author = ns.UnitFullName("player"), time = Now(), state = "", text = text }
    self:Broadcast(n)
    DB().seen[id] = self:Digest(n)
    ns:Fire("BOARD_UPDATE")
    return true
end

function Board:RemoveReply(id, rid)
    local n = DB().notes[id]
    local a = n and n.replies[rid]
    if not a or not (self:IsMine(a.author) or self:AmOfficer()) then return end
    a.state = "x"
    self:Broadcast(n)
    ns:Fire("BOARD_UPDATE")
end

function Board:Replies(n)
    local list = {}
    for rid, a in pairs(n.replies) do
        if a.state ~= "x" then
            a.rid = rid
            table.insert(list, a)
        end
    end
    table.sort(list, function(a, b) return a.time < b.time end)
    return list
end

-- Listen für die Oberfläche -----------------------------------------------------------
-- filter: nil = alle, "mine" = für mich, "own" = von mir, sonst eine Kategorie
function Board:List(filter)
    local list = {}
    for _, n in pairs(DB().notes) do
        if self:IsVisible(n) then
            local ok = true
            if filter == "mine" then ok = self:IsForMe(n) and not self:IsMePerson(n.author) and n.to ~= "all"
            elseif filter == "own" then ok = self:IsMePerson(n.author)
            elseif filter then ok = n.cat == filter end
            if ok then table.insert(list, n) end
        end
    end
    table.sort(list, function(a, b)
        if a.pinned ~= b.pinned then return a.pinned end
        local doneA, doneB = a.state == "erledigt", b.state == "erledigt"
        if doneA ~= doneB then return doneB end
        return a.created > b.created
    end)
    return list
end

-- Ungelesen: neue Zettel für mich – und bei eigenen oder persönlichen Zetteln jede Änderung
function Board:IsUnread(n)
    local seen = DB().seen[n.id]
    if not seen then return self:IsForMe(n) and not self:IsMePerson(n.author) end
    if self:IsMePerson(n.author) or self:IsPersonal(n) then return seen ~= self:Digest(n) end
    return false
end

function Board:UnreadCount()
    local count = 0
    for _, n in pairs(DB().notes) do
        if self:IsVisible(n) and self:IsUnread(n) then count = count + 1 end
    end
    return count
end

function Board:MarkSeen(n)
    DB().seen[n.id] = self:Digest(n)
end

function Board:MarkAllSeen()
    for _, n in pairs(DB().notes) do
        if self:IsVisible(n) then DB().seen[n.id] = self:Digest(n) end
    end
    ns:Fire("BOARD_UPDATE")
end

-- Hinweise im Chat ------------------------------------------------------------------------
local function Short(text, max)
    if #text <= max then return text end
    return (text:sub(1, max):gsub("[\192-\255][\128-\191]*$", "")) .. "…"
end

function Board:Notify(n, kind, extra)
    -- Zettel an dich und alles zu deinen Zetteln hat einen eigenen Schalter, Zettel an alle einen anderen
    local mine = kind ~= "neu" or self:IsPersonal(n)
    if not ns.Opt(mine and "chatBoardMine" or "chatBoard") then return end
    table.insert(self.pendingNotify, { n = n, kind = kind, extra = extra })
    if self.notifyQueued then return end
    self.notifyQueued = true
    C_Timer.After(5, function()
        Board.notifyQueued = false
        local items = Board.pendingNotify
        Board.pendingNotify = {}
        local fresh, personal = {}, false
        for _, it in ipairs(items) do
            if it.kind == "neu" then
                table.insert(fresh, it.n)
                if Board:IsPersonal(it.n) then personal = true end
            else
                ns.Print("|cfff3dc9aPinnwand:|r " .. it.extra .. ": „" .. Short(it.n.title, 40) .. "“ – /ea pinnwand")
            end
        end
        if #fresh == 1 then
            local n = fresh[1]
            ns.Print("|cfff3dc9aPinnwand:|r Neuer Zettel von " .. (ns.ShortName(n.author) or "?")
                .. (Board:IsPersonal(n) and " an dich" or (n.to ~= "all" and (" an " .. Board:ToLabel(n.to)) or ""))
                .. ": „" .. Short(n.title, 50) .. "“ – /ea pinnwand")
        elseif #fresh > 1 then
            ns.Print("|cfff3dc9aPinnwand:|r " .. #fresh .. " neue Zettel – /ea pinnwand")
        end
        if personal then ns.Sound(SOUNDKIT and SOUNDKIT.TELL_MESSAGE or 3081, "Master") end
    end)
end

-- Was hat sich für mich geändert? (neuer Zettel, Reaktion oder Antwort auf meinen Zettel)
local function CheckNews(before, after, sender)
    if Board:IsMePerson(after.author) then
        if not before then return end
        for key, r in pairs(after.reacts) do
            local old = before.reacts[key]
            if r.v == 1 and (not old or old.v ~= 1) and not Board:IsMine(r.name) then
                Board:Notify(after, "react", (ns.ShortName(r.name) or "?") .. " " .. Board.CAT[after.cat].reacted)
            end
        end
        for rid, a in pairs(after.replies) do
            if not before.replies[rid] and a.state ~= "x" and not Board:IsMine(a.author) then
                Board:Notify(after, "reply", (ns.ShortName(a.author) or "?") .. " hat geantwortet")
            end
        end
        return
    end
    if not Board:IsVisible(after) then return end
    if not before then
        -- Kurz nach dem Einloggen kommt gesammelt ein Hinweis (siehe unten), nicht einer pro Zettel
        if Board:IsForMe(after) and GetTime() > (Board.quietUntil or 0) then Board:Notify(after, "neu") end
        return
    end
    if Board:IsPersonal(after) then
        for rid, a in pairs(after.replies) do
            if not before.replies[rid] and a.state ~= "x" and not Board:IsMine(a.author) then
                Board:Notify(after, "reply", (ns.ShortName(a.author) or "?") .. " hat geantwortet")
            end
        end
    end
end

local function Copy(n)
    local c = {}
    for _, k in ipairs(BODY) do c[k] = n[k] end
    c.keep = n.keep
    c.reacts, c.replies = {}, {}
    for k, r in pairs(n.reacts) do c.reacts[k] = { name = r.name, v = r.v, t = r.t } end
    for k, a in pairs(n.replies) do c.replies[k] = { author = a.author, time = a.time, state = a.state, text = a.text } end
    return c
end

function Board:Receive(data, sender)
    -- Ohne Gildenliste lassen sich Rechte (Offizier?) nicht prüfen: kurz zurückstellen
    if #ns.Members.list == 0 then
        self.waiting = self.waiting or {}
        table.insert(self.waiting, { data, sender })
        return
    end
    -- Zettel einer anderen Gilde (Charakter desselben Accounts dort) mischen sich nicht darunter
    if not self:Open() then return end
    local n = self:Parse(data)
    if not n then return end
    local old = DB().notes[n.id]
    local before = old and Copy(old)
    local result = self:Merge(n, true)
    self.recent[n.id] = { digest = Hash(data), at = GetTime() }
    if result then
        CheckNews(before, DB().notes[n.id], sender)
        ns:Fire("BOARD_UPDATE")
    end
end

-- Abgleich ------------------------------------------------------------------------------
function Board:Inventory()
    local parts = {}
    local now = Now()
    for id, n in pairs(DB().notes) do
        if n.expires > now then table.insert(parts, id .. ":" .. self:Digest(n)) end
    end
    return table.concat(parts, ";")
end

function Board:RequestSync()
    if not self:Open() then return end -- nur in der Gilde, der die Pinnwand gehört
    local req = string.format("%x", math.random(0, 16777215))
    self.myRequest = req
    ns.WhenChatFree(function() ns.Comm:SendLarge("BRDQ", req .. "#" .. Board:Inventory(), "GUILD") end)
end

local function ParseInventory(s)
    local t = {}
    for id, digest in (s or ""):gmatch("([^:;]+):([^;]+)") do t[id] = digest end
    return t
end

function Board:AnswerRequest(sender, data)
    if not self:Open() then return end -- Zettel verlassen die Gilde nicht
    local req, inv = data:match("^([^#]*)#(.*)$")
    if not req then return end
    local theirs = ParseInventory(inv)
    local now = Now()
    local send, want = {}, {}
    for id, n in pairs(DB().notes) do
        if n.expires > now and theirs[id] ~= self:Digest(n) then table.insert(send, id) end
    end
    for id, digest in pairs(theirs) do
        local n = DB().notes[id]
        if not n or self:Digest(n) ~= digest then table.insert(want, id) end
    end
    if #send == 0 and #want == 0 then return end
    local asked = GetTime()
    -- Zufällig warten: Wer zuerst antwortet, meldet sich mit BRDA, die anderen lassen es
    C_Timer.After(1.5 + math.random() * 6, function()
        if Board.answered[req] then return end
        Board.answered[req] = true
        ns.Comm:Send("BRDA", req, "GUILD")
        for _, id in ipairs(send) do
            local n = DB().notes[id]
            local r = Board.recent[id]
            -- Seit der Anfrage schon von jemand anderem geschickt (gleicher Stand)? Dann nicht noch einmal.
            if n and not (r and r.at > asked and r.digest == Board:Digest(n)) then
                local payload = Board:Serialize(n)
                Board.recent[id] = { digest = Hash(payload), at = GetTime() }
                ns.WhenChatFree(function() ns.Comm:SendLarge("BRDN", payload, "GUILD") end)
            end
        end
        if #want > 0 then
            ns.WhenChatFree(function() ns.Comm:SendLarge("BRDW", table.concat(want, ";"), "WHISPER", sender) end)
        end
    end)
end

function Board:SendWanted(list)
    if not self:Open() then return end
    for id in (list or ""):gmatch("[^;]+") do
        local n = DB().notes[id]
        if n and n.expires > Now() then
            local r = self.recent[id]
            if not (r and GetTime() - r.at < 30 and r.digest == self:Digest(n)) then self:Broadcast(n) end
        end
    end
end

ns.Comm.handlers.BRDN = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if data then Board:Receive(data, sender) end
end

ns.Comm.handlers.BRDQ = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if data and #ns.Members.list > 0 and ns.Members:Find(sender) then Board:AnswerRequest(sender, data) end
end

ns:Listen("MEMBERS_UPDATE", function()
    if not Board.waiting or #ns.Members.list == 0 then return end
    local list = Board.waiting
    Board.waiting = nil
    for _, w in ipairs(list) do Board:Receive(w[1], w[2]) end
end)

ns.Comm.handlers.BRDA = function(_, parts)
    if parts[2] then Board.answered[parts[2]] = true end
end

ns.Comm.handlers.BRDW = function(sender, parts)
    local data = ns.Comm:Assemble(sender, parts)
    if data then Board:SendWanted(data) end
end

-- Webseite --------------------------------------------------------------------------------
-- Zettel an alle (keine persönlichen, keine Gruppen) als Text zum Einfügen auf der Webseite
function Board:ExportForWeb()
    local lines = { "EAPW1^" .. Now() .. "^" .. (ns.UnitFullName("player") or "") }
    local count = 0
    for _, n in ipairs(self:List()) do
        if n.to == "all" then
            count = count + 1
            table.insert(lines, table.concat({ "N", n.id, n.author, n.created, n.expires, n.cat, n.when or 0,
                n.pinned and 1 or 0, n.state, n.title, Encode(n.text), n.keep and 1 or 0 }, "^"))
            for _, r in ipairs(self:Reactions(n)) do
                table.insert(lines, table.concat({ "R", n.id, r.name }, "^"))
            end
            for _, a in ipairs(self:Replies(n)) do
                table.insert(lines, table.concat({ "A", n.id, a.author, a.time, Encode(a.text) }, "^"))
            end
        end
    end
    return table.concat(lines, "\n"), count
end

-- Aufräumen und Start -----------------------------------------------------------------------
function Board:Prune()
    local now = Now()
    for id, n in pairs(DB().notes) do
        if (n.expires or 0) <= now then
            DB().notes[id] = nil
            DB().seen[id] = nil
        end
    end
    for id in pairs(DB().seen) do
        if not DB().notes[id] then DB().seen[id] = nil end
    end
end

ns:Listen("INIT", function()
    Board:Prune()
    C_Timer.NewTicker(600, function()
        Board:Prune()
        ns:Fire("BOARD_UPDATE")
    end)
end)

ns:On("PLAYER_LOGIN", function()
    Board.quietUntil = GetTime() + 75
    C_Timer.After(25 + math.random() * 15, function() Board:RequestSync() end)
    -- Nach dem Abgleich: kurzer Hinweis auf ungelesene Zettel
    C_Timer.After(75, function()
        local n = Board:UnreadCount()
        if n > 0 then
            ns.Print("|cfff3dc9aPinnwand:|r " .. (n == 1 and "1 neuer Zettel" or (n .. " neue Zettel")) .. " – /ea pinnwand")
        end
    end)
end)
