-- Elternabend: Gruppensuchen aus Discord und Dungeonfinder als Hinweis im Reiter „Gruppen“
--
-- Ein Addon kann nicht ins Internet. Die Mac-App „Elternabend Abgleich“ holt die offenen Suchen von
-- gilde-elternabend.de und schreibt sie in Abgleich.lua (Feld „gruppen“). Das Addon dieses Rechners
-- liest sie beim Einloggen oder nach /reload und gibt sie über den Addon-Kanal an die Gilde weiter –
-- so sehen alle mit Addon, was im Discord gesucht wird, auch ohne App.
--   Format: #ELTERNABEND-GRUPPEN;1;<Stand>
--           gruppe;ID;Dungeon;Start;Dauer;Ersteller;freie Tanks;freie Heiler;freie DDs;Hinweis;Quelle
--   LFGWEB  Stand ID Dungeon Start Dauer Ersteller Tank Heiler DD Hinweis Quelle   (Gilde; Antwort auf LFGQ per Flüstern)
-- Es ist ein Schnappschuss: Stand ist der letzte Abgleich der App. Melden geht nur im Discord oder auf der
-- Webseite. Suchen verschwinden 30 Minuten nach dem Start oder wenn der Schnappschuss älter als 6 Stunden ist.
local _, ns = ...

local WG = { list = {} }
ns.WebGroups = WG

local LATE = 30 * 60      -- so lange nach dem Start stehen Suchen noch da
local OLD = 6 * 3600      -- ältere Schnappschüsse zählen nicht mehr

local function Clean(s, max)
    s = tostring(s or ""):gsub("[\t\r\n|;]", " ")
    s = s:gsub("[\240-\244][\128-\191][\128-\191][\128-\191]", "") -- Emojis aus Discord-Namen: kennt die Schrift des Spiels nicht
    s = strtrim(s)
    if max and #s > max then s = s:sub(1, max):gsub("[\192-\255][\128-\191]*$", "") end
    return s
end

-- Text der Webseite lesen: Stand und Liste
function WG.Parse(text)
    if type(text) ~= "string" then return nil end
    local snap = tonumber(text:match("^#ELTERNABEND%-GRUPPEN;%d+;(%d+)"))
    if not snap then return nil end
    local list = {}
    for line in text:gmatch("[^\n]+") do
        local f = {}
        for field in (line .. ";"):gmatch("([^;]*);") do f[#f + 1] = field end
        if f[1] == "gruppe" and f[2] ~= "" and tonumber(f[4]) then
            list[#list + 1] = { id = Clean(f[2], 20), what = Clean(f[3], 40), start = tonumber(f[4]), duration = tonumber(f[5]) or 0,
                by = Clean(f[6], 40), need = { tank = tonumber(f[7]) or 0, heal = tonumber(f[8]) or 0, dd = tonumber(f[9]) or 0 },
                note = Clean(f[10], 80), source = f[11] == "web" and "web" or "discord" }
        end
    end
    return snap, list
end

function WG:Store(e, snap)
    local old = self.list[e.id]
    if old and (old.snap or 0) > snap then return false end
    e.snap = snap
    self.list[e.id] = e
    return true
end

-- Noch aktuelle Suchen, nach Startzeit
function WG:Active()
    local now, out = time(), {}
    for id, e in pairs(self.list) do
        if e.start < now - LATE or now - (e.snap or 0) > OLD then
            self.list[id] = nil
        else
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b) return a.start < b.start end)
    return out
end

-- „heute 20:00“, „morgen 19:30“, „läuft seit 10 Min.“
function WG.When(e)
    local now = time()
    if e.start <= now then
        local mins = math.floor((now - e.start) / 60)
        return mins < 1 and "jetzt" or ("läuft seit " .. mins .. " Min.")
    end
    local day = date("%Y%m%d", e.start)
    local label = day == date("%Y%m%d", now) and "heute" or (day == date("%Y%m%d", now + 86400) and "morgen" or date("%d.%m.", e.start))
    return label .. " " .. date("%H:%M", e.start)
end

-- Aus der Datei der Mac-App (nur auf dem Rechner mit der App)
function WG:Load()
    local d = ElternabendAbgleich
    if type(d) ~= "table" then return end
    local snap, list = WG.Parse(d.gruppen)
    if not snap or time() - snap > OLD then return end
    self.own = { snap = snap, list = list }
    for _, e in ipairs(list) do self:Store(e, snap) end
    ns:Fire("GROUPS_UPDATE")
end

-- Den eigenen Schnappschuss an die Gilde (oder an einen, der gerade eingeloggt hat) weitergeben
function WG:Share(channel, target)
    if not self.own or not ns.Info:AtHome() then return end
    for _, e in ipairs(self.own.list) do
        if e.start >= time() - LATE then
            ns.Comm:Send("LFGWEB", table.concat({ self.own.snap, e.id, e.what, e.start, e.duration, e.by,
                e.need.tank, e.need.heal, e.need.dd, e.note, e.source }, "\t"), channel or "GUILD", target, true)
        end
    end
end

ns.Comm.handlers.LFGWEB = function(sender, parts)
    if not ns.Members:Find(sender) then return end
    local snap, start = tonumber(parts[2]), tonumber(parts[5])
    if not snap or not start or not parts[3] or parts[3] == "" or time() - snap > OLD then return end
    local e = { id = Clean(parts[3], 20), what = Clean(parts[4], 40), start = start, duration = tonumber(parts[6]) or 0,
        by = Clean(parts[7], 40), need = { tank = tonumber(parts[8]) or 0, heal = tonumber(parts[9]) or 0, dd = tonumber(parts[10]) or 0 },
        note = Clean(parts[11], 80), source = parts[12] == "web" and "web" or "discord" }
    if WG:Store(e, snap) then ns:Fire("GROUPS_UPDATE") end
end

-- Wer neu einloggt, fragt mit LFGQ nach offenen Suchen: dann auch den Schnappschuss schicken
local previous = ns.Comm.handlers.LFGQ
ns.Comm.handlers.LFGQ = function(sender, parts)
    if previous then previous(sender, parts) end
    if WG.own then C_Timer.After(2 + math.random() * 4, function() WG:Share("WHISPER", sender) end) end
end

ns:Listen("INIT", function()
    WG:Load()
    if WG.own then C_Timer.After(25 + math.random() * 10, function() WG:Share() end) end
end)
