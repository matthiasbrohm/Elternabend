-- Schlossknacken der Schurken steht bei den Berufen (Idee von cbz64)

test("Schlossknacken aus der Fertigkeitenliste landet bei den Berufen und wird verteilt", function()
    local w = login({ guild = "Elternabend", roster = { { name = "Anna Sturmwind", online = true } } })
    w.env.GetNumSkillLines = function() return 3 end
    w.env.GetSkillLineInfo = function(i)
        if i == 1 then return "Klassenfertigkeiten", true end
        if i == 2 then return "Schlossknacken", false, nil, 175, 0, 0, 300 end
        return "Einhandschwerter", false, nil, 120, 0, 0, 300
    end
    w:clear()
    w:fire("SKILL_LINES_CHANGED")
    w:advance(10)
    local char = w.ns.db.professions[w.ns.NameKey("Anna Sturmwind")]
    check(char, "nichts gespeichert")
    local found
    for _, p in ipairs(char.profs) do
        if p.name == "Schlossknacken" or p.name == "Lockpicking" then found = p end
        check(not p.name:find("Einhand"), "Waffenfertigkeit gespeichert")
    end
    check(found, "Schlossknacken fehlt")
    equal(found.level, 175)
    equal(found.max, 300)
    seen(w, "comm", "PROF2")
    noErrors(w)
end)
