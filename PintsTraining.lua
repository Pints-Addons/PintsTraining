-- Pint's Training: a tab on the spellbook listing what your class trainer can teach you - available now,
-- coming soon, not yet - with costs, plus which weapon masters teach the weapon skills you're missing.  /ptrain
local ADDON = ...
-- Compatibility: WoW Forever runs on the modern game client, where these older functions moved or were renamed.
local IsAddOnLoaded = IsAddOnLoaded or (C_AddOns and C_AddOns.IsAddOnLoaded)
local GetSpellTexture = GetSpellTexture or (C_Spell and C_Spell.GetSpellTexture)
local GetSpellLink = GetSpellLink or (C_Spell and C_Spell.GetSpellLink)
local IsSpellKnown = IsSpellKnown or (C_SpellBook and C_SpellBook.IsSpellKnown)
local GetSpellInfo = GetSpellInfo or function(s)
	local i = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(s)
	if i then return i.name, nil, i.iconID, i.castTime, i.minRange, i.maxRange, i.spellID, i.originalIconID end
end

local PT = {}
_G.PintsTraining = PT
local DATA = PintsTrainingData or {}

local DEFAULTS = { showKnown = false, soon = 2, levelUpNote = true, minimap = {} }
local db, cdb
local function Print(m) print("|cffd4a017Pint's Training:|r " .. m) end
local function Money(v)
	v = v or 0
	local g, s, c = math.floor(v / 10000), math.floor(v / 100) % 100, v % 100
	local out = ""
	if g > 0 then out = out .. g .. "|cffffd700g|r " end
	if s > 0 then out = out .. s .. "|cffc7c7cfs|r " end
	if c > 0 or out == "" then out = out .. c .. "|cffeda55fc|r" end
	return (out:gsub("%s+$", ""))
end

---------------------------------------------------------------- what's trainable
local function Known(id) return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) or false end
-- names for trainer spells the game itself no longer has (WoW Forever took them out or made them a spec's own)
local NAMES = { [1535] = "Fire Nova Totem", [8498] = "Fire Nova Totem", [8499] = "Fire Nova Totem", [11314] = "Fire Nova Totem", [11315] = "Fire Nova Totem" }
local function GameName(id)
	if C_Spell and C_Spell.GetSpellName then local ok, n = pcall(C_Spell.GetSpellName, id); if ok and n then return n end end
	local ok, n = pcall(GetSpellInfo, id)
	return ok and n or nil
end
local function SpellName(id)
	return GameName(id) or NAMES[id] or ("spell " .. id)
end
local function SpellIcon(id)
	if C_Spell and C_Spell.GetSpellTexture then local t = C_Spell.GetSpellTexture(id); if t then return t end end
	return GetSpellTexture and GetSpellTexture(id)
end
local SECTIONS = {
	{ key = "now", title = "Available Now", color = "|cff20ff20" },
	{ key = "soon", title = "Coming Soon", color = "|cff66bbff" },
	{ key = "later", title = "Not Yet Available", color = "|cffff3030" },
	{ key = "ignored", title = "Ignored", color = "|cff888888" },
	{ key = "known", title = "Already Known", color = "|cff888888" },
}
-- everything for this character, sorted into sections
-- what your class trainer actually teaches in this version of the game (read when you talk to one - see ReadTrainer)
local function TrainerKey()
	local _, class = UnitClass("player")
	return class .. ":" .. (UnitFactionGroup("player") or "?")
end
local function TrainerList()
	local t = db and db.trainer and db.trainer[TrainerKey()]
	return t and t.spells and #t.spells > 0 and t or nil
end
PT.TrainerList = TrainerList
function PT.Collect()
	local _, class = UnitClass("player")
	local list = DATA[class] or {}
	-- seen at a trainer: that list is the real one (WoW Forever took some spells out, and moved others to new levels)
	local tl = TrainerList()
	if tl then
		local req = {}
		for _, e in ipairs(list) do req[e[1]] = e[4] end
		local real = {}
		for _, sp in ipairs(tl.spells) do real[#real + 1] = { sp.id, sp.level or 1, sp.cost or 0, req[sp.id] or 0, 0, sp.rank or 0, name = sp.name } end
		list = real
	end
	local level = UnitLevel("player")
	local myFaction = UnitFactionGroup("player") == "Horde" and 2 or 1
	local out = { now = {}, soon = {}, later = {}, unavail = {}, ignored = {}, known = {} }
	for _, e in ipairs(list) do
		local id, lvl, cost, req, fac, rank = e[1], e[2], e[3], e[4], e[5], e[6]
		if (fac == 0 or fac == myFaction) and (req == 0 or Known(req)) then
			local item = { id = id, level = lvl, cost = cost, rank = rank, name = e.name and (GameName(id) or e.name) or nil }
			if Known(id) then table.insert(out.known, item)
			-- (the game doesn't have this spell at all: a trainer can't teach it to you - left off the list)
			elseif not GameName(id) and not item.name then
				-- (not shown)
			elseif cdb.ignored[id] then table.insert(out.ignored, item)
			elseif lvl <= level then table.insert(out.now, item)
			elseif lvl <= level + db.soon then table.insert(out.soon, item)
			else table.insert(out.later, item) end
		end
	end
	return out
end
function PT.AvailableNow()
	local s = PT.Collect()
	local cost = 0
	for _, i in ipairs(s.now) do cost = cost + i.cost end
	return #s.now, cost
end

---------------------------------------------------------------- weapon skills
local WEAPONS = {   -- skill spell -> name
	[196] = "One-Handed Axes", [197] = "Two-Handed Axes", [198] = "One-Handed Maces", [199] = "Two-Handed Maces", [200] = "Polearms",
	[201] = "One-Handed Swords", [202] = "Two-Handed Swords", [227] = "Staves", [264] = "Bows", [266] = "Guns", [1180] = "Daggers",
	[2567] = "Thrown", [5011] = "Crossbows", [15590] = "Fist Weapons",
}
local CAN_USE = {
	WARRIOR = { 196, 197, 198, 199, 200, 201, 202, 227, 264, 266, 1180, 2567, 5011, 15590 },
	PALADIN = { 196, 197, 198, 199, 200, 201, 202 },
	HUNTER = { 196, 197, 200, 201, 202, 227, 264, 266, 1180, 2567, 5011, 15590 },
	ROGUE = { 198, 201, 264, 266, 1180, 2567, 5011, 15590 },
	PRIEST = { 198, 227, 1180 },
	SHAMAN = { 196, 197, 198, 199, 227, 1180, 15590 },
	MAGE = { 201, 227, 1180 },
	WARLOCK = { 201, 227, 1180 },
	DRUID = { 198, 199, 227, 1180, 15590 },
}
-- weapon masters: name, city, faction, what they teach (cost 10s, polearms 1g)
local MASTERS = {
	{ "Woo Ping", "Stormwind", 1, { 201, 202, 1180, 227, 200, 5011 } },
	{ "Buliwyf Stonehand", "Ironforge", 1, { 196, 197, 198, 199, 15590, 266 } },
	{ "Bixi Wobblebonk", "Ironforge", 1, { 1180, 5011, 2567 } },
	{ "Ilyenia Moonfire", "Darnassus", 1, { 1180, 227, 15590, 264, 2567 } },
	{ "Hanashi", "Orgrimmar", 2, { 196, 197, 227, 264, 2567 } },
	{ "Sayoc", "Orgrimmar", 2, { 196, 197, 1180, 15590, 264, 2567 } },
	{ "Ansekhwa", "Thunder Bluff", 2, { 198, 199, 227, 266 } },
	{ "Archibald", "Undercity", 2, { 201, 202, 1180, 200, 5011 } },
}
function PT.CollectWeapons()
	local _, class = UnitClass("player")
	local myFaction = UnitFactionGroup("player") == "Horde" and 2 or 1
	local out = { learn = {}, known = {} }
	for _, id in ipairs(CAN_USE[class] or {}) do
		local where = {}
		for _, m in ipairs(MASTERS) do
			if m[3] == myFaction then for _, w in ipairs(m[4]) do if w == id then where[#where + 1] = m[1] .. " (" .. m[2] .. ")" end end end
		end
		local item = { id = id, name = WEAPONS[id], where = table.concat(where, ", "), cost = (id == 200) and 10000 or 1000, weapon = true }
		if Known(id) then table.insert(out.known, item) elseif #where > 0 then table.insert(out.learn, item) end
	end
	table.sort(out.learn, function(a, b) return a.name < b.name end)
	table.sort(out.known, function(a, b) return a.name < b.name end)
	return out
end

---------------------------------------------------------------- the spellbook page
local page, tab, rows, lines = nil, nil, {}, {}
local ROWS, ROWH = 40, 16      -- rows made; how many show depends on the page height
local function Build()
	if not SpellBookFrame then
		-- the modern game client (WoW Forever) has a different spellbook: the page becomes its own window
		page = CreateFrame("Frame", "PintsTrainingPage", UIParent, "BackdropTemplate")
		page:SetSize(420, 480); page:SetPoint("CENTER", -200, 40)
		page:SetMovable(true); page:SetClampedToScreen(true); page:RegisterForDrag("LeftButton")
		page:SetScript("OnDragStart", page.StartMoving); page:SetScript("OnDragStop", page.StopMovingOrSizing)
		page:SetFrameStrata("HIGH")
		tinsert(UISpecialFrames, "PintsTrainingPage")
		local x = CreateFrame("Button", nil, page, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", 2, 2)
		page:HookScript("OnHide", function() if tab then tab:SetChecked(false) end end)
	else
	page = CreateFrame("Frame", "PintsTrainingPage", SpellBookFrame, "BackdropTemplate")
	page:SetPoint("TOPLEFT", SpellBookFrame, "TOPLEFT", 18, -72)
	page:SetPoint("BOTTOMRIGHT", SpellBookFrame, "BOTTOMRIGHT", -38, 84)
	end
	page:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
	page:SetBackdropColor(0.06, 0.05, 0.04, 0.97); page:SetBackdropBorderColor(0.5, 0.45, 0.35, 1)
	if SpellBookFrame then page:SetFrameLevel(SpellBookFrame:GetFrameLevel() + 20) end
	page:EnableMouse(true)
	page:Hide()

	page.search = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
	page.search:SetSize(190, 20); page.search:SetPoint("TOPLEFT", 14, -6); page.search:SetAutoFocus(false)
	page.search.hint = page.search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); page.search.hint:SetPoint("LEFT", 2, 0); page.search.hint:SetText("Search")
	page.search:SetScript("OnTextChanged", function(self) self.hint:SetShown(self:GetText() == ""); PT.Refresh() end)
	page.search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	page.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

	page.weapons = CreateFrame("Button", nil, page)
	page.weapons:SetSize(24, 24); page.weapons:SetPoint("LEFT", page.search, "RIGHT", 8, 0)
	page.weapons.t = page.weapons:CreateTexture(nil, "ARTWORK"); page.weapons.t:SetAllPoints(); page.weapons.t:SetTexture("Interface\\Icons\\INV_Sword_04")
	page.weapons:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	page.weapons:SetScript("OnClick", function() PT.showWeapons = not PT.showWeapons; PT.Refresh() end)
	page.weapons:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(PT.showWeapons and "Back to class spells" or "Weapon skills"); GameTooltip:AddLine("Which weapon masters teach the weapons you can use.", 1, 1, 1, true); GameTooltip:Show() end)
	page.weapons:SetScript("OnLeave", function() GameTooltip:Hide() end)

	page.known = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate"); page.known:SetSize(20, 20); page.known:SetPoint("LEFT", page.weapons, "RIGHT", 6, 0)
	local kt = page.known:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); kt:SetPoint("LEFT", page.known, "RIGHT", 0, 0); kt:SetText("Known")
	page.known:SetScript("OnShow", function(self) self:SetChecked(db.showKnown) end)
	page.known:SetScript("OnClick", function(self) db.showKnown = self:GetChecked() and true or false; PT.Refresh() end)

	page.scroll = CreateFrame("ScrollFrame", "PintsTrainingScroll", page, "FauxScrollFrameTemplate")
	page.scroll:SetPoint("TOPLEFT", 6, -32); page.scroll:SetPoint("BOTTOMRIGHT", -28, 8)
	page.scroll:SetScript("OnVerticalScroll", function(self, offset) FauxScrollFrame_OnVerticalScroll(self, offset, ROWH, PT.Draw) end)

	for i = 1, ROWS do
		local r = CreateFrame("Button", nil, page)
		r:SetHeight(ROWH); r:SetPoint("TOPLEFT", 8, -32 - (i - 1) * ROWH); r:SetPoint("RIGHT", page, "RIGHT", -30, 0)
		r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		r.icon = r:CreateTexture(nil, "ARTWORK"); r.icon:SetSize(ROWH - 2, ROWH - 2); r.icon:SetPoint("LEFT", 0, 0)
		r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
		r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); r.right:SetPoint("RIGHT", -2, 0); r.right:SetJustifyH("RIGHT"); r.right:SetWidth(64)
		r.lvl = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.lvl:SetPoint("RIGHT", r.right, "LEFT", -4, 0); r.lvl:SetJustifyH("RIGHT"); r.lvl:SetWidth(52)
		r.head = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); r.head:SetPoint("CENTER")
		r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); r.sub:SetPoint("LEFT", 2, 0); r.sub:SetPoint("RIGHT", -70, 0); r.sub:SetJustifyH("LEFT")
		r.hl = r:CreateTexture(nil, "HIGHLIGHT"); r.hl:SetAllPoints(); r.hl:SetColorTexture(1, 0.82, 0, 0.12)
		r:SetScript("OnEnter", function(self)
			local L = self.line
			if not L then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if L.sub then
				GameTooltip:AddLine("Level " .. L.level)
				GameTooltip:AddLine(L.count .. " to train - " .. Money(L.total), 1, 1, 1)
			elseif L.header then
				GameTooltip:AddLine(L.header)
				if L.total and L.total > 0 then GameTooltip:AddLine("Cost to train all: " .. Money(L.total), 1, 1, 1) end
			elseif L.item.weapon then
				GameTooltip:AddLine(L.item.name)
				GameTooltip:AddLine(L.item.where ~= "" and ("Taught by " .. L.item.where) or "No weapon master on your side teaches this.", 1, 1, 1, true)
				GameTooltip:AddLine("Cost: " .. Money(L.item.cost), 1, 1, 1)
			else
				GameTooltip:SetSpellByID(L.item.id)
				GameTooltip:AddLine(" ")
				GameTooltip:AddDoubleLine("Train at level " .. L.item.level, "Cost: " .. Money(L.item.cost), 1, 0.82, 0, 1, 1, 1)
				GameTooltip:AddLine(cdb.ignored[L.item.id] and "Right-click to stop ignoring" or "Right-click to ignore", 0.5, 0.5, 0.5)
			end
			GameTooltip:Show()
		end)
		r:SetScript("OnLeave", function() GameTooltip:Hide() end)
		r:SetScript("OnClick", function(self, b)
			local L = self.line
			if not L or L.header or L.sub or L.item.weapon then return end
			if b == "RightButton" then cdb.ignored[L.item.id] = (not cdb.ignored[L.item.id]) or nil; PT.Refresh()
			elseif IsModifiedClick("CHATLINK") and GetSpellLink then local link = GetSpellLink(L.item.id); if link then ChatEdit_InsertLink(link) end end
		end)
		rows[i] = r
	end
	page:SetScript("OnShow", function() PT.Refresh() end)
end

function PT.Refresh()
	if not page or not page:IsShown() then return end
	wipe(lines)
	local text = (page.search:GetText() or ""):lower()
	local function match(n) return text == "" or n:lower():find(text, 1, true) end
	local level = UnitLevel("player")
	if PT.showWeapons then
		local w = PT.CollectWeapons()
		local function section(title, color, list)
			local shown = {}
			for _, it in ipairs(list) do if match(it.name) then shown[#shown + 1] = it end end
			if #shown == 0 then return end
			local total = 0; for _, it in ipairs(shown) do total = total + it.cost end
			lines[#lines + 1] = { header = color .. title .. "|r", total = total }
			for _, it in ipairs(shown) do lines[#lines + 1] = { item = it } end
		end
		section("Weapon Skills to Learn", "|cff20ff20", w.learn)
		if db.showKnown then section("Already Known", "|cff888888", w.known) end
		if #lines == 0 then lines[1] = { header = "|cff888888You know every weapon a trainer can teach you.|r" } end
	else
		local s = PT.Collect()
		for _, sec in ipairs(SECTIONS) do
			if sec.key ~= "known" or db.showKnown then
				local shown, total = {}, 0
				for _, it in ipairs(s[sec.key]) do
					it.name = it.name or SpellName(it.id)
					if match(it.name) then shown[#shown + 1] = it; total = total + it.cost end
				end
				if #shown > 0 then
					lines[#lines + 1] = { header = sec.color .. sec.title .. "|r", total = total, key = sec.key }
					if sec.key == "soon" or sec.key == "later" then
						-- what you'll train when: a small heading for each level
						local byLevel, order = {}, {}
						for _, it in ipairs(shown) do
							if not byLevel[it.level] then byLevel[it.level] = {}; order[#order + 1] = it.level end
							table.insert(byLevel[it.level], it)
						end
						table.sort(order)
						for _, lv in ipairs(order) do
							local t = 0; for _, it in ipairs(byLevel[lv]) do t = t + it.cost end
							lines[#lines + 1] = { sub = true, level = lv, count = #byLevel[lv], total = t }
							table.sort(byLevel[lv], function(a, b) return (a.name or "") < (b.name or "") end)
							for _, it in ipairs(byLevel[lv]) do lines[#lines + 1] = { item = it, key = sec.key, grouped = true } end
						end
					else
						for _, it in ipairs(shown) do lines[#lines + 1] = { item = it, key = sec.key } end
					end
				end
			end
		end
		if #lines == 0 then lines[1] = { header = "|cff888888Nothing left to train.|r" } end
	end
	PT.Draw()
end
function PT.Draw()
	if not page then return end
	local visible = math.max(5, math.min(ROWS, math.floor(((page:GetHeight() or 360) - 40) / ROWH)))
	FauxScrollFrame_Update(page.scroll, #lines, visible, ROWH)
	local off = FauxScrollFrame_GetOffset(page.scroll)
	local level = UnitLevel("player")
	for i, r in ipairs(rows) do
		local L = (i <= visible) and lines[i + off] or nil
		r.line = L
		if not L then r:Hide()
		else
			r:Show()
			r.sub:SetText("")
			if L.sub then
				local gap = L.level - level
				r.head:Hide(); r.icon:Hide(); r.name:SetText(""); r.lvl:SetText("")
				r.sub:SetText(("|cffd4a017Level %d|r  |cff888888(%d level%s away)|r"):format(L.level, gap, gap == 1 and "" or "s"))
				r.right:SetText(Money(L.total))
			elseif L.header then
				r.head:SetText(L.header); r.head:Show(); r.icon:Hide(); r.name:SetText(""); r.right:SetText(""); r.lvl:SetText("")
			else
				local it = L.item
				r.head:Hide(); r.icon:Show()
				r.icon:SetPoint("LEFT", L.grouped and 10 or 0, 0)
				if it.weapon then
					r.icon:SetTexture(SpellIcon(it.id) or "Interface\\Icons\\INV_Sword_04")
					r.name:SetText(it.name)
					r.right:SetText(Money(it.cost)); r.lvl:SetText("")
				else
					r.icon:SetTexture(SpellIcon(it.id))
					local rank = (it.rank and it.rank > 0) and (" |cffb0a080(Rank " .. it.rank .. ")|r") or ""
					local grey = (L.key == "known" or L.key == "ignored")
					r.name:SetText((grey and "|cff999999" or "") .. (it.name or SpellName(it.id)) .. (grey and "|r" or "") .. rank)
					-- cost always; the level too (coloured by how far off it is)
					r.right:SetText(it.cost > 0 and Money(it.cost) or "|cff888888free|r")
					local gap = it.level - level
					local col = (gap <= 0) and "|cff20ff20" or (gap <= db.soon) and "|cffffff00" or (gap <= db.soon + 2) and "|cffff8040" or "|cffff2020"
					if L.key == "known" or L.key == "ignored" then col = "|cff999999" end
					r.lvl:SetText(col .. "Lvl " .. it.level .. "|r")
				end
				r.name:SetPoint("RIGHT", r.lvl, "LEFT", -4, 0)
			end
		end
	end
end

---------------------------------------------------------------- the tab on the side of the spellbook
local function PlaceTab()
	if not tab then return end
	if not SpellBookFrame then local a = PT.AvailableNow(); tab.badge:SetText(a > 0 and a or ""); return end
	local n = (GetNumSpellTabs and GetNumSpellTabs()) or 4
	local last
	for i = n, 1, -1 do local t = _G["SpellBookSkillLineTab" .. i]; if t and t:IsShown() then last = t; break end end
	tab:ClearAllPoints()
	if last then tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -17)
	else tab:SetPoint("TOPLEFT", SpellBookFrame, "TOPRIGHT", -32, -48) end
	local a, cost = PT.AvailableNow()
	tab.badge:SetText(a > 0 and a or "")
end
local function SetTab(on)
	if not page then Build() end
	page:SetShown(on)
	if tab then tab:SetChecked(on) end
	if on then PT.Refresh() end
end
PT.SetTab = SetTab
-- modern client (WoW Forever): a tab on the right edge of the Spellbook window that opens the list beside it
local function BuildModernTab()
	local book = PlayerSpellsFrame
	if tab or not book then return end
	tab = CreateFrame("CheckButton", "PintsTrainingTab", UIParent)
	tab:SetSize(36, 36); tab:SetFrameStrata("HIGH")
	tab:SetPoint("TOPLEFT", book, "TOPRIGHT", 0, -70)
	tab:SetNormalTexture("Interface\\Icons\\INV_Misc_Book_09")
	tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight", "ADD")
	tab.badge = tab:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); tab.badge:SetPoint("BOTTOMRIGHT", -1, 2)
	tab:SetScript("OnClick", function(self)
		local on = self:GetChecked()
		if on then
			if not page then Build() end
			page:ClearAllPoints(); page:SetPoint("TOPLEFT", book, "TOPRIGHT", 40, -20)
			page:SetHeight(math.min(560, math.max(400, (book:GetHeight() or 480) - 40)))
		end
		SetTab(on)
	end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("What's to train")
		local a, cost = PT.AvailableNow()
		GameTooltip:AddLine(a > 0 and (a .. " ready to learn - " .. Money(cost)) or "Nothing to learn right now.", 1, 1, 1)
		GameTooltip:AddLine("Shows what you'll learn at each level.", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
	tab:SetShown(book:IsShown())
	book:HookScript("OnShow", function() tab:Show(); local a = PT.AvailableNow(); tab.badge:SetText(a > 0 and a or "") end)
	book:HookScript("OnHide", function() tab:Hide(); tab:SetChecked(false); if page then page:Hide() end end)
	local a = PT.AvailableNow(); tab.badge:SetText(a > 0 and a or "")
end
PT.BuildModernTab = BuildModernTab
local function BuildTab()
	if not SpellBookFrame then BuildModernTab(); return end   -- modern client: the spellbook loads later (see ADDON_LOADED)
	tab = CreateFrame("CheckButton", "PintsTrainingTab", SpellBookFrame)
	tab:SetSize(32, 32)
	local bg = tab:CreateTexture(nil, "BACKGROUND"); bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab"); bg:SetSize(64, 64); bg:SetPoint("TOPLEFT", -3, 11)
	tab:SetNormalTexture("Interface\\Icons\\INV_Misc_QuestionMark")
	tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight", "ADD")
	tab.badge = tab:CreateFontString(nil, "OVERLAY", "NumberFontNormal"); tab.badge:SetPoint("BOTTOMRIGHT", -1, 2)
	tab:SetScript("OnClick", function(self) SetTab(self:GetChecked()) end)
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine("What's to train")
		local a, cost = PT.AvailableNow()
		GameTooltip:AddLine(a > 0 and (a .. " ready to learn - " .. Money(cost)) or "Nothing to learn right now.", 1, 1, 1)
		GameTooltip:Show()
	end)
	tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
	-- picking any of the game's own tabs puts the spellbook back
	for i = 1, 8 do
		local t = _G["SpellBookSkillLineTab" .. i]
		if t then t:HookScript("OnClick", function() SetTab(false) end) end
	end
	for _, n in ipairs({ "SpellBookFrameTabButton1", "SpellBookFrameTabButton2", "SpellBookFrameTabButton3" }) do
		local b = _G[n]; if b then b:HookScript("OnClick", function() SetTab(false) end) end
	end
	SpellBookFrame:HookScript("OnShow", function() PlaceTab(); if page and page:IsShown() then PT.Refresh() end end)
	SpellBookFrame:HookScript("OnHide", function() if page then page:Hide() end; tab:SetChecked(false) end)
	if SpellBookFrame_Update then hooksecurefunc("SpellBookFrame_Update", PlaceTab) end
	PlaceTab()
end

---------------------------------------------------------------- broker (Titan Panel etc.), slash, events
local broker
local function UpdateBroker()
	if not broker then return end
	local a, cost = PT.AvailableNow()
	broker.text = a > 0 and ("|cff20ff20" .. a .. " to train|r") or "Training: none"
end
local function BuildBroker()
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	if not LDB then return end
	broker = LDB:NewDataObject("PintsTraining", { type = "data source", text = "Training", icon = "Interface\\Icons\\INV_Misc_Book_09",
		OnClick = function() SlashCmdList.PINTSTRAINING("") end,
		OnTooltipShow = function(tt)
			tt:AddLine("Pint's Training")
			local s = PT.Collect()
			local total = 0
			for _, it in ipairs(s.now) do total = total + it.cost; tt:AddDoubleLine(SpellName(it.id) .. (it.rank > 0 and (" (Rank " .. it.rank .. ")") or ""), Money(it.cost), 1, 1, 1, 1, 1, 1) end
			if #s.now == 0 then tt:AddLine("Nothing to learn right now.", 0.7, 0.7, 0.7) else tt:AddDoubleLine("Total", Money(total), 1, 0.82, 0, 1, 1, 1) end
			if s.soon[1] then tt:AddLine(" "); tt:AddLine(#s.soon .. " more in the next " .. db.soon .. " levels", 0.4, 0.73, 1) end
		end })
	UpdateBroker()
	local Icon = LibStub("LibDBIcon-1.0", true)
	if Icon then Icon:Register("PintsTraining", broker, db.minimap) end
end
SLASH_PINTSTRAINING1 = "/ptrain"
SLASH_PINTSTRAINING2 = "/pintstraining"
SlashCmdList.PINTSTRAINING = function(msg)
	msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "off-wt" then
		local off = (C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
		pcall(off, "WhatsTraining"); Print("What's Training switched off - /reload to finish.")
	elseif msg == "levelup" then db.levelUpNote = not db.levelUpNote; Print("level-up note " .. (db.levelUpNote and "on" or "off"))
	else
		if not SpellBookFrame then SetTab(not (page and page:IsShown())); return end
		if not SpellBookFrame:IsShown() then ToggleSpellBook(BOOKTYPE_SPELL or "spell") end
		SetTab(true)
	end
end
---------------------------------------------------------------- reading the trainer
-- Talking to your class trainer: everything they list (what you can learn now, later, and what you know), with level and
-- cost, is saved. From then on the tab shows that instead of the Classic list.
local scanTip
local function ReadTrainer()
	if not (GetNumTrainerServices and GetTrainerServiceInfo) then return end
	if IsTradeskillTrainer and IsTradeskillTrainer() then return end        -- (a profession trainer)
	local _, class = UnitClass("player")
	local known = {}
	for _, e in ipairs(DATA[class] or {}) do known[e[1]] = true end
	-- show every kind while reading (available, not yet, already known), then put the trainer window back as it was
	local saved = {}
	if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
		for _, t in ipairs({ "available", "unavailable", "used" }) do saved[t] = GetTrainerServiceTypeFilter(t); pcall(SetTrainerServiceTypeFilter, t, 1) end
	end
	if not scanTip then scanTip = CreateFrame("GameTooltip", "PintsTrainingScanTip", nil, "GameTooltipTemplate") end
	local out, classSpells = {}, 0
	for i = 1, GetNumTrainerServices() or 0 do
		local name, rankText, kind = GetTrainerServiceInfo(i)
		if name and kind ~= "header" then
			local id
			scanTip:SetOwner(UIParent, "ANCHOR_NONE")
			if pcall(scanTip.SetTrainerService, scanTip, i) and scanTip.GetSpell then
				local _, sid = scanTip:GetSpell(); id = tonumber(sid)
			end
			scanTip:Hide()
			if id then
				if known[id] then classSpells = classSpells + 1 end
				local lvl = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i) or 1
				local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
				out[#out + 1] = { id = id, level = lvl, cost = cost, rank = tonumber(tostring(rankText or ""):match("(%d+)")) or 0, name = name }
			end
		end
	end
	for t, v in pairs(saved) do pcall(SetTrainerServiceTypeFilter, t, v and 1 or 0) end
	-- a weapon master or someone else's trainer lists none of your class's spells: not your class trainer
	if #out == 0 or classSpells == 0 then return end
	table.sort(out, function(a, b) if a.level ~= b.level then return a.level < b.level end return a.name < b.name end)
	db.trainer = db.trainer or {}
	local had = db.trainer[TrainerKey()]
	db.trainer[TrainerKey()] = { seen = time(), spells = out }
	if not had then Print(("read your trainer's list (%d spells) - the tab now shows what this version of the game teaches."):format(#out)) end
	PT.Refresh()
end
PT.ReadTrainer = ReadTrainer

local function Loaded(a) if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(a) end return IsAddOnLoaded and IsAddOnLoaded(a) end
local ev = CreateFrame("Frame")
-- (pcall: an event this game version doesn't have mustn't stop the rest from loading)
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "TRAINER_UPDATE", "TRAINER_SHOW" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e, a1)
	if e == "ADDON_LOADED" and a1 == ADDON then
		PintsTrainingDB = PintsTrainingDB or {}; db = PintsTrainingDB
		for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = (type(v) == "table") and {} or v end end
		PintsTrainingCharDB = PintsTrainingCharDB or {}; cdb = PintsTrainingCharDB
		cdb.ignored = cdb.ignored or {}
		PT.db = db
	elseif e == "ADDON_LOADED" and a1 == "Blizzard_PlayerSpells" then
		if db then BuildModernTab() end
	elseif e == "ADDON_LOADED" then
		return
	elseif e == "PLAYER_LOGIN" then
		BuildTab(); BuildBroker()
		if Loaded("WhatsTraining") then Print("What's Training is on too - /ptrain off-wt to switch it off, then /reload.") end
	elseif e == "TRAINER_SHOW" then
		C_Timer.After(0.5, function() pcall(ReadTrainer) end)
	elseif e == "PLAYER_LEVEL_UP" then
		C_Timer.After(1, function()
			UpdateBroker(); if tab then PlaceTab() end
			if db.levelUpNote then
				local a, cost = PT.AvailableNow()
				if a > 0 then Print(("%d new spell%s to train (%s). /ptrain to see them."):format(a, a == 1 and "" or "s", Money(cost))) end
			end
		end)
	else
		UpdateBroker(); if tab then PlaceTab() end; PT.Refresh()
	end
end)
