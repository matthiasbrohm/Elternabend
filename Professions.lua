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

-- Berufsnamen kommen in der Sprache des Spielers, der sie schickt („Blacksmithing“ aus
-- einem englischen Client). Für Anzeige, Filter und Suche immer in die eigene Sprache übersetzen.
local PROF_NAMES = {
    { de = "Alchimie", en = "Alchemy" },
    { de = "Schmiedekunst", en = "Blacksmithing" },
    { de = "Verzauberkunst", en = "Enchanting" },
    { de = "Ingenieurskunst", en = "Engineering" },
    { de = "Lederverarbeitung", en = "Leatherworking" },
    { de = "Schneiderei", en = "Tailoring" },
    { de = "Juwelierskunst", en = "Jewelcrafting" },
    { de = "Inschriftenkunde", en = "Inscription" },
    { de = "Kochkunst", en = "Cooking" },
    { de = "Erste Hilfe", en = "First Aid" },
    { de = "Archäologie", en = "Archaeology" },
}
local localNames
function Prof.LocalName(profName)
    if not profName then return profName end
    if not localNames then
        local field = (GetLocale and GetLocale() == "deDE") and "de" or "en"
        localNames = {}
        for _, n in ipairs(PROF_NAMES) do
            for _, v in pairs(n) do localNames[ns.Lower(v)] = n[field] end
        end
    end
    return localNames[ns.Lower(profName)] or profName
end

-- Namen übersetzen und doppelte Einträge zusammenführen (das mit mehr Rezepten bleibt)
local function Normalize(char)
    local list, byName = {}, {}
    for _, p in ipairs(char.profs) do
        p.name = Prof.LocalName(p.name)
        local o = byName[p.name]
        if not o then
            byName[p.name] = p
            table.insert(list, p)
        else
            local np, no = #(p.recipes or {}), #(o.recipes or {})
            if np > no or (np == no and (p.level or 0) > (o.level or 0)) then
                for k in pairs(o) do o[k] = nil end
                for k, v in pairs(p) do o[k] = v end
            end
        end
    end
    char.profs = list
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
    if not ns.Info:AtHome() then return end -- Berufe bleiben in der Gilde
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
    if not ns.Info:AtHome() then return end
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
    if not ns.Info:AtHome() then return end -- Charakter in einer anderen Gilde: deren Berufe mischen sich nicht darunter
    local data = ns.Comm:Assemble(sender, parts)
    if not data then
        ns:Fire("PROF_UPDATE") -- Fortschritt in der Übersicht zeigen
        return
    end
    local char = Prof:Parse(data, compact)
    if not char or StripHidden(char) then return end
    Normalize(char)
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

-- Export für die Webseite (gilde-elternabend.de/berufe.php → „Aus dem Addon importieren“)
-- Eine Zeile ohne „|“ (das ist in Eingabefeldern ein Steuerzeichen). Teile mit „^“ getrennt:
--   EAB2^Zeit^Exporteur^Anzahl
--   C~Name~Beruf~Stufe~Max~Stand~Rezept-ID,Rezept-ID,…             (ein Beruf eines Charakters)
--   R~Rezept-ID~Name~Gegenstand~Menge~Item*Anzahl,Item*Anzahl~Text   (was das Rezept braucht und ergibt)
--   I~Item-ID~Qualität~Name~Farbe¦Links¦Rechts`Farbe¦Links¦Rechts     (Werte wie im Tooltip)
local BAR = "\194\166" -- ¦
local function Clean(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|n", " "):gsub("|", "")
    s = s:gsub("[%^~`]", " "):gsub(BAR, " "):gsub("%s+", " ")
    return (s:gsub("^ ", ""):gsub(" $", ""))
end

local function GetItemInfoCompat(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return end
    local ok, name, _, quality = pcall(f, id)
    if ok and name and not ns.IsSecret(name) then return name, quality end
end

local function IsCached(id)
    if C_Item and C_Item.IsItemDataCachedByID then return C_Item.IsItemDataCachedByID(id) end
    return GetItemInfoCompat(id) ~= nil
end

local function RequestItem(id)
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) else GetItemInfoCompat(id) end
end

-- Was ein Rezept braucht und ergibt (aus den Spieldaten, klappt auch für fremde Rezepte)
local function Schematic(id)
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then return nil end
    local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
    if not ok or type(sch) ~= "table" then return nil end
    local out = { item = sch.outputItemID, qty = sch.quantityMin or 1, reagents = {} }
    for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
        local r = slot.reagents and slot.reagents[1]
        local basic = slot.required or slot.reagentType == nil or slot.reagentType == 1
        if r and r.itemID and basic then table.insert(out.reagents, { r.itemID, slot.quantityRequired or 1 }) end
    end
    return out
end

-- Für die Anzeige im Addon (zwischengespeichert)
local schematicCache = {}
function Prof:Schematic(id)
    if schematicCache[id] == nil then schematicCache[id] = Schematic(id) or false end
    return schematicCache[id] or nil
end

-- Farbcode der Qualität des hergestellten Gegenstands (oder nil)
function Prof:RecipeColor(id)
    local sch = self:Schematic(id)
    if not sch or not sch.item then return nil end
    local _, quality = GetItemInfoCompat(sch.item)
    if not quality then RequestItem(sch.item) return nil end
    local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return c and c.hex or nil
end

-- Rüstungsplatz ----------------------------------------------------------------
-- Wohin gehört, was ein Rezept herstellt (Kopf, Brust, Waffe …)? Für Filter und Sortierung im Berufe-Reiter.
Prof.SLOTS = {
    { key = "kopf", label = "Kopf", types = { "INVTYPE_HEAD" } },
    { key = "hals", label = "Hals", types = { "INVTYPE_NECK" } },
    { key = "schultern", label = "Schultern", types = { "INVTYPE_SHOULDER" } },
    { key = "ruecken", label = "Rücken", types = { "INVTYPE_CLOAK" } },
    { key = "brust", label = "Brust", types = { "INVTYPE_CHEST", "INVTYPE_ROBE" } },
    { key = "hemd", label = "Hemd", types = { "INVTYPE_BODY" } },
    { key = "handgelenke", label = "Handgelenke", types = { "INVTYPE_WRIST" } },
    { key = "haende", label = "Hände", types = { "INVTYPE_HAND" } },
    { key = "taille", label = "Taille", types = { "INVTYPE_WAIST" } },
    { key = "beine", label = "Beine", types = { "INVTYPE_LEGS" } },
    { key = "fuesse", label = "Füße", types = { "INVTYPE_FEET" } },
    { key = "finger", label = "Finger", types = { "INVTYPE_FINGER" } },
    { key = "schmuck", label = "Schmuck", types = { "INVTYPE_TRINKET" } },
    { key = "waffe", label = "Waffe", types = { "INVTYPE_WEAPON", "INVTYPE_2HWEAPON", "INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND" } },
    { key = "schildhand", label = "Schildhand", types = { "INVTYPE_SHIELD", "INVTYPE_HOLDABLE" } },
    { key = "distanz", label = "Distanz", types = { "INVTYPE_RANGED", "INVTYPE_RANGEDRIGHT", "INVTYPE_THROWN" } },
    { key = "munition", label = "Munition", types = { "INVTYPE_AMMO" } },
    { key = "tasche", label = "Tasche", types = { "INVTYPE_BAG", "INVTYPE_QUIVER" } },
}
local SLOT_BY_TYPE = {}
Prof.SLOT_BY_KEY = {}
for i, slot in ipairs(Prof.SLOTS) do
    slot.order = i
    Prof.SLOT_BY_KEY[slot.key] = slot
    for _, t in ipairs(slot.types) do SLOT_BY_TYPE[t] = slot end
end

-- Liefert den Platz (Eintrag aus Prof.SLOTS) und – bei Rüstung und Waffen – die Art („Leder“, „Dolch“ …).
-- nil für alles, was man nicht anlegt (Tränke, Materialien, Verzauberungen …).
local slotCache = {}
function Prof:RecipeSlot(id)
    local c = slotCache[id]
    if c == nil then
        c = false
        local sch = self:Schematic(id)
        local info = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if sch and sch.item and info then
            local ok, _, _, subType, equipLoc, _, classID, subClassID = pcall(info, sch.item)
            local slot = ok and type(equipLoc) == "string" and SLOT_BY_TYPE[equipLoc] or nil
            if slot then
                -- Art nur, wo sie etwas sagt: Stoff/Leder/Schwere Rüstung/Platte und Waffenarten
                local armor = classID == 4 and type(subClassID) == "number" and subClassID >= 1 and subClassID <= 4
                    and equipLoc ~= "INVTYPE_CLOAK"
                local kind = (armor or classID == 2) and type(subType) == "string" and subType ~= "" and subType or nil
                c = { slot = slot, kind = kind }
            end
        end
        slotCache[id] = c
    end
    if c then return c.slot, c.kind end
end

-- Sonderrezept? Liefert die Gegenstands-ID des Rezepts (Muster, Pläne …) oder nil,
-- wenn man es beim Lehrer lernt.
function Prof:SpecialItem(id)
    return ns.SpecialRecipes and ns.SpecialRecipes[tonumber(id)] or nil
end

-- Kleines Rezept-Symbol vor Sonderrezepten
Prof.SPECIAL_ICON = "|TInterface\\Icons\\INV_Scroll_03:14:14:0:0:64:64:5:59:5:59|t "

function Prof:ItemName(id)
    local name = GetItemInfoCompat(id)
    if not name then RequestItem(id) end
    return name
end

local scanTip
local function ItemLines(itemID)
    local lines = {}
    local function Add(hex, left, right)
        if ns.IsSecret(left) or ns.IsSecret(right) then return end
        left, right = Clean(left), Clean(right)
        if left == "" and right == "" then return end
        if left:find("^Verkaufspreis") or left:find("^Sell Price") then return end
        if #lines < 24 then table.insert(lines, hex .. BAR .. left .. BAR .. right) end
    end
    local function Hex(r, g, b) return string.format("%02x%02x%02x", (r or 1) * 255, (g or 1) * 255, (b or 1) * 255) end
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
        if ok and type(data) == "table" and data.lines then
            for i, l in ipairs(data.lines) do
                if i > 1 then
                    local c = l.leftColor
                    Add(c and Hex(c.r, c.g, c.b) or "ffffff", l.leftText, l.rightText)
                end
            end
            return lines
        end
    end
    -- Ältere Clients: verstecktes Tooltip auslesen
    scanTip = scanTip or CreateFrame("GameTooltip", "ElternabendScanTooltip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    local ok = pcall(scanTip.SetItemByID, scanTip, itemID)
    if ok then
        for i = 2, scanTip:NumLines() do
            local L, R = _G["ElternabendScanTooltipTextLeft" .. i], _G["ElternabendScanTooltipTextRight" .. i]
            Add(Hex(L:GetTextColor()), L:GetText(), (R and R:IsShown()) and R:GetText() or "")
        end
    end
    scanTip:Hide()
    return lines
end

local function SpellText(id)
    if C_Spell and C_Spell.GetSpellDescription then
        local ok, d = pcall(C_Spell.GetSpellDescription, id)
        if ok and d and not ns.IsSecret(d) then return Clean(d) end
    elseif GetSpellDescription then
        local ok, d = pcall(GetSpellDescription, id)
        if ok and d then return Clean(d) end
    end
    return ""
end

-- only: erlaubte Schlüssel (z. B. aktuelle Gildenmitglieder) oder nil für alle.
-- Lädt zuerst die nötigen Gegenstandsdaten (bis zu 12 Sekunden) und ruft dann done(text, anzahl) auf;
-- progress(geladen, gesamt) meldet den Zwischenstand.
function Prof:PrepareExport(only, progress, done)
    local chars, recipeIDs, seen = {}, {}, {}
    for key, char in pairs(DB()) do
        if not only or only[key] then
            for _, p in ipairs(char.profs) do
                table.insert(chars, { char = char, prof = p })
                for _, id in ipairs(p.recipes or {}) do
                    if not seen[id] then seen[id] = true; table.insert(recipeIDs, id) end
                end
            end
        end
    end
    local schematics, itemIDs, needItem, isOutput = {}, {}, {}, {}
    for _, id in ipairs(recipeIDs) do
        local sch = Schematic(id)
        schematics[id] = sch
        if sch then
            if sch.item then isOutput[sch.item] = true end
            if sch.item and not needItem[sch.item] then needItem[sch.item] = true; table.insert(itemIDs, sch.item) end
            for _, r in ipairs(sch.reagents) do
                if not needItem[r[1]] then needItem[r[1]] = true; table.insert(itemIDs, r[1]) end
            end
        end
    end
    for _, id in ipairs(itemIDs) do if not IsCached(id) then RequestItem(id) end end

    local function Build()
        local parts = {}
        table.sort(chars, function(a, b)
            if a.char.name ~= b.char.name then return a.char.name < b.char.name end
            return (a.prof.name or "") < (b.prof.name or "")
        end)
        for _, e in ipairs(chars) do
            local p = e.prof
            table.insert(parts, table.concat({ "C", Clean(ns.ShortName(e.char.name) or e.char.name), Clean(p.name), p.level or 0, p.max or 0,
                e.char.time or 0, table.concat(p.recipes or {}, ",") }, "~"))
        end
        for _, id in ipairs(recipeIDs) do
            local sch = schematics[id]
            local reag = {}
            if sch then for _, r in ipairs(sch.reagents) do table.insert(reag, r[1] .. "*" .. r[2]) end end
            local item = sch and sch.item or 0
            table.insert(parts, table.concat({ "R", id, Clean(self:RecipeName(id) or ""), item, sch and sch.qty or 1,
                table.concat(reag, ","), (item == 0) and SpellText(id) or "" }, "~"))
        end
        for _, id in ipairs(itemIDs) do
            local name, quality = GetItemInfoCompat(id)
            if name then
                -- Werte nur für hergestellte Gegenstände, bei Materialien reicht der Name
                local lines = isOutput[id] and table.concat(ItemLines(id), "`") or ""
                table.insert(parts, table.concat({ "I", id, quality or 1, Clean(name), lines }, "~"))
            end
        end
        local head = table.concat({ "EAB2", time(), Clean(ns.ShortName(ns.UnitFullName("player")) or "?"), #chars }, "^")
        done(head .. (#parts > 0 and ("^" .. table.concat(parts, "^")) or ""), #chars)
    end

    local waited = 0
    local function Check()
        local ready = 0
        for _, id in ipairs(itemIDs) do if IsCached(id) then ready = ready + 1 end end
        if progress then progress(ready, #itemIDs) end
        if ready >= #itemIDs or waited >= 12 or not C_Timer then Build() return end
        waited = waited + 0.5
        C_Timer.After(0.5, Check)
    end
    Check()
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
        if StripHidden(char) then DB()[key] = nil else Normalize(char) end
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
