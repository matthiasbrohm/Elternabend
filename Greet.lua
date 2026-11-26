local _, ns = ...

-- Gruß beim Einloggen, Abschied beim Ausloggen (beides im Gildenchat, standardmäßig aus)
--
-- Ausloggen dürfen Addons nicht selbst (Logout() und Quit() sind geschützt). Das Addon hängt sich deshalb
-- nur hinten an: Wer über das Spielmenü, /camp, /logout oder /quit geht, löst Logout()/Quit() aus – direkt
-- danach schreibt das Addon den Abschied, solange man noch online ist.
-- Gruß nur beim echten Einloggen, nicht nach /reload, und höchstens alle 30 Minuten je Account
-- (sonst grüßt man nach jedem Verbindungsabbruch neu).

local Greet = {}
ns.Greet = Greet

Greet.DEFAULT_HELLO = "Hallo zusammen!"
Greet.DEFAULT_BYE = "Ich bin dann mal weg – bis bald!"

local HELLO_DELAY = 15        -- Sekunden nach dem Einloggen: Gildenchat ist bereit, die Gilde sieht einen online
local HELLO_REPEAT = 30 * 60  -- nicht öfter grüßen
local BYE_REPEAT = 120        -- Spielmenü und /camp lösen beide aus: nur einmal schreiben

local function S() return ns.db.settings end

function Greet:HelloText()
    local t = strtrim(S().helloText or "")
    return t ~= "" and t or self.DEFAULT_HELLO
end

function Greet:ByeText()
    local t = strtrim(S().byeText or "")
    return t ~= "" and t or self.DEFAULT_BYE
end

local function InOurGuild()
    return IsInGuild() and ns.Info:IsOurGuild()
end

function Greet:Hello()
    if not S().hello or not InOurGuild() then return end
    if time() - (ns.db.helloAt or 0) < HELLO_REPEAT then return end
    ns.db.helloAt = time()
    ns.SendChat(self:HelloText(), "GUILD")
end

-- Direkt senden, nicht in die Warteschlange: gleich ist man offline
function Greet:Bye()
    if not S().bye or not InOurGuild() or ns.ChatLocked() then return end
    local now = GetTime()
    if self.byeAt and now - self.byeAt < BYE_REPEAT then return end
    self.byeAt = now
    pcall(C_ChatInfo.SendChatMessage, self:ByeText(), "GUILD")
end

ns:On("PLAYER_ENTERING_WORLD", function(isInitialLogin)
    if not isInitialLogin then return end
    C_Timer.After(HELLO_DELAY, function() Greet:Hello() end)
end)

if hooksecurefunc then
    if Logout then hooksecurefunc("Logout", function() Greet:Bye() end) end
    if Quit then hooksecurefunc("Quit", function() Greet:Bye() end) end
end
pcall(ns.On, ns, "PLAYER_CAMPING", function() Greet:Bye() end)
pcall(ns.On, ns, "PLAYER_QUITING", function() Greet:Bye() end)
