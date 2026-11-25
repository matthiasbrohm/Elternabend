-- Begrüßung neuer Gildenmitglieder: mehrere Texte, einer schreibt

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
