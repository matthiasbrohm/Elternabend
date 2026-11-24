-- Begrüßung neuer Gildenmitglieder: viele Texte, keine doppelten

test("Begrüßung: lange Texte enthalten Discord, Vorstellungsrunde und Addon-Tipp, passen in den Chat", function()
    local w = login({ guild = "Elternabend" })
    local W = w.ns.Welcome
    check(#W.LONG >= 5, "zu wenige lange Texte")
    for _, t in ipairs(W.LONG) do
        local text = t:format("Brunhilde Blutaxt")
        check(text:lower():find("discord", 1, true), "ohne discord: " .. text)
        check(text:find("#vorstellungsrunde", 1, true), "ohne Vorstellungsrunde: " .. text)
        check(text:find("Elternabend", 1, true), "ohne Addon/Gildenname: " .. text)
        check(#text <= 255, "zu lang (" .. #text .. "): " .. text)
    end
    -- sehr langer Name: notfalls nur der Vorname
    for _ = 1, 20 do
        check(#W.LongText("Abcdefghijklmnopqrstuvwx Abcdefghijklmnopqrstuvwx") <= 255, "langer Name passt nicht")
    end
    noErrors(w)
end)

test("Begrüßung: kurze Texte – viele, ohne „discord“ und nie doppelt, wenn genug frei sind", function()
    local w = login({ guild = "Elternabend" })
    local W = w.ns.Welcome
    check(#W.SHORT >= 15, "zu wenige kurze Texte")
    for _, t in ipairs(W.SHORT) do
        check(not t:lower():find("discord", 1, true), "kurzer Text mit discord: " .. t)
        check(select(2, t:gsub("%%s", "")) == 1, "Name fehlt: " .. t)
    end
    -- Alle bis auf einen standen schon im Chat: dann kommt genau der übrige
    local seen = {}
    for i = 2, #W.SHORT do seen[w.ns.Lower(W.SHORT[i]:format("Beta Lux"))] = true end
    for _ = 1, 10 do equal(W.ShortText("Beta Lux", seen), W.SHORT[1]:format("Beta Lux")) end
    -- unterschiedliche Texte über viele Begrüßungen
    local verschieden = {}
    for _ = 1, 200 do verschieden[W.ShortText("Beta Lux")] = true end
    local n = 0
    for _ in pairs(verschieden) do n = n + 1 end
    check(n >= 10, "zu wenig Abwechslung: " .. n)
    noErrors(w)
end)
