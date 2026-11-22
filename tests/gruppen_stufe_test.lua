-- Offene Gruppen: empfohlene Stufe direkt hinter bekannten Dungeons

test("Offene Gruppen: Dungeon zeigt die empfohlene Stufe, grün wenn sie passt, freie Gesuche ohne", function()
    local w = login({ guild = "Elternabend", roster = { { name = "Beta Lux", online = true, class = "PALADIN" },
        { name = "Greta Glutherz", online = true, class = "PRIEST" } } })
    w.env.UnitLevel = function() return 15 end
    w:advance(40)
    w:receive("LFG\tg1\tHalle der Thanen\t1\t1\t0\t\t0\t0", "GUILD", "Beta Lux")
    w:receive("LFG\tg2\tTiefschwarze Grotte\t1\t1\t2\tbitte mit Erfahrung\t0\t0", "GUILD", "Greta Glutherz")
    w:receive("LFG\tg3\tHogger\t0\t0\t2\t\t0\t0", "GUILD", "Greta Glutherz")
    w.ns.UI:Show("gruppen")
    local p = w.ns.UI.panels.gruppen
    w:call(p.Refresh, p)
    local texts = {}
    for _, row in ipairs(p.list.rows) do
        if row:IsShown() then texts[row.data.what] = row.cols.what:GetText() end
    end
    local thanen, grotte, hogger = texts["Halle der Thanen"], texts["Tiefschwarze Grotte"], texts["Hogger"]
    check(thanen and thanen:find("13–18", 1, true), tostring(thanen))
    -- passt (Stufe 15) → andere Farbe als die nicht passende Grotte
    local c1, c2 = thanen:match("|c(%x+)13–18"), grotte:match("|c(%x+)24–32")
    check(c1 and c2 and c1 ~= c2, tostring(c1) .. " / " .. tostring(c2))
    check(grotte:find("24–32", 1, true) and grotte:find("bitte mit Erfahrung", 1, true), grotte)
    check(grotte:find("24–32", 1, true) < grotte:find("bitte mit Erfahrung", 1, true), "Stufe nicht vor der Notiz")
    check(not hogger:find("%d+–%d+"), hogger)
    noErrors(w)
end)
