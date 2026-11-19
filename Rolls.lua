-- Elternabend: Würfelfenster – wer bei Bedarf/Gier was gewählt und gewürfelt hat
--
-- Statt der vielen Zeilen im Chat ein eigenes, verschiebbares Fenster: je Gegenstand, wer Bedarf,
-- Gier oder Passen gewählt hat, die Würfe, wer gewonnen hat und auf wen noch gewartet wird.
-- Standardmäßig aus (Einstellungen → „Würfelfenster“). Öffnen und schließen mit /ea loot,
-- /ea würfe oder einer eigenen Taste (Tastenbelegung → Elternabend).
--
-- Gelesen werden die Beute-Zeilen des Chats (CHAT_MSG_LOOT). Die Muster kommen aus den Texten des
-- Spiels selbst (LOOT_ROLL_NEED & Co.) – so klappt es in jeder Sprache. Zusätzlich meldet
-- START_LOOT_ROLL den Beginn einer Runde mit Laufzeit, falls das Spiel es schickt.
local _, ns = ...
local T = ns.Theme

local Rolls = { rounds = {} }
ns.Rolls = Rolls

BINDING_NAME_ELTERNABEND_WUERFE = "Würfelfenster öffnen / schließen"

local KEEP = 40            -- so viele Runden bleiben gespeichert
local STALE = 3 * 60       -- nach so vielen Sekunden ohne Ende gilt eine Runde als vorbei
local CHOICES = { need = 1, greed = 2, de = 3, pass = 4 }

-- Muster aus den Texten des Spiels ---------------------------------------------------------
-- Jeder Text hat Platzhalter in fester Reihenfolge (z. B. „%s hat 'Bedarf' für: %s ausgewählt“).
-- Übersetzungen dürfen sie umstellen („%2$s … %1$s“) – deshalb merkt sich das Muster, welcher
-- Fund zu welchem Platzhalter gehört.
local SPECS = {
    { "LOOT_ROLL_NEED", "need", { "who", "item" } },
    { "LOOT_ROLL_GREED", "greed", { "who", "item" } },
    { "LOOT_ROLL_DISENCHANT", "de", { "who", "item" } },
    { "LOOT_ROLL_PASSED", "pass", { "who", "item" } },
    { "LOOT_ROLL_PASSED_AUTO", "pass", { "who", "item" } },
    { "LOOT_ROLL_PASSED_AUTO_FEMALE", "pass", { "who", "item" } },
    { "LOOT_ROLL_NEED_SELF", "need", { "item" }, true },
    { "LOOT_ROLL_GREED_SELF", "greed", { "item" }, true },
    { "LOOT_ROLL_DISENCHANT_SELF", "de", { "item" }, true },
    { "LOOT_ROLL_PASSED_SELF", "pass", { "item" }, true },
    { "LOOT_ROLL_PASSED_SELF_AUTO", "pass", { "item" }, true },
    { "LOOT_ROLL_ROLLED_NEED", "rollneed", { "roll", "item", "who" } },
    { "LOOT_ROLL_ROLLED_GREED", "rollgreed", { "roll", "item", "who" } },
    { "LOOT_ROLL_ROLLED_DE", "rollde", { "roll", "item", "who" } },
    { "LOOT_ROLL_WON", "won", { "who", "item" } },
    { "LOOT_ROLL_YOU_WON", "won", { "item" }, true },
    { "LOOT_ROLL_ALL_PASSED", "allpass", { "item" } },
}

-- „%s hat … %d …“ -> Lua-Muster mit Fängen, Liste, welcher Fang welcher Platzhalter ist,
-- und die Art jedes Platzhalters (s/d) sowie ihre Zahl
function Rolls.Compile(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local pattern, order, kinds, n, pos, most = "^", {}, {}, 0, 1, 0
    while true do
        local s, e, index, kind = fmt:find("%%(%d*)%$?([sd])", pos)
        if not s then break end
        local literal = fmt:sub(pos, s - 1):gsub("%%%%", "%%"):gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        pattern = pattern .. literal .. (kind == "d" and "(%d+)" or "(.-)")
        n = n + 1
        local arg = tonumber(index) or n
        order[#order + 1] = arg
        kinds[arg] = kind
        most = math.max(most, arg)
        pos = e + 1
    end
    if n == 0 then return nil end
    local tail = fmt:sub(pos):gsub("%%%%", "%%"):gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    return pattern .. tail .. "$", order, kinds, most
end

-- Neuere Spielversionen setzen vor jede Zeile einen Link auf den Beuteverlauf:
-- „|HlootHistory:%d|h[Beute]|h: %s hat Bedarf gewählt …“. Dieser erste Platzhalter ist dann die
-- Nummer der Runde – praktisch, denn sie hält auch zwei gleiche Gegenstände auseinander.
local compiled, byName
local function Patterns()
    if compiled then return compiled, byName end
    compiled, byName = {}, {}
    for _, spec in ipairs(SPECS) do
        local fmt = _G[spec[1]]
        local pattern, order, kinds, most = Rolls.Compile(fmt)
        if pattern then
            local args = spec[3]
            local shift = most == #args + 1 and kinds[1] == "d"
            local names = {}
            for arg = 1, most do
                if shift then names[arg] = arg == 1 and "history" or args[arg - 1] else names[arg] = args[arg] end
            end
            local p = { pattern = pattern, order = order, names = names, shift = shift, kind = spec[2], self = spec[4],
                -- längere (genauere) Texte zuerst: „… automatisch gepasst …“ vor „… gepasst …“
                weight = #fmt }
            table.insert(compiled, p)
            byName[spec[1]] = p
        end
    end
    table.sort(compiled, function(a, b) return a.weight > b.weight end)
    return compiled, byName
end

-- Eine Chatzeile lesen: { kind = …, who = …, item = …, roll = … } oder nil
function Rolls.Parse(msg)
    if type(msg) ~= "string" or ns.IsSecret(msg) then return nil end
    for _, p in ipairs(Patterns()) do
        local found = { msg:match(p.pattern) }
        if #found > 0 then
            local r = { kind = p.kind }
            for i, value in ipairs(found) do
                local name = p.names[p.order[i]]
                if name then r[name] = value end
            end
            if p.self then r.who = ns.UnitFullName("player") end
            if r.item and (not r.who or r.who ~= "") then
                r.roll = tonumber(r.roll)
                r.history = tonumber(r.history)
                return r
            end
        end
    end
end

-- Runden ------------------------------------------------------------------------------------
local function DB()
    ns.db.rolls = ns.db.rolls or { rounds = {} }
    return ns.db.rolls
end

function Rolls:Enabled()
    return ns.db and ns.db.settings.rollWindow == true
end

-- Derselbe Gegenstand, auch wenn sich Farbe oder Text des Links unterscheiden
local function ItemKey(link)
    return link and (link:match("|H(item:[^|]+)|h") or link:match("item:[%-%d:]+") or link)
end

local function Open(round)
    return not round.done and (time() - round.t) < STALE
end

local function NewRound(link, history)
    local list = DB().rounds
    local round = { t = time(), link = link, key = ItemKey(link), history = history, choices = {} }
    table.insert(list, 1, round)
    while #list > KEEP do table.remove(list) end
    return round
end

-- Älteste passende offene Runde (die Liste ist neueste zuerst). Mit Rundennummer zählt nur die
-- Runde mit derselben Nummer (oder eine ohne – die bekommt sie dann).
local function Find(link, accept, history)
    local key, list = ItemKey(link), DB().rounds
    for i = #list, 1, -1 do
        local round = list[i]
        if round.key == key and Open(round) and (not history or not round.history or round.history == history)
            and (not accept or accept(round)) then
            if history then round.history = history end
            return round
        end
    end
end

local function Choice(round, who)
    for _, c in ipairs(round.choices) do
        if ns.SameName(c.name, who) then return c end
    end
end

function Rolls:Handle(r)
    if not r then return end
    local h = r.history
    if r.kind == "need" or r.kind == "greed" or r.kind == "de" or r.kind == "pass" then
        -- zwei gleiche Gegenstände zugleich: wer schon gewählt hat, gehört zur nächsten Runde
        local round = Find(r.item, function(x) return not Choice(x, r.who) end, h) or NewRound(r.item, h)
        table.insert(round.choices, { name = r.who, choice = r.kind })
    elseif r.kind == "rollneed" or r.kind == "rollgreed" or r.kind == "rollde" then
        local want = r.kind:sub(5)
        local round = Find(r.item, function(x)
            local c = Choice(x, r.who)
            return c and c.choice == want and not c.roll
        end, h) or Find(r.item, nil, h) or NewRound(r.item, h)
        local c = Choice(round, r.who)
        if not c then
            c = { name = r.who, choice = want }
            table.insert(round.choices, c)
        end
        c.roll = r.roll
    elseif r.kind == "won" then
        local round = Find(r.item, function(x) return Choice(x, r.who) ~= nil end, h) or Find(r.item, nil, h)
            or NewRound(r.item, h)
        round.winner = r.who
        round.done = true
    elseif r.kind == "allpass" then
        local round = Find(r.item, nil, h) or NewRound(r.item, h)
        round.allPassed = true
        round.done = true
    end
    ns:Fire("ROLLS_UPDATE")
end

-- Beginn einer Runde (mit Laufzeit), sofern das Spiel ihn meldet
function Rolls:Start(rollID, rollTime)
    local ok, link = pcall(GetLootRollItemLink, rollID)
    if not ok or type(link) ~= "string" or ns.IsSecret(link) then return end
    local round = Find(link, function(x) return x.rollID == nil and #x.choices == 0 end) or NewRound(link)
    round.rollID = rollID
    if tonumber(rollTime) then round.ends = time() + math.ceil(rollTime / 1000) end
    ns:Fire("ROLLS_UPDATE")
end

function Rolls:List() return DB().rounds end

-- Probelauf ohne Gruppe (/ea würfe test): baut Beispielzeilen mit den Texten des eigenen Spiels und
-- schickt sie durch dasselbe Lesen wie echte Chatzeilen. Was nicht erkannt wird, meldet der Chat.
function Rolls:Demo()
    local me = ns.UnitFullName("player") or "Du"
    local function Link(id, color, fallback)
        local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local ok, _, link = pcall(info, id)
        if ok and type(link) == "string" then return link end
        return "|c" .. color .. "|Hitem:" .. id .. "::::::::|h[" .. fallback .. "]|h|r"
    end
    local a, b, c = Link(14047, "ffffffff", "Runenstoff"), Link(4306, "ffffffff", "Seidenstoff"), Link(2589, "ffffffff", "Leinenstoff")
    local lines = {
        { "LOOT_ROLL_NEED", "Probe Anna", a }, { "LOOT_ROLL_GREED", "Probe Bert", a }, { "LOOT_ROLL_NEED_SELF", a },
        { "LOOT_ROLL_PASSED", "Probe Cora", a },
        { "LOOT_ROLL_ROLLED_NEED", 42, a, "Probe Anna" }, { "LOOT_ROLL_ROLLED_NEED", 87, a, me },
        { "LOOT_ROLL_ROLLED_GREED", 99, a, "Probe Bert" }, { "LOOT_ROLL_YOU_WON", a },
        { "LOOT_ROLL_PASSED", "Probe Anna", b }, { "LOOT_ROLL_PASSED_SELF", b }, { "LOOT_ROLL_ALL_PASSED", b },
        { "LOOT_ROLL_GREED", "Probe Bert", c }, { "LOOT_ROLL_GREED_SELF", c },
    }
    local history = { [a] = 101, [b] = 102, [c] = 103 }
    local _, specs = Patterns()
    local missing, first = {}, nil
    for _, l in ipairs(lines) do
        local fmt, p = _G[l[1]], specs[l[1]]
        local args = { select(2, unpack(l)) }
        if p and p.shift then
            local item
            for i = 2, #l do if history[l[i]] then item = l[i] end end
            table.insert(args, 1, history[item] or 100)
        end
        local ok, msg = pcall(string.format, type(fmt) == "string" and fmt or "", unpack(args))
        local r = ok and Rolls.Parse(msg)
        if r then
            self:Handle(r)
        else
            missing[#missing + 1] = l[1]
            first = first or (type(fmt) == "string" and fmt:gsub("|", "||") or tostring(fmt))
        end
    end
    -- die letzte Runde läuft noch eine halbe Minute
    local round = Find(c)
    if round then round.ends = time() + 30 end
    ns:Fire("ROLLS_UPDATE")
    if #missing > 0 then
        ns.Print("Würfelfenster: Diese Texte des Spiels wurden nicht erkannt: " .. table.concat(missing, ", ")
            .. ". Der erste lautet: " .. tostring(first))
    else
        ns.Print("Würfelfenster: Probelauf mit drei Beispiel-Gegenständen. „Leeren“ räumt sie wieder weg.")
    end
end

function Rolls:Clear()
    DB().rounds = {}
    ns:Fire("ROLLS_UPDATE")
end

-- Wer in der Gruppe hat für diese Runde noch nichts gewählt?
function Rolls:Waiting(round)
    if not Open(round) or round.allPassed then return {} end
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        units = { "player", "party1", "party2", "party3", "party4" }
    end
    local waiting = {}
    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            local name = ns.UnitFullName(unit)
            if name and not ns.IsSecret(name) and not Choice(round, name) then waiting[#waiting + 1] = name end
        end
    end
    return waiting
end

-- Gewählt und gewürfelt: Bedarf vor Gier vor Passen, jeweils höchster Wurf zuerst
function Rolls.Sorted(round)
    local list = {}
    for _, c in ipairs(round.choices) do list[#list + 1] = c end
    table.sort(list, function(a, b)
        local ca, cb = CHOICES[a.choice] or 9, CHOICES[b.choice] or 9
        if ca ~= cb then return ca < cb end
        if (a.roll or -1) ~= (b.roll or -1) then return (a.roll or -1) > (b.roll or -1) end
        return (a.name or "") < (b.name or "")
    end)
    return list
end

ns:On("CHAT_MSG_LOOT", function(msg)
    if Rolls:Enabled() then Rolls:Handle(Rolls.Parse(msg)) end
end)
pcall(ns.On, ns, "START_LOOT_ROLL", function(rollID, rollTime)
    if Rolls:Enabled() then Rolls:Start(rollID, rollTime) end
end)

-- Fenster -----------------------------------------------------------------------------------
local WIDTH, HEIGHT = 380, 420             -- Startgröße
local MIN_W, MIN_H, MAX_W, MAX_H = 320, 220, 900, 1100 -- am Griff unten rechts in diesen Grenzen veränderbar
local CHOICE_TEXT = { need = "Bedarf", greed = "Gier", de = "Entzaubern", pass = "Passe" }
local CHOICE_COLOR = { need = "red", greed = "green", de = "orange", pass = "dim" }

-- Stern als Bild: Zeichen wie ★ oder → hat die Schrift des Spiels nicht (dann erscheint ein Kästchen)
local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:13:13:0:0|t"

-- Symbol eines Gegenstands – je nach Spielversion heißt die Abfrage anders
function Rolls.ItemIcon(link)
    local id = tonumber(link and link:match("item:(%d+)"))
    if not id then return nil end
    local tries = {
        function() return C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id) end,
        function() return GetItemIcon and GetItemIcon(id) end,
        function() return C_Item and C_Item.GetItemInfoInstant and select(5, C_Item.GetItemInfoInstant(id)) end,
        function() return GetItemInfoInstant and select(5, GetItemInfoInstant(id)) end,
    }
    for _, try in ipairs(tries) do
        local ok, icon = pcall(try)
        if ok and (type(icon) == "number" or type(icon) == "string") and not ns.IsSecret(icon) then return icon end
    end
end

local function ClassHexFor(name)
    local units = IsInRaid() and GetNumGroupMembers() or 5
    for i = 1, units do
        local unit = IsInRaid() and ("raid" .. i) or (i == 1 and "player" or ("party" .. (i - 1)))
        if UnitExists(unit) and ns.SameName(ns.UnitFullName(unit), name) then
            local _, class = UnitClass(unit)
            local col = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if col and col.colorStr then return col.colorStr end
        end
    end
    local m = ns.Members and ns.Members:Find(name)
    local col = m and m.classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[m.classFile]
    return col and col.colorStr or T.hex.cream
end

local function Create()
    local f = CreateFrame("Frame", "ElternabendRolls", UIParent, "BackdropTemplate")
    local size = ns.db.settings.rollWindowSize
    if type(size) == "table" and tonumber(size[1]) and tonumber(size[2]) then
        f:SetSize(math.min(MAX_W, math.max(MIN_W, size[1])), math.min(MAX_H, math.max(MIN_H, size[2])))
    else
        f:SetSize(WIDTH, HEIGHT)
    end
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif f.SetMinResize then f:SetMinResize(MIN_W, MIN_H) f:SetMaxResize(MAX_W, MAX_H) end
    f:SetFrameStrata("MEDIUM")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint(1)
        ns.db.settings.rollWindowPos = { point, rel, x, y }
    end)
    T.Backdrop(f, T.colors.navy, 0.95, 0.7)
    tinsert(UISpecialFrames, "ElternabendRolls") -- Esc schließt
    local pos = ns.db.settings.rollWindowPos
    if type(pos) == "table" and pos[1] then
        f:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3] or 0, pos[4] or 0)
    else
        f:SetPoint("RIGHT", UIParent, "RIGHT", -260, 40)
    end

    local kicker = T.Text(f, "kicker")
    kicker:SetPoint("TOPLEFT", 14, -12)
    kicker:SetText("ELTERNABEND")
    local title = T.Text(f, "heading")
    title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -4)
    title:SetText("Würfe")

    local close = T.Button(f, "X", 26)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() f:Hide() end)
    local clear = T.Button(f, "Leeren", 70)
    clear:SetHeight(22)
    clear:SetPoint("RIGHT", close, "LEFT", -6, 0)
    clear:SetScript("OnClick", function() Rolls:Clear() end)

    local sf = T.Scroll(f)
    sf:SetPoint("TOPLEFT", 14, -50)
    sf:SetPoint("BOTTOMRIGHT", -8, 18)
    sf.content:SetWidth(f:GetWidth() - 32)

    -- Griff unten rechts: Fenster größer oder kleiner ziehen; Größe und Platz werden gemerkt
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        ns.db.settings.rollWindowSize = { math.floor(f:GetWidth() + 0.5), math.floor(f:GetHeight() + 0.5) }
        local point, _, rel, x, y = f:GetPoint(1)
        ns.db.settings.rollWindowPos = { point, rel, x, y }
    end)
    f.grip = grip
    f:SetScript("OnSizeChanged", function(self)
        if self:IsShown() and self.Refresh then self:Refresh() end
    end)
    f.scroll = sf
    f.lines = {}
    f.heads = {}

    f.empty = T.Text(sf.content, "muted")
    f.empty:SetPoint("TOPLEFT", 0, -4)
    f.empty:SetWidth(f:GetWidth() - 40)
    f.empty:SetJustifyH("LEFT")
    f.empty:SetText("Noch keine Würfe. Sobald in deiner Gruppe um Beute gewürfelt wird, steht hier, "
        .. "wer Bedarf, Gier oder Passen gewählt hat – und wer gewinnt.")

    -- Kopfzeile je Gegenstand: Symbol und Link (Maus drüber zeigt den Gegenstand), rechts der Stand
    local function Head(i)
        local h = f.heads[i]
        if h then return h end
        h = CreateFrame("Button", nil, sf.content)
        h:SetHeight(20)
        h.icon = h:CreateTexture(nil, "ARTWORK")
        h.icon:SetSize(18, 18)
        h.icon:SetPoint("LEFT")
        h.name = T.Text(h, "body")
        h.name:SetPoint("LEFT", h.icon, "RIGHT", 6, 0)
        h.name:SetPoint("RIGHT", -110, 0)
        h.name:SetWordWrap(false)
        h.state = T.Text(h, "small", "RIGHT")
        h.state:SetPoint("RIGHT", -4, 0)
        h.state:SetWidth(108)
        h:SetScript("OnEnter", function(self)
            if not self.link then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
            GameTooltip:Show()
        end)
        h:SetScript("OnLeave", GameTooltip_Hide)
        f.heads[i] = h
        return h
    end
    -- Zeile je Spieler: Name, Wahl, Wurf
    local function Line(i)
        local l = f.lines[i]
        if l then return l end
        l = CreateFrame("Frame", nil, sf.content)
        l:SetHeight(16)
        l.name = T.Text(l, "small")
        l.name:SetPoint("LEFT", 24, 0)
        l.name:SetWordWrap(false)
        l.choice = T.Text(l, "small")
        l.roll = T.Text(l, "small", "RIGHT")
        l.roll:SetPoint("RIGHT", -6, 0)
        l.roll:SetWidth(40)
        f.lines[i] = l
        return l
    end

    function f:Refresh()
        for _, h in ipairs(self.heads) do h:Hide() end
        for _, l in ipairs(self.lines) do l:Hide() end
        local rounds = Rolls:List()
        -- Breiten aus der aktuellen Fenstergröße: Name links, Wahl und Wurf rechtsbündig dahinter
        local inner = math.max(200, self:GetWidth() - 32)
        local choiceX = inner - 136
        self.empty:SetWidth(inner - 8)
        self.empty:SetShown(#rounds == 0)
        local y, hi, li = 0, 0, 0
        for _, round in ipairs(rounds) do
            hi = hi + 1
            local h = Head(hi)
            h:SetWidth(inner)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, -y)
            h.link = round.link
            h.icon:SetTexture(Rolls.ItemIcon(round.link) or 134400)
            h.name:SetText(round.link or "?")
            local open = not round.done and (time() - round.t) < STALE
            if round.winner then
                h.state:SetText(STAR .. " " .. T.Hex("green", ns.ShortName(round.winner) or round.winner))
            elseif round.allPassed then
                h.state:SetText(T.Hex("muted", "alle gepasst"))
            elseif open then
                local left = round.ends and (round.ends - time()) or nil
                h.state:SetText(T.Hex("goldBright", left and left > 0 and ("läuft · " .. left .. " s") or "läuft"))
            else
                h.state:SetText(T.Hex("dim", "vorbei"))
            end
            h:Show()
            y = y + 22
            for _, c in ipairs(Rolls.Sorted(round)) do
                li = li + 1
                local l = Line(li)
                l:SetWidth(inner)
                l.choice:ClearAllPoints()
                l.choice:SetPoint("LEFT", choiceX, 0)
                l:ClearAllPoints()
                l:SetPoint("TOPLEFT", 0, -y)
                local winner = round.winner and ns.SameName(round.winner, c.name)
                l.name:SetWidth(choiceX - 30)
                l.name:SetText((winner and (STAR .. " ") or "") .. "|c" .. ClassHexFor(c.name)
                    .. (ns.ShortName(c.name) or c.name or "?") .. "|r")
                l.choice:SetText(T.Hex(CHOICE_COLOR[c.choice] or "cream", CHOICE_TEXT[c.choice] or c.choice))
                l.roll:SetText(c.roll and (winner and T.Hex("goldBright", c.roll) or tostring(c.roll)) or "")
                l:Show()
                y = y + 16
            end
            local waiting = Rolls:Waiting(round)
            if #waiting > 0 then
                li = li + 1
                local l = Line(li)
                l:SetWidth(inner)
                l:ClearAllPoints()
                l:SetPoint("TOPLEFT", 0, -y)
                local names = {}
                for _, n in ipairs(waiting) do names[#names + 1] = ns.ShortName(n) or n end
                l.name:SetWidth(inner - 28)
                l.name:SetText(T.Hex("muted", "Wartet noch: " .. table.concat(names, ", ")))
                l.choice:SetText("")
                l.roll:SetText("")
                l:Show()
                y = y + 16
            end
            y = y + 10
        end
        sf.content:SetHeight(math.max(1, y))
        sf.UpdateThumb()
    end

    -- Restzeit der laufenden Runden mitzählen
    f.elapsed = 0
    f:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed < 1 then return end
        self.elapsed = 0
        for _, round in ipairs(Rolls:List()) do
            if not round.done and round.ends and round.ends >= time() - 1 then self:Refresh() return end
        end
    end)
    f:SetScript("OnShow", function(self) self:Refresh() end)
    f:Hide()
    return f
end

function Rolls:Show()
    if not self:Enabled() then
        ns.Print("Das Würfelfenster ist aus. Einschalten: Einstellungen » „Würfelfenster“ (oder /ea einstellungen).")
        return
    end
    self.frame = self.frame or Create()
    self.frame:Show()
    self.frame:Refresh()
end

function Rolls:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
    else
        self:Show()
    end
end

ns:Listen("ROLLS_UPDATE", function()
    if Rolls.frame and Rolls.frame:IsShown() then Rolls.frame:Refresh() end
end)
