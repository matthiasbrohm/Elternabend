-- Elternabend: Berufe und Rezepte der Gilde
--
-- Wer sein Berufsfenster öffnet, dessen gelernte Rezepte liest das Addon aus und
-- verteilt sie über den Gildenkanal. Jedes Addon speichert, was es empfängt – so
-- sieht man auch Rezepte von Mitgliedern, die gerade offline sind.
--
-- Übertragen werden nur Rezept-IDs (Zauber-IDs); die Namen kennt jeder Client selbst.
--   PROF2 (SendLarge)  Zeit # Charakter # Beruf:Stufe:Max:a,b,…~Beruf:…
--                      Rezepte sortiert als Abstand zur vorigen ID, zur Basis 36 (halb so lang)
--   PROF  (SendLarge)  wie PROF2, aber mit vollen IDs (Addon 4.1.0 und älter)
--   PROFQ              „Bitte schickt eure Berufe“ (z. B. nach dem ersten Einloggen)
local _, ns = ...

local Prof = { names = {}, answered = {}, asked = {} }
ns.Professions = Prof

local SEND_DELAY = 5          -- nach einer Änderung kurz warten, dann senden
local ANSWER_COOLDOWN = 600   -- jedem Fragenden höchstens alle 10 Minuten antworten

local function DB()
    return ns.db.professions
end

-- Sammelberufe interessieren niemanden als Hersteller: weder erfassen noch anzeigen
local HIDDEN = { "angeln", "kräuterkunde", "bergbau", "kürschner", "fishing", "herbalism", "mining", "skinning" }

function Prof.IsHidden(profName)
    local lower = ns.Lower(profName or "")
    for _, word in ipairs(HIDDEN) do
        if lower:find(word, 1, true) then return true end
    end
    return false
end

-- Ausgeblendete Berufe aus einem Charakter entfernen; true, wenn keiner übrig bleibt
local function StripHidden(char)
    for i = #char.profs, 1, -1 do
        if Prof.IsHidden(char.profs[i].name) then table.remove(char.profs, i) end
    end
    return #char.profs == 0
end

-- Rezeptname aus der Zauber-ID (zwischengespeichert)
function Prof:RecipeName(id)
    local name = self.names[id]
    if name then return name end
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(id)
    elseif GetSpellInfo then
        name = GetSpellInfo(id)
    end
    if name and not ns.IsSecret(name) then
        self.names[id] = name
        return name
    end
end

-- Eigene Berufe auslesen ------------------------------------------------------
local function CurrentProfessionInfo()
    if C_TradeSkillUI.GetBaseProfessionInfo then
        local info = C_TradeSkillUI.GetBaseProfessionInfo()
        if info and info.professionName and info.professionName ~= "" then
            return info.professionName, info.skillLevel, info.maxSkillLevel
        end
    end
    if C_TradeSkillUI.GetTradeSkillLine then
        local _, name, rank, max = C_TradeSkillUI.GetTradeSkillLine()
        return name, rank, max
    end
end

-- Nur das eigene Berufsfenster zählt, nicht ein verlinktes oder das der Gilde
local function IsOwnTradeSkill()
    if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return false end
    if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then return false end
    if C_TradeSkillUI.IsNPCCrafting and C_TradeSkillUI.IsNPCCrafting() then return false end
    return true
end

function Prof:ReadOpenWindow()
    if not C_TradeSkillUI or not C_TradeSkillUI.GetAllRecipeIDs or not IsOwnTradeSkill() then return end
    if C_TradeSkillUI.IsTradeSkillReady and not C_TradeSkillUI.IsTradeSkillReady() then return end
    local profName, level, max = CurrentProfessionInfo()
    if not profName or ns.IsSecret(profName) then return end

    local ids = {}
    for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
        local info = C_TradeSkillUI.GetRecipeInfo(id)
        if info and info.learned then
            table.insert(ids, id)
            if info.name then self.names[id] = info.name end
        end
    end
    if #ids == 0 then return end
    table.sort(ids)
    self:StoreOwn(profName, level, max, ids)
end

-- Stufen ohne Berufsfenster (z. B. Kochkunst); Sammelberufe fallen in StoreOwn raus
function Prof:ReadProfessionLevels()
    if not GetProfessions then return end
    for _, index in ipairs({ GetProfessions() }) do
        if index then
            local name, _, level, max = GetProfessionInfo(index)
            if name and not ns.IsSecret(name) then self:StoreOwn(name, level, max, nil) end
        end
    end
end

-- In den eigenen Eintrag übernehmen; ids = nil heißt: nur Stufe aktualisieren
function Prof:StoreOwn(profName, level, max, ids)
    if Prof.IsHidden(profName) then return end
    local name = ns.UnitFullName("player")
    local key = ns.NameKey(name)
    if not key then return end
    local char = DB()[key] or { name = name, profs = {} }
    char.name, char.mine = name, true
    local entry
    for _, p in ipairs(char.profs) do
        if p.name == profName then entry = p end
    end
    if not entry then
        entry = { name = profName, recipes = {} }
        table.insert(char.profs, entry)
    end
    local changed = entry.level ~= level or (ids and table.concat(ids, ",") ~= table.concat(entry.recipes, ","))
    entry.level, entry.max = level, max
    if ids then entry.recipes = ids end
    DB()[key] = char
    if changed then
        char.time = time()
        self:QueueSend()
        ns:Fire("PROF_UPDATE")
    end
end

-- Verteilen -------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function Base36(n)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local d = n % 36
        s = DIGITS:sub(d + 1, d + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end

-- Sortierte IDs als Abstände: 2330,2332,3170 → „1sq,2,na“
local function Pack(ids)
    local sorted, out, prev = {}, {}, 0
    for _, id in ipairs(ids or {}) do table.insert(sorted, id) end
    table.sort(sorted)
    for _, id in ipairs(sorted) do
        table.insert(out, Base36(id - prev))
        prev = id
    end
    return table.concat(out, ",")
end

local function Unpack(list)
    local ids, prev = {}, 0
    for d in list:gmatch("[%w]+") do
        local n = tonumber(d, 36)
        if n then
            prev = prev + n
            table.insert(ids, prev)
        end
    end
    return ids
end

function Prof:Serialize(char, compact)
    local parts = {}
    for _, p in ipairs(char.profs) do
        local list = compact and Pack(p.recipes) or table.concat(p.recipes or {}, ",")
        table.insert(parts, table.concat({ p.name, p.level or 0, p.max or 0, list }, ":"))
    end
    return (char.time or 0) .. "#" .. char.name .. "#" .. table.concat(parts, "~")
end

function Prof:Parse(data, compact)
    local stamp, name, rest = data:match("^(%d+)#([^#]+)#(.*)$")
    if not stamp then return nil end
    local char = { name = name, time = tonumber(stamp), profs = {} }
    for part in rest:gmatch("[^~]+") do
        local pname, level, max, list = part:match("^([^:]+):(%d*):(%d*):(.*)$")
        if pname then
            local ids
            if compact then
                ids = Unpack(list)
            else
                ids = {}
                for id in list:gmatch("%d+") do table.insert(ids, tonumber(id)) end
            end
            table.insert(char.profs, { name = pname, level = tonumber(level), max = tonumber(max), recipes = ids })
        end
    end
    return char
end

-- Eigene Charaktere dieses Accounts senden (deren Daten liegen accountweit vor).
-- Ohne all nur die, die sich seit dem letzten Senden geändert haben.
-- Mit target: alle per Flüstern an diesen einen Spieler (Antwort auf eine Anfrage).
function Prof:SendMine(all, target)
    if not IsInGuild() then return end
    for _, char in pairs(DB()) do
        if char.mine and #char.profs > 0 and (all or (char.sent or 0) < (char.time or 0)) then
            if not target then char.sent = char.time end
            ns.Comm:SendLarge("PROF2", self:Serialize(char, true), target and "WHISPER" or "GUILD", target)
        end
    end
end

-- Kennen wir schon Berufe von anderen?
function Prof:KnowsOthers()
    for _, char in pairs(DB()) do
        if not char.mine then return true end
    end
    return false
end

function Prof:QueueSend()
    if self.sendQueued then return end
    self.sendQueued = true
    C_Timer.After(SEND_DELAY, function()
        Prof.sendQueued = false
        Prof:SendMine()
    end)
end

-- Neu anfragen: alle Addons online schicken ihre Berufe per Flüstern zurück.
-- Die Anfrage geht über die Gilde und zusätzlich direkt an bekannte Addon-Nutzer,
-- falls der Server die eigenen Gildennachrichten nicht verteilt.
function Prof:RequestAll(silent)
    ns.Comm:Send("PROFQ", nil, "GUILD")
    ns.Comm:SendToSeen("PROFQ")
    if not silent then ns.Print("Berufe angefragt – die Antworten kommen in den nächsten Sekunden.") end
end

-- Erster Kontakt mit einem Addon-Nutzer aus der Gilde, dessen Berufe wir nicht kennen:
-- einmal direkt nachfragen
ns:Listen("ADDON_USER_SEEN", function(sender, key)
    if Prof.asked[key] or DB()[key] or not IsInGuild() then return end
    local m = ns.Members.byKey[key]
    if not m or not m.online then return end
    Prof.asked[key] = true
    C_Timer.After(3 + math.random() * 5, function() ns.Comm:Send("PROFQ", nil, "WHISPER", sender) end)
end)

local function Receive(sender, parts, compact)
    local data = ns.Comm:Assemble(sender, parts)
    if not data then
        ns:Fire("PROF_UPDATE") -- Fortschritt in der Übersicht zeigen
        return
    end
    local char = Prof:Parse(data, compact)
    if not char or StripHidden(char) then return end
    local key = ns.NameKey(char.name)
    local old = DB()[key]
    if old and old.mine then return end -- eigene Charaktere kennt man selbst am besten
    if old and (old.time or 0) >= (char.time or 0) then return end
    char.from = ns.ShortName(sender)
    DB()[key] = char
    ns:Fire("PROF_UPDATE")
end

ns.Comm.handlers.PROF = function(sender, parts) Receive(sender, parts, false) end
ns.Comm.handlers.PROF2 = function(sender, parts) Receive(sender, parts, true) end

-- Antwort per Flüstern an den Fragenden: Das kommt auch an, wenn der Server unsere
-- Gildennachrichten nicht verteilt
ns.Comm.handlers.PROFQ = function(sender)
    local key = ns.NameKey(sender)
    if not key then return end
    if Prof.answered[key] and GetTime() - Prof.answered[key] < ANSWER_COOLDOWN then return end
    Prof.answered[key] = GetTime()
    C_Timer.After(2 + math.random() * 8, function() Prof:SendMine(true, sender) end)
end

-- Suche -----------------------------------------------------------------------
-- Liefert { {recipe=Name, id=ID, char=…, key=…, prof=…}, … } für alle Treffer
function Prof:Search(text, limit)
    local filter = ns.Lower(strtrim(text or ""))
    local hits = {}
    if filter == "" then return hits end
    for key, char in pairs(DB()) do
        for _, p in ipairs(char.profs) do
            for _, id in ipairs(p.recipes or {}) do
                local name = self:RecipeName(id)
                if name and ns.Lower(name):find(filter, 1, true) then
                    table.insert(hits, { recipe = name, id = id, char = char.name, key = key, prof = p.name })
                end
            end
        end
    end
    table.sort(hits, function(a, b)
        if a.recipe ~= b.recipe then return a.recipe < b.recipe end
        return a.char < b.char
    end)
    if limit and #hits > limit then
        for i = #hits, limit + 1, -1 do hits[i] = nil end
    end
    return hits
end

function Prof:Count()
    local chars, recipes = 0, 0
    for _, char in pairs(DB()) do
        chars = chars + 1
        for _, p in ipairs(char.profs) do recipes = recipes + #(p.recipes or {}) end
    end
    return chars, recipes
end

-- Gespeicherte Daten aus älteren Versionen bereinigen
ns:Listen("INIT", function()
    for key, char in pairs(DB()) do
        if StripHidden(char) then DB()[key] = nil end
    end
end)

-- Events -------------------------------------------------------------------------
ns:On("TRADE_SKILL_SHOW", function() C_Timer.After(1, function() Prof:ReadOpenWindow() end) end)
ns:On("TRADE_SKILL_LIST_UPDATE", function() Prof:ReadOpenWindow() end)
ns:On("PLAYER_LOGIN", function()
    C_Timer.After(5, function() Prof:ReadProfessionLevels() end)
    -- Geänderte eigene Berufe melden, zeitlich gestreut; wer noch keine fremden
    -- Berufe kennt (frisch installiert), fragt die Gilde einmal danach
    C_Timer.After(20 + math.random() * 25, function()
        Prof:SendMine()
        if IsInGuild() and not Prof:KnowsOthers() then Prof:RequestAll(true) end
    end)
end)
ns:On("SKILL_LINES_CHANGED", function() Prof:ReadProfessionLevels() end)
