-- Schlossknacken der Schurken steht bei den Berufen (Idee von cbz64)

test("Schlossknacken aus der Fertigkeitenliste landet bei den Berufen und wird verteilt", function()
    local w = login({ guild = "Elternabend", roster = { { name = "Anna Sturmwind", online = true } } })
    w.env.C_SkillInfo = false -- älterer Client: nur GetSkillLineInfo
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

test("Schlossknacken in WoW Forever (C_SkillInfo)", function()
    local w = login({ guild = "Elternabend", roster = { { name = "Anna Sturmwind", online = true } } })
    w.env.C_SkillInfo = {
        GetSkillLineInfoByID = function(id)
            if id == 633 then return { skillID = 633, name = "Schlossknacken", isHeader = false, rank = 210, maxRank = 300 } end
        end,
    }
    w:fire("SKILL_LINES_CHANGED")
    w:advance(10)
    local char = w.ns.db.professions[w.ns.NameKey("Anna Sturmwind")]
    local found
    for _, p in ipairs(char and char.profs or {}) do
        if p.name == "Schlossknacken" or p.name == "Lockpicking" then found = p end
    end
    check(found, "Schlossknacken fehlt")
    equal(found.level, 210)
    noErrors(w)
end)

test("Schlossknacken: Nicht-Schurken bekommen keinen Eintrag", function()
    local w = login({ guild = "Elternabend", roster = { { name = "Anna Sturmwind", online = true } } })
    w.env.C_SkillInfo = { GetSkillLineInfoByID = function() return nil end, GetNumSkillLines = function() return 0 end,
        GetSkillLineInfo = function() return nil end }
    w:fire("SKILL_LINES_CHANGED")
    w:advance(10)
    local char = w.ns.db.professions[w.ns.NameKey("Anna Sturmwind")]
    for _, p in ipairs(char and char.profs or {}) do check(p.name ~= "Schlossknacken", "Eintrag ohne Fertigkeit") end
    noErrors(w)
end)
