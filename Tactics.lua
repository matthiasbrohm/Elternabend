-- Elternabend Raid: Taktikbilder
--
-- Die Bilder liegen als TGA im Ordner Taktik/ und stehen in Taktik.lua; beides
-- erzeugt Taktik-Werkstatt/taktik-bilder.py. Ein Addon kann keine Bilder aus dem
-- Internet laden oder verschicken: „Dem Raid zeigen“ sendet deshalb nur die ID,
-- und jeder öffnet das Bild aus seinem eigenen Addon-Ordner.
local ADDON, ns = ...

local Tactics = {}
ns.Tactics = Tactics

function Tactics:All()
    return ns.TACTICS or {}
end

function Tactics:Get(id)
    for _, t in ipairs(self:All()) do
        if t.id == id then return t end
    end
end

function Tactics:Path(t)
    return "Interface\\AddOns\\" .. ADDON .. "\\" .. t.file
end

-- Bild so groß wie möglich in den Rahmen einpassen, Seitenverhältnis bleibt
function Tactics:Fit(texture, t, maxWidth, maxHeight)
    local scale = math.min(maxWidth / t.width, maxHeight / t.height)
    texture:SetTexture(self:Path(t))
    texture:SetTexCoord(0, t.width / t.texWidth, 0, t.height / t.texHeight)
    texture:SetSize(t.width * scale, t.height * scale)
end

function Tactics:ShowToRaid(t)
    if not IsInGroup() then
        ns.Print("Du bist in keiner Gruppe.")
        return
    end
    if not ns.IsTrusted(ns.UnitFullName("player")) then
        ns.Print("Nur Leitung und Assistenten können dem Raid eine Taktik zeigen.")
        return
    end
    ns.Comm:Send("TAKTIK", t.id)
    ns.Print("Taktik „" .. t.boss .. "“ wird allen mit Addon gezeigt.")
end

ns.Comm.handlers.TAKTIK = function(sender, parts)
    if not ns.IsTrusted(sender) then return end
    local t = Tactics:Get(parts[2])
    if not t then
        ns.Print(ns.ShortName(sender) .. " zeigt eine Taktik, die deine Addon-Version noch nicht kennt – bitte das Addon aktualisieren.")
        return
    end
    ns.UI:ShowTactic(t, ns.ShortName(sender))
end
