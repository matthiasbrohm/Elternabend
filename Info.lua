-- Elternabend: Infos zur Gilde und Begrüßung
--
-- Die festen Infos stehen hier und kommen mit jeder Addon-Version. Die Nachricht
-- des Tages kommt live aus dem Spiel (die Gildenleitung ändert sie wie gewohnt
-- im Gildenfenster).
local _, ns = ...

local Info = {}
ns.Info = Info

Info.GUILD = {
    name = "Elternabend",
    tagline = "Die familienfreundliche Gilde – Raids ab 21 Uhr, wenn die Kinder schlafen.",
    motto = "„Die Kinder schlafen. Die Helden erwachen.“",
    about = "Wir sind eine entspannte Gilde, gegründet von Eltern für Eltern. Allianz, ganz auf PvE: " ..
        "Dungeons, Raids und gemeinsames Vorankommen. Bei uns zählen Spaß, Zusammenhalt und ein " ..
        "freundlicher Umgangston – und ruft ein Kind, ist AFK völlig in Ordnung.",
    raidTimes = "Raids starten ab 21 Uhr – wenn im Kinderzimmer Ruhe ist.",
    raidHint = "Termine, Anmeldung und Soft-Reserves: Raidplaner auf der Webseite oder im Discord.",
    discord = "https://discord.gg/elternabend",
    website = "https://www.gilde-elternabend.de",
}

-- Gildennamen, bei denen die Begrüßung erscheint: WoW Forever und die Testgilde in Retail
Info.GUILD_NAMES = { ["Elternabend"] = true, ["Der Elternabend"] = true }

function Info:IsOurGuild()
    local guild = IsInGuild() and GetGuildInfo("player")
    return guild ~= nil and self.GUILD_NAMES[guild] == true
end

function Info:MOTD()
    local motd = IsInGuild() and GetGuildRosterMOTD() or ""
    if ns.IsSecret(motd) then return "" end
    return motd or ""
end

-- Begrüßung einmal pro Charakter: beim ersten Start und nach dem Gildenbeitritt
function Info:MaybeWelcome()
    if not self:IsOurGuild() then return end
    local key = ns.PlayerKey()
    local seen = ns.db.welcomeSeen
    if not key or seen[key] then return end
    seen[key] = true
    ns.UI:Show("start")
end

ns:On("PLAYER_LOGIN", function() C_Timer.After(6, function() Info:MaybeWelcome() end) end)
ns:On("PLAYER_GUILD_UPDATE", function() C_Timer.After(2, function() Info:MaybeWelcome() end) end)
ns:On("GUILD_MOTD", function() ns:Fire("INFO_UPDATE") end)
