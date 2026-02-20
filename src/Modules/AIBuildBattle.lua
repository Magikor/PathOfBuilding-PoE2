-- Path of Building
--
-- Module: AI Build Battle
-- In-app AI vs Human battle simulation for PoE2 builds.
--

local pairs = pairs
local t_insert = table.insert
local s_format = string.format
local m_min = math.min
local m_max = math.max
local m_random = math.random

aiBattleLib = { }

local humanBaselines = {
	{
		label = "human_noob",
		attackDamageInc = 20,
		critBonus = 25,
		flatLife = 20,
		customMods = "",
	},
	{
		label = "human_mid",
		attackDamageInc = 80,
		critBonus = 90,
		flatLife = 60,
		customMods = "+20% to all elemental resistances",
	},
	{
		label = "human_endgame",
		attackDamageInc = 160,
		critBonus = 180,
		flatLife = 120,
		customMods = "+60% to all elemental resistances\n+20% to chaos resistance",
	},
}

local availableCustomMods = {
	"+20% to all elemental resistances",
	"+20% to chaos resistance",
	"10% increased Movement Speed",
	"10% increased attack speed",
	"3% of Physical Attack Damage Leeched as Life",
	"10% reduced Mana Cost of Skills",
}

local defaultSkillGroup = "Lightning Arrow 20/0  1\n"

local archetypes = {
	{
		id = "bow_lightning",
		name = "Bow Lightning",
		classNames = { "Ranger", "Mercenary", "Huntress" },
		weaponBase = "Heavy Bow",
		offhandBase = "Quiver",
		skillGroup = "Lightning Arrow 20/0  1\n",
	},
	{
		id = "mace_slam",
		name = "Mace Slam",
		classNames = { "Warrior" },
		weaponBase = "Two Handed Mace",
		offhandBase = "Ring",
		skillGroup = "Rolling Slam 20/0  1\n",
	},
	{
		id = "wand_spell",
		name = "Wand Spell",
		classNames = { "Witch", "Sorceress" },
		weaponBase = "Wand",
		offhandBase = "Ring",
		skillGroup = "Spark 20/0  1\n",
	},
	{
		id = "staff_monk",
		name = "Quarterstaff Striker",
		classNames = { "Monk" },
		weaponBase = "Quarterstaff",
		offhandBase = "Ring",
		skillGroup = "Ice Strike 20/0  1\n",
	},
	{
		id = "fallback_bow",
		name = "Fallback Bow",
		classNames = nil,
		weaponBase = "Heavy Bow",
		offhandBase = "Quiver",
		skillGroup = defaultSkillGroup,
	},
}

local function clone(tbl)
	local out = { }
	for k, v in pairs(tbl) do
		out[k] = v
	end
	return out
end

local function classMatchesArchetype(className, archetype)
	if not archetype.classNames then
		return true
	end
	for i = 1, #archetype.classNames do
		if archetype.classNames[i] == className then
			return true
		end
	end
	return false
end

local function getArchetypeById(id)
	for i = 1, #archetypes do
		if archetypes[i].id == id then
			return archetypes[i]
		end
	end
	return archetypes[#archetypes]
end

local function archetypeUsesSpells(archetype)
	return archetype and archetype.id == "wand_spell"
end

local function getCompatibleArchetypes(className)
	local specific = { }
	local generic = { }
	for i = 1, #archetypes do
		local archetype = archetypes[i]
		if archetype.classNames and classMatchesArchetype(className, archetype) then
			specific[#specific + 1] = archetype
		elseif not archetype.classNames then
			generic[#generic + 1] = archetype
		end
	end
	if #specific > 0 then
		return specific
	end
	if #generic == 0 then
		generic[1] = archetypes[#archetypes]
	end
	return generic
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function pickDps(output)
	local best = 0
	for key, value in pairs(output or { }) do
		if type(value) == "number" and key:find("DPS") and value > best then
			best = value
		end
	end
	return best
end

local function joinMods(mods)
	if #mods == 0 then
		return ""
	end
	return table.concat(mods, "\n")
end

local function randomCustomMods()
	local selected = { }
	for i = 1, #availableCustomMods do
		if m_random() < 0.33 then
			selected[#selected + 1] = availableCustomMods[i]
		end
	end
	if #selected == 0 and m_random() < 0.4 then
		selected[1] = availableCustomMods[m_random(1, #availableCustomMods)]
	end
	return joinMods(selected)
end

local function seedMetaCandidate(classCandidate, archetype, profile)
	local isSpell = archetypeUsesSpells(archetype)
	local cfg = {
		attackDamageInc = isSpell and m_random(50, 130) or m_random(120, 230),
		critBonus = m_random(140, 260),
		flatLife = m_random(120, 220),
		attackSpeedInc = isSpell and m_random(8, 45) or m_random(25, 70),
		elementalDamageInc = m_random(60, 170),
		projectileDamageInc = m_random(20, 160),
		resAll = m_random(55, 75),
		chaosRes = m_random(20, 45),
		armourInc = m_random(70, 220),
		evasionInc = m_random(70, 220),
		lifeLeech = isSpell and m_random(0, 3) or m_random(4, 10),
		manaEfficiency = isSpell and m_random(18, 40) or m_random(0, 18),
		moveSpeed = m_random(18, 40),
		customMods = randomCustomMods(),
		archetypeId = archetype.id,
		classId = classCandidate.classId,
		className = classCandidate.className,
		ascendClassId = classCandidate.ascendClassId,
		ascendClassName = classCandidate.ascendClassName,
	}

	if profile == "offense" then
		cfg.attackDamageInc = clamp(cfg.attackDamageInc + m_random(20, 45), 10, 240)
		cfg.critBonus = clamp(cfg.critBonus + m_random(20, 40), 20, 280)
		cfg.flatLife = clamp(cfg.flatLife - m_random(10, 35), 10, 220)
		cfg.resAll = clamp(cfg.resAll - m_random(5, 12), 0, 75)
	elseif profile == "defense" then
		cfg.flatLife = clamp(cfg.flatLife + m_random(15, 40), 10, 220)
		cfg.resAll = clamp(cfg.resAll + m_random(4, 12), 0, 75)
		cfg.chaosRes = clamp(cfg.chaosRes + m_random(4, 10), 0, 50)
		cfg.attackDamageInc = clamp(cfg.attackDamageInc - m_random(8, 24), 10, 240)
	end

	return cfg
end

local function getClassCandidates(build)
	local classCandidates = { }
	for classId, classData in pairs(build.spec.tree.classes or { }) do
		if type(classId) == "number" and classData and classData.name and classData.classes then
			for ascendClassId, ascendData in pairs(classData.classes) do
				if type(ascendClassId) == "number" and ascendData then
					classCandidates[#classCandidates + 1] = {
						classId = classId,
						className = classData.name,
						ascendClassId = ascendClassId,
						ascendClassName = ascendData.name or "None",
					}
				end
			end
		end
	end

	table.sort(classCandidates, function(a, b)
		if a.className == b.className then
			return a.ascendClassName < b.ascendClassName
		end
		return a.className < b.className
	end)

	return classCandidates
end

local function randomCandidate(classCandidate)
	local compatible = getCompatibleArchetypes(classCandidate.className)
	local archetype = compatible[m_random(1, #compatible)]
	return {
		attackDamageInc = m_random(10, 220),
		critBonus = m_random(20, 260),
		flatLife = m_random(10, 180),
		attackSpeedInc = m_random(0, 60),
		elementalDamageInc = m_random(0, 140),
		projectileDamageInc = m_random(0, 140),
		resAll = m_random(0, 60),
		chaosRes = m_random(0, 45),
		armourInc = m_random(0, 180),
		evasionInc = m_random(0, 180),
		lifeLeech = m_random(0, 8),
		manaEfficiency = m_random(0, 30),
		moveSpeed = m_random(0, 35),
		customMods = randomCustomMods(),
		archetypeId = archetype.id,
		classId = classCandidate.classId,
		className = classCandidate.className,
		ascendClassId = classCandidate.ascendClassId,
		ascendClassName = classCandidate.ascendClassName,
	}
end

local function crossoverCandidate(a, b)
	return {
		attackDamageInc = (m_random() < 0.5) and a.attackDamageInc or b.attackDamageInc,
		critBonus = (m_random() < 0.5) and a.critBonus or b.critBonus,
		flatLife = (m_random() < 0.5) and a.flatLife or b.flatLife,
		attackSpeedInc = (m_random() < 0.5) and a.attackSpeedInc or b.attackSpeedInc,
		elementalDamageInc = (m_random() < 0.5) and a.elementalDamageInc or b.elementalDamageInc,
		projectileDamageInc = (m_random() < 0.5) and a.projectileDamageInc or b.projectileDamageInc,
		resAll = (m_random() < 0.5) and a.resAll or b.resAll,
		chaosRes = (m_random() < 0.5) and a.chaosRes or b.chaosRes,
		armourInc = (m_random() < 0.5) and a.armourInc or b.armourInc,
		evasionInc = (m_random() < 0.5) and a.evasionInc or b.evasionInc,
		lifeLeech = (m_random() < 0.5) and a.lifeLeech or b.lifeLeech,
		manaEfficiency = (m_random() < 0.5) and a.manaEfficiency or b.manaEfficiency,
		moveSpeed = (m_random() < 0.5) and a.moveSpeed or b.moveSpeed,
		customMods = (m_random() < 0.5) and a.customMods or b.customMods,
		archetypeId = (m_random() < 0.5) and a.archetypeId or b.archetypeId,
		classId = a.classId,
		className = a.className,
		ascendClassId = a.ascendClassId,
		ascendClassName = a.ascendClassName,
	}
end

local function mutateCandidate(parent)
	local nextCfg = clone(parent)
	nextCfg.attackDamageInc = clamp(nextCfg.attackDamageInc + m_random(-18, 18), 10, 240)
	nextCfg.critBonus = clamp(nextCfg.critBonus + m_random(-24, 24), 20, 280)
	nextCfg.flatLife = clamp(nextCfg.flatLife + m_random(-14, 14), 10, 220)
	nextCfg.attackSpeedInc = clamp((nextCfg.attackSpeedInc or 0) + m_random(-10, 10), 0, 80)
	nextCfg.elementalDamageInc = clamp((nextCfg.elementalDamageInc or 0) + m_random(-16, 16), 0, 180)
	nextCfg.projectileDamageInc = clamp((nextCfg.projectileDamageInc or 0) + m_random(-16, 16), 0, 180)
	nextCfg.resAll = clamp((nextCfg.resAll or 0) + m_random(-10, 10), 0, 75)
	nextCfg.chaosRes = clamp((nextCfg.chaosRes or 0) + m_random(-8, 8), 0, 50)
	nextCfg.armourInc = clamp((nextCfg.armourInc or 0) + m_random(-20, 20), 0, 220)
	nextCfg.evasionInc = clamp((nextCfg.evasionInc or 0) + m_random(-20, 20), 0, 220)
	nextCfg.lifeLeech = clamp((nextCfg.lifeLeech or 0) + m_random(-2, 2), 0, 10)
	nextCfg.manaEfficiency = clamp((nextCfg.manaEfficiency or 0) + m_random(-6, 6), 0, 40)
	nextCfg.moveSpeed = clamp((nextCfg.moveSpeed or 0) + m_random(-8, 8), 0, 45)
	if m_random() < 0.2 then
		nextCfg.customMods = randomCustomMods()
	end
	if m_random() < 0.15 then
		local compatible = getCompatibleArchetypes(nextCfg.className)
		nextCfg.archetypeId = compatible[m_random(1, #compatible)].id
	end
	return nextCfg
end

local function addItem(build, raw)
	local ok = pcall(function()
		build.itemsTab:CreateDisplayItemFromRaw(raw)
		build.itemsTab:AddDisplayItem()
	end)
	return ok
end

local function addItemWithFallback(build, base, lines, fallbackBase)
	local raw = "New Item\n" .. base .. "\n" .. lines .. "\n"
	if addItem(build, raw) then
		return true
	end
	local fallback = fallbackBase or "Ring"
	local fallbackRaw = "New Item\n" .. fallback .. "\n" .. lines .. "\n"
	return addItem(build, fallbackRaw)
end

local function addSkillSetup(build, skillGroup)
	local candidates = {
		skillGroup,
		defaultSkillGroup,
		"Spark 20/0  1\n",
		"Lightning Arrow 20/0  1\n",
	}

	for i = 1, #candidates do
		local value = candidates[i]
		if value and #value > 0 then
			local ok = pcall(function()
				build.skillsTab:PasteSocketGroup(value)
			end)
			if ok then
				return true
			end
		end
	end

	return false
end

local function evaluateBuild(build, snapshotXml, label, cfg)
	local loadErr = build:LoadDB(snapshotXml, build.buildName or "AI Battle Snapshot")
	if loadErr then
		return nil, "Failed to load snapshot state"
	end

	if cfg.classId and cfg.ascendClassId then
		build.spec:SelectClass(cfg.classId)
		build.spec:SelectAscendClass(cfg.ascendClassId)
	end
	local archetype = getArchetypeById(cfg.archetypeId)
	local isSpellArchetype = archetypeUsesSpells(archetype)
	local weaponSpeedLine = isSpellArchetype and "%d%% increased cast speed" or "%d%% increased attack speed"
	local weaponDamageLine = isSpellArchetype and "%d%% increased spell damage" or "%d%% increased attack damage"

	addItemWithFallback(
		build,
		archetype.weaponBase,
		string.format(
			weaponDamageLine
				.. "\n%d%% increased Critical Damage Bonus\n"
				.. weaponSpeedLine
				.. "\n%d%% increased elemental damage with attack skills",
			cfg.attackDamageInc,
			cfg.critBonus,
			cfg.attackSpeedInc or 0,
			cfg.elementalDamageInc or 0
		),
		"Ring"
	)

	addItemWithFallback(
		build,
		archetype.offhandBase or "Ring",
		string.format(
			"%d%% increased projectile damage\n"
				.. "+%d to maximum life\n"
				.. "+%d%% to all elemental resistances\n"
				.. "+%d%% to chaos resistance",
			cfg.projectileDamageInc or 0,
			m_min(220, cfg.flatLife + 25),
			cfg.resAll or 0,
			cfg.chaosRes or 0
		),
		"Ring"
	)

	addItemWithFallback(
		build,
		"Ring",
		string.format(
			"+%d to maximum life\n%d%% increased attack speed\n%d%% increased armour\n%d%% increased evasion rating",
			cfg.flatLife,
			cfg.attackSpeedInc or 0,
			cfg.armourInc or 0,
			cfg.evasionInc or 0
		),
		"Ring"
	)

	addItemWithFallback(
		build,
		"Boots",
		string.format(
			"+%d%% to movement speed\n+%d to maximum life\n+%d%% to all elemental resistances\n+%d%% to chaos resistance",
			cfg.moveSpeed or 0,
			m_min(220, cfg.flatLife + 10),
			cfg.resAll or 0,
			cfg.chaosRes or 0
		),
		"Ring"
	)

	addItemWithFallback(
		build,
		"Body Armour",
		string.format(
			"+%d to maximum life\n%d%% increased armour\n%d%% increased evasion rating\n+%d%% to all elemental resistances",
			m_min(260, cfg.flatLife + 45),
			cfg.armourInc or 0,
			cfg.evasionInc or 0,
			cfg.resAll or 0
		),
		"Ring"
	)

	addItemWithFallback(
		build,
		"Helm",
		string.format(
			"+%d to maximum life\n+%d%% to all elemental resistances\n+%d%% to chaos resistance",
			m_min(200, cfg.flatLife + 20),
			cfg.resAll or 0,
			cfg.chaosRes or 0
		),
		"Ring"
	)

	if cfg.customMods and #cfg.customMods > 0 then
		build.configTab.input.customMods = cfg.customMods
		build.configTab:BuildModList()
	end

	addSkillSetup(build, archetype.skillGroup)
	build.calcsTab:BuildOutput()

	local output = build.calcsTab.mainOutput or { }
	local calcsOutput = build.calcsTab.calcsOutput or { }

	local dps = pickDps(output)
	local life = output.Life or 0
	local physMaxHit = calcsOutput.PhysicalMaximumHitTaken or 0

	local fitBonus = classMatchesArchetype(cfg.className, archetype) and (dps * 0.05) or 0
	local elementalCoverage = m_min((cfg.resAll or 0), 75) / 75
	local chaosCoverage = m_min((cfg.chaosRes or 0), 40) / 40
	local defenseCoverage = m_min(1, ((life / 1800) * 0.45) + ((physMaxHit / 6000) * 0.55))
	local sustainCoverage
	if isSpellArchetype then
		sustainCoverage = m_min((cfg.manaEfficiency or 0) / 30, 1)
	else
		sustainCoverage = m_min((cfg.lifeLeech or 0) / 8, 1)
	end
	local mobilityCoverage = m_min((cfg.moveSpeed or 0) / 35, 1)

	local safetyBonus = 18000 * ((elementalCoverage * 0.45) + (chaosCoverage * 0.15) + (defenseCoverage * 0.4))
	local utilityBonus = dps * ((sustainCoverage * 0.05) + (mobilityCoverage * 0.04))

	local safetyPenalty = 1
	if elementalCoverage < 0.75 then
		safetyPenalty = safetyPenalty * 0.7
	end
	if defenseCoverage < 0.45 then
		safetyPenalty = safetyPenalty * 0.75
	end

	local score = (dps + (life * 120) + (physMaxHit * 80) + fitBonus + safetyBonus + utilityBonus) * safetyPenalty
	local minCoverage = m_min(elementalCoverage, defenseCoverage, m_max(chaosCoverage, 0.45))
	local robustScore = score * (0.75 + (0.25 * minCoverage))

	return {
		label = label,
		dps = dps,
		life = life,
		physicalMaximumHitTaken = physMaxHit,
		score = score,
		robustScore = robustScore,
		classId = cfg.classId,
		className = cfg.className,
		ascendClassId = cfg.ascendClassId,
		ascendClassName = cfg.ascendClassName,
		archetypeId = archetype.id,
		archetypeName = archetype.name,
		weaponBase = archetype.weaponBase,
		offhandBase = archetype.offhandBase,
		skillGroup = archetype.skillGroup,
		quality = {
			elementalCoverage = elementalCoverage,
			chaosCoverage = chaosCoverage,
			defenseCoverage = defenseCoverage,
			sustainCoverage = sustainCoverage,
			mobilityCoverage = mobilityCoverage,
			safetyPenalty = safetyPenalty,
		},
		config = cfg,
	}
end

local function scoreClassProbe(build, snapshotXml, classCandidate)
	local probeCfg = {
		attackDamageInc = 90,
		critBonus = 100,
		flatLife = 75,
		attackSpeedInc = 20,
		elementalDamageInc = 40,
		projectileDamageInc = 30,
		resAll = 30,
		chaosRes = 10,
		armourInc = 60,
		evasionInc = 60,
		lifeLeech = 3,
		manaEfficiency = 12,
		moveSpeed = 20,
		customMods = "+20% to all elemental resistances",
		archetypeId = getCompatibleArchetypes(classCandidate.className)[1].id,
		classId = classCandidate.classId,
		className = classCandidate.className,
		ascendClassId = classCandidate.ascendClassId,
		ascendClassName = classCandidate.ascendClassName,
	}
	local result, err = evaluateBuild(
		build,
		snapshotXml,
		s_format("probe_%s_%s", classCandidate.className, classCandidate.ascendClassName),
		probeCfg
	)
	if not result then
		return nil, err
	end
	return {
		classId = classCandidate.classId,
		className = classCandidate.className,
		ascendClassId = classCandidate.ascendClassId,
		ascendClassName = classCandidate.ascendClassName,
		archetypeId = result.archetypeId,
		archetypeName = result.archetypeName,
		weaponBase = result.weaponBase,
		offhandBase = result.offhandBase,
		score = result.score,
		dps = result.dps,
		life = result.life,
		physicalMaximumHitTaken = result.physicalMaximumHitTaken,
	}
end

local function optimizeClass(build, snapshotXml, classCandidate, generations, populationSize, eliteSize)
	local population = { }
	for i = 1, populationSize do
		population[i] = randomCandidate(classCandidate)
	end

	local bestResult = nil
	for g = 1, generations do
		local scored = { }
		for i = 1, #population do
			local result, err = evaluateBuild(
				build,
				snapshotXml,
				s_format("ai_%s_%s_g%d_%d", classCandidate.className, classCandidate.ascendClassName, g, i),
				population[i]
			)
			if not result then
				return nil, err
			end
			scored[i] = result
		end

		table.sort(scored, function(a, b)
			return (a.robustScore or a.score) > (b.robustScore or b.score)
		end)

		if not bestResult or (scored[1].robustScore or scored[1].score) > (bestResult.robustScore or bestResult.score) then
			bestResult = scored[1]
		end

		local nextPopulation = { }
		for i = 1, eliteSize do
			nextPopulation[i] = clone(scored[i].config)
		end

		while #nextPopulation < populationSize do
			local parentA = scored[m_random(1, eliteSize)].config
			local parentB = scored[m_random(1, eliteSize)].config
			local child = crossoverCandidate(parentA, parentB)
			nextPopulation[#nextPopulation + 1] = mutateCandidate(child)
		end

		population = nextPopulation
	end

	return bestResult
end

local function optimizeHumanChallenger(build, snapshotXml, classCandidate, generations, populationSize, eliteSize)
	local compatible = getCompatibleArchetypes(classCandidate.className)
	local profiles = { "balanced", "offense", "defense" }
	local population = { }
	for i = 1, populationSize do
		local archetype = compatible[m_random(1, #compatible)]
		local profile = profiles[m_random(1, #profiles)]
		local seeded = seedMetaCandidate(classCandidate, archetype, profile)
		if i > 1 and m_random() < 0.5 then
			seeded = mutateCandidate(seeded)
		end
		population[i] = seeded
	end

	local bestResult = nil
	for g = 1, generations do
		local scored = { }
		for i = 1, #population do
			local result, err = evaluateBuild(
				build,
				snapshotXml,
				s_format("human_meta_%s_%s_g%d_%d", classCandidate.className, classCandidate.ascendClassName, g, i),
				population[i]
			)
			if not result then
				return nil, err
			end
			scored[i] = result
		end

		table.sort(scored, function(a, b)
			return (a.robustScore or a.score) > (b.robustScore or b.score)
		end)

		if not bestResult or (scored[1].robustScore or scored[1].score) > (bestResult.robustScore or bestResult.score) then
			bestResult = scored[1]
		end

		local nextPopulation = { }
		for i = 1, eliteSize do
			nextPopulation[i] = clone(scored[i].config)
		end

		while #nextPopulation < populationSize do
			local parentA = scored[m_random(1, eliteSize)].config
			local parentB = scored[m_random(1, eliteSize)].config
			local child = crossoverCandidate(parentA, parentB)
			nextPopulation[#nextPopulation + 1] = mutateCandidate(child)
		end

		population = nextPopulation
	end

	if bestResult then
		bestResult.label = "human_web_meta"
	end

	return bestResult
end

local function jsonEscape(value)
	local out = tostring(value)
	out = out:gsub("\\", "\\\\")
	out = out:gsub('"', '\\"')
	out = out:gsub("\n", "\\n")
	out = out:gsub("\r", "\\r")
	out = out:gsub("\t", "\\t")
	return out
end

local function encodeJson(value)
	local t = type(value)
	if t == "nil" then
		return "null"
	elseif t == "number" then
		return tostring(value)
	elseif t == "boolean" then
		return value and "true" or "false"
	elseif t == "string" then
		return '"' .. jsonEscape(value) .. '"'
	elseif t == "table" then
		local isArray = true
		local maxIndex = 0
		for k, _ in pairs(value) do
			if type(k) ~= "number" then
				isArray = false
				break
			end
			if k > maxIndex then maxIndex = k end
		end
		if isArray then
			local parts = { }
			for i = 1, maxIndex do
				parts[#parts + 1] = encodeJson(value[i])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = { }
		for k, v in pairs(value) do
			parts[#parts + 1] = '"' .. jsonEscape(k) .. '":' .. encodeJson(v)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

function aiBattleLib:Run(build, options)
	local _ = self
	options = options or { }
	local skipHumanGauntlet = options.skipHumanGauntlet == true
	local maxClassCandidates = tonumber(options.maxClassCandidates) or 0
	local maxClassesOptimized = tonumber(options.maxClassesOptimized) or 0
	local generations = options.generations or 6
	local populationSize = options.populationSize or 18
	local eliteSize = options.eliteSize or 5
	local topAscendanciesPerClass = options.topAscendanciesPerClass or 2
	local perClassGenerations = options.perClassGenerations or m_min(generations, 4)
	local perClassPopulation = options.perClassPopulation or m_max(8, m_min(populationSize, 14))
	local perClassElite = options.perClassElite or m_max(2, m_min(eliteSize, 4))
	local humanGenerations = options.humanGenerations or m_min(generations + 2, 10)
	local humanPopulation = options.humanPopulation or m_max(populationSize, 24)
	local humanElite = options.humanElite or m_max(perClassElite, 6)
	local humanAscendanciesPerClass = options.humanAscendanciesPerClass or m_max(topAscendanciesPerClass, 2)

	if perClassElite > perClassPopulation then
		perClassElite = perClassPopulation
	end
	if humanElite > humanPopulation then
		humanElite = humanPopulation
	end

	local snapshotXml = build:SaveDB("AI Battle Snapshot")
	if not snapshotXml then
		return nil, "Could not create build snapshot"
	end

	local scoredHumans = { }
	local currentClass = {
		classId = build.spec.curClassId,
		className = build.spec.curClassName,
		ascendClassId = build.spec.curAscendClassId,
		ascendClassName = build.spec.curAscendClassName,
	}
	for i = 1, #humanBaselines do
		local human = clone(humanBaselines[i])
		human.classId = currentClass.classId
		human.className = currentClass.className
		human.ascendClassId = currentClass.ascendClassId
		human.ascendClassName = currentClass.ascendClassName
		local result, err = evaluateBuild(build, snapshotXml, human.label, human)
		if not result then
			build:LoadDB(snapshotXml, build.buildName or "AI Battle Snapshot")
			build.calcsTab:BuildOutput()
			return nil, err
		end
		scoredHumans[i] = result
	end

	table.sort(scoredHumans, function(a, b)
		return (a.robustScore or a.score) > (b.robustScore or b.score)
	end)

	local classCandidates = getClassCandidates(build)
	if options.preferSpell then
		local filteredCandidates = { }
		for i = 1, #classCandidates do
			local className = classCandidates[i].className
			if className == "Witch" or className == "Sorceress" then
				filteredCandidates[#filteredCandidates + 1] = classCandidates[i]
			end
		end
		if #filteredCandidates > 0 then
			classCandidates = filteredCandidates
		end
	end
	if #classCandidates == 0 then
		build:LoadDB(snapshotXml, build.buildName or "AI Battle Snapshot")
		build.calcsTab:BuildOutput()
		return nil, "No classes available to evaluate"
	end

	local classProbes = { }
	for i = 1, #classCandidates do
		local probe, err = scoreClassProbe(build, snapshotXml, classCandidates[i])
		if not probe then
			build:LoadDB(snapshotXml, build.buildName or "AI Battle Snapshot")
			build.calcsTab:BuildOutput()
			return nil, err
		end
		classProbes[#classProbes + 1] = probe
	end

	table.sort(classProbes, function(a, b)
		return a.score > b.score
	end)

	if maxClassCandidates > 0 and #classProbes > maxClassCandidates then
		while #classProbes > maxClassCandidates do
			table.remove(classProbes)
		end
	end

	local probesByClass = { }
	for i = 1, #classProbes do
		local probe = classProbes[i]
		probesByClass[probe.className] = probesByClass[probe.className] or { }
		t_insert(probesByClass[probe.className], probe)
	end

	local classOrder = { }
	for className, probeList in pairs(probesByClass) do
		table.sort(probeList, function(a, b)
			return a.score > b.score
		end)
		classOrder[#classOrder + 1] = {
			className = className,
			bestScore = probeList[1] and probeList[1].score or 0,
		}
	end
	table.sort(classOrder, function(a, b)
		return a.bestScore > b.bestScore
	end)

	if maxClassesOptimized > 0 and #classOrder > maxClassesOptimized then
		while #classOrder > maxClassesOptimized do
			table.remove(classOrder)
		end
	end

	local classBuilds = { }
	for idx = 1, #classOrder do
		local className = classOrder[idx].className
		local probeList = probesByClass[className]
		table.sort(probeList, function(a, b)
			return a.score > b.score
		end)

		local bestForClass = nil
		for i = 1, m_min(topAscendanciesPerClass, #probeList) do
			local classCandidate = probeList[i]
			local optimized, err = optimizeClass(
				build,
				snapshotXml,
				classCandidate,
				perClassGenerations,
				perClassPopulation,
				perClassElite
			)
			if not optimized then
				build:LoadDB(snapshotXml, build.buildName or "AI Battle Snapshot")
				build.calcsTab:BuildOutput()
				return nil, err
			end
			if not bestForClass
				or (optimized.robustScore or optimized.score)
					> (bestForClass.robustScore or bestForClass.score) then
				bestForClass = optimized
			end
		end

		if bestForClass then
			classBuilds[#classBuilds + 1] = {
				classId = bestForClass.classId,
				className = className,
				ascendClassId = bestForClass.ascendClassId,
				ascendClassName = bestForClass.ascendClassName,
				score = bestForClass.score,
				robustScore = bestForClass.robustScore,
				dps = bestForClass.dps,
				life = bestForClass.life,
				physicalMaximumHitTaken = bestForClass.physicalMaximumHitTaken,
				weaponBase = bestForClass.weaponBase,
				offhandBase = bestForClass.offhandBase,
				archetypeId = bestForClass.archetypeId,
				archetypeName = bestForClass.archetypeName,
				skillGroup = bestForClass.skillGroup,
				quality = bestForClass.quality,
				stats = {
					attackDamageInc = bestForClass.config and bestForClass.config.attackDamageInc or 0,
					critBonus = bestForClass.config and bestForClass.config.critBonus or 0,
					attackSpeedInc = bestForClass.config and bestForClass.config.attackSpeedInc or 0,
					elementalDamageInc = bestForClass.config and bestForClass.config.elementalDamageInc or 0,
					projectileDamageInc = bestForClass.config and bestForClass.config.projectileDamageInc or 0,
					flatLife = bestForClass.config and bestForClass.config.flatLife or 0,
					resAll = bestForClass.config and bestForClass.config.resAll or 0,
					chaosRes = bestForClass.config and bestForClass.config.chaosRes or 0,
					armourInc = bestForClass.config and bestForClass.config.armourInc or 0,
					evasionInc = bestForClass.config and bestForClass.config.evasionInc or 0,
					lifeLeech = bestForClass.config and bestForClass.config.lifeLeech or 0,
					manaEfficiency = bestForClass.config and bestForClass.config.manaEfficiency or 0,
					moveSpeed = bestForClass.config and bestForClass.config.moveSpeed or 0,
				},
			}
		end
	end

	local humanChallengers = { }
	if not skipHumanGauntlet then
		for idx = 1, #classOrder do
			local className = classOrder[idx].className
			local probeList = probesByClass[className]
			table.sort(probeList, function(a, b)
				return (a.robustScore or a.score or 0) > (b.robustScore or b.score or 0)
			end)

			for i = 1, m_min(humanAscendanciesPerClass, #probeList) do
				local humanCandidate = probeList[i]
				local optimizedHuman, err = optimizeHumanChallenger(
					build,
					snapshotXml,
					humanCandidate,
					humanGenerations,
					humanPopulation,
					humanElite
				)
				if not optimizedHuman then
					build:LoadDB(snapshotXml, build.buildName or "AI Battle Snapshot")
					build.calcsTab:BuildOutput()
					return nil, err
				end
				humanChallengers[#humanChallengers + 1] = {
					className = className,
					classId = optimizedHuman.classId,
					ascendClassId = optimizedHuman.ascendClassId,
					ascendClassName = optimizedHuman.ascendClassName,
					score = optimizedHuman.score,
					robustScore = optimizedHuman.robustScore,
					dps = optimizedHuman.dps,
					life = optimizedHuman.life,
					physicalMaximumHitTaken = optimizedHuman.physicalMaximumHitTaken,
					archetypeId = optimizedHuman.archetypeId,
					archetypeName = optimizedHuman.archetypeName,
					weaponBase = optimizedHuman.weaponBase,
					offhandBase = optimizedHuman.offhandBase,
					quality = optimizedHuman.quality,
				}
			end
		end
	end

	table.sort(humanChallengers, function(a, b)
		return (a.robustScore or a.score) > (b.robustScore or b.score)
	end)

	if #classBuilds == 0 then
		build:LoadDB(snapshotXml, build.buildName or "AI Battle Snapshot")
		build.calcsTab:BuildOutput()
		return nil, "Failed to optimize any class builds"
	end

	table.sort(classBuilds, function(a, b)
		return (a.robustScore or a.score) > (b.robustScore or b.score)
	end)

	local bestResult = classBuilds[1]

	local bestHuman = humanChallengers[1] or scoredHumans[1]
	local bestAi = bestResult

	local aiCmp = bestAi.robustScore or bestAi.score or 0
	local humanCmp = bestHuman and (bestHuman.robustScore or bestHuman.score) or 0
	local winner = (aiCmp > humanCmp) and "AI" or "HUMAN"
	local leadPercent
	if aiCmp <= 0 or humanCmp <= 0 then
		leadPercent = 0
	elseif winner == "AI" then
		leadPercent = ((aiCmp / humanCmp) - 1) * 100
	else
		leadPercent = ((humanCmp / aiCmp) - 1) * 100
	end

	local dominationIndex = aiCmp - humanCmp

	local report = {
		generatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		winner = winner,
		leadPercent = leadPercent,
		bestHuman = bestHuman,
		bestAI = bestAi,
		bestClass = {
			classId = bestAi.classId,
			className = bestAi.className,
			ascendClassId = bestAi.ascendClassId,
			ascendClassName = bestAi.ascendClassName,
		},
		bestLoadout = {
			archetypeId = bestAi.archetypeId,
			archetypeName = bestAi.archetypeName,
			weaponBase = bestAi.weaponBase,
			offhandBase = bestAi.offhandBase,
			skillGroup = bestAi.skillGroup,
			stats = bestAi.stats,
			quality = bestAi.quality,
		},
		dominationIndex = dominationIndex,
		benchmarkType = skipHumanGauntlet and "ai-vs-human-baseline" or "adversarial-human-gauntlet",
		humanGauntlet = {
			skipped = skipHumanGauntlet,
			generations = humanGenerations,
			population = humanPopulation,
			elite = humanElite,
			ascendanciesPerClass = humanAscendanciesPerClass,
			challengersEvaluated = #humanChallengers,
			bestChallenger = bestHuman,
		},
		classBuilds = classBuilds,
		classRankings = classBuilds,
		ascendancyCandidates = classProbes,
		humanChallengers = humanChallengers,
		humans = scoredHumans,
	}

	build:LoadDB(snapshotXml, build.buildName or "AI Battle Snapshot")
	build.calcsTab:BuildOutput()

	return report
end

function aiBattleLib:SaveReport(report, outPath)
	local _ = self
	local file = io.open(outPath, "w")
	if not file then
		return nil, "Could not write report to: " .. outPath
	end
	file:write(encodeJson(report))
	file:close()
	return true
end

local function lowerSafe(value)
	if type(value) ~= "string" then
		return ""
	end
	return value:lower()
end

local function addKeywords(out, keywords)
	if type(keywords) ~= "table" then
		return
	end
	for _, keyword in ipairs(keywords) do
		if type(keyword) == "string" and keyword ~= "" then
			table.insert(out, keyword:lower())
		end
	end
end

local function getPassiveKeywords(archetypeId, preferSpell)
	local keywords = {
		"maximum life",
		"elemental resistance",
		"all elemental resistances",
	}

	local byArchetype = {
		wand_spell = { "spell", "cast speed", "elemental damage", "lightning", "cold", "fire", "mana", "energy shield" },
		bow_crit = { "bow", "projectile", "attack speed", "critical", "critical strike", "evasion" },
		twohand_slam = { "two handed", "melee", "attack speed", "physical damage", "armour", "stun" },
		summoner_minion = { "minion", "minions", "mana", "energy shield", "curse", "aura" },
	}

	if preferSpell then
		addKeywords(keywords, { "spell", "cast speed", "mana", "energy shield", "elemental" })
	end

	addKeywords(keywords, byArchetype[archetypeId] or {})
	return keywords
end

local function scoreItemForSlot(item, slotName, archetypeId, preferSpell)
	local title = lowerSafe(item and item.title)
	local raw = lowerSafe(item and item.raw)
	local text = title .. "\n" .. raw
	if text == "\n" then
		return -math.huge
	end

	local score = 0

	local function scoreWords(words, weight)
		for _, word in ipairs(words) do
			if text:find(word, 1, true) then
				score = score + weight
			end
		end
	end

	if slotName == "Weapon 1" or slotName == "Weapon 2" then
		if archetypeId == "wand_spell" then
			scoreWords({ "wand", "staff", "sceptre", "focus", "spell", "cast speed", "energy shield", "mana", "elemental" }, 6)
		elseif archetypeId == "bow_crit" then
			scoreWords({ "bow", "quiver", "projectile", "attack speed", "critical" }, 6)
		elseif archetypeId == "twohand_slam" then
			scoreWords({ "mace", "axe", "staff", "two handed", "physical", "melee", "stun" }, 6)
		elseif archetypeId == "summoner_minion" then
			scoreWords({ "sceptre", "wand", "staff", "minion", "spell", "mana", "energy shield" }, 6)
		end
	elseif slotName == "Helmet" or slotName == "Body Armour" or slotName == "Gloves" or slotName == "Boots" then
		scoreWords({
			"maximum life",
			"all elemental resistances",
			"elemental resistance",
			"armour",
			"evasion",
			"energy shield",
		}, 3)
		if preferSpell or archetypeId == "wand_spell" or archetypeId == "summoner_minion" then
			scoreWords({ "mana", "energy shield", "cast speed", "spell" }, 2)
		end
	elseif slotName == "Amulet" or slotName == "Ring 1" or slotName == "Ring 2" or slotName == "Ring 3" then
		scoreWords({ "maximum life", "elemental resistance", "all elemental resistances", "attributes" }, 3)
		if preferSpell or archetypeId == "wand_spell" or archetypeId == "summoner_minion" then
			scoreWords({ "spell", "cast speed", "mana", "energy shield", "intelligence" }, 3)
		else
			scoreWords({ "attack speed", "physical", "critical", "dexterity", "strength" }, 2)
		end
	elseif slotName == "Belt" then
		scoreWords({ "maximum life", "all elemental resistances", "elemental resistance", "strength", "armour" }, 4)
	elseif slotName == "Flask 1" or slotName == "Flask 2" then
		scoreWords({ "life", "mana", "charges", "recovery" }, 4)
	elseif slotName == "Charm 1" or slotName == "Charm 2" or slotName == "Charm 3" then
		scoreWords({ "resistance", "life", "energy shield", "duration" }, 3)
	elseif slotName == "Arm 1" or slotName == "Arm 2" or slotName == "Leg 1" or slotName == "Leg 2" then
		scoreWords({ "armour", "evasion", "energy shield", "life", "resistance" }, 3)
	end

	return score
end

local function getNowMs()
	if type(_G.GetTime) == "function" then
		return _G.GetTime()
	end
	return math.floor(os.clock() * 1000)
end

function aiBattleLib:ApplyBestBuild(build, report)
	local _ = self
	local applyStartMs = getNowMs()
	local itemBudgetMs = 900
	local passiveBudgetMs = 900
	local maxItemChecksPerSlot = 220
	local maxPassiveCandidates = 240
	local maxPassiveAttempts = 120
	local summary = {
		itemsEquipped = 0,
		skillsAdded = 0,
		nodesAllocated = 0,
	}

	if not build or not report then
		return summary
	end

	local bestClass = report.bestClass or {}
	local bestLoadout = report.bestLoadout or {}
	local preferSpell = report.profile and report.profile.preferSpell
	local archetypeId = bestLoadout.archetypeId or "wand_spell"
	local archetype = getArchetypeById(archetypeId)

	local spec = build.spec
	if spec and bestClass.classId then
		pcall(function()
			spec:SelectClass(bestClass.classId)
			if bestClass.ascendClassId then
				spec:SelectAscendClass(bestClass.ascendClassId)
			end
		end)
	end

	local itemsTab = build.itemsTab
	local appMain = _G.main
	if itemsTab and itemsTab.activeItemSet and appMain and appMain.itemDB and appMain.itemDB.list then
		local slotOrder = {
			"Weapon 1",
			"Weapon 2",
			"Helmet",
			"Body Armour",
			"Gloves",
			"Boots",
			"Amulet",
			"Ring 1",
			"Ring 2",
			"Ring 3",
			"Belt",
			"Charm 1",
			"Charm 2",
			"Charm 3",
			"Flask 1",
			"Flask 2",
			"Arm 1",
			"Arm 2",
			"Leg 1",
			"Leg 2",
		}

		local usedItemIds = {}
		for _, slotName in ipairs(slotOrder) do
			if getNowMs() - applyStartMs > itemBudgetMs then
				break
			end
			if itemsTab.activeItemSet[slotName] then
				local bestItem
				local bestScore = -math.huge
				local checks = 0

				for _, item in ipairs(appMain.itemDB.list) do
					if checks >= maxItemChecksPerSlot then
						break
					end
					if getNowMs() - applyStartMs > itemBudgetMs then
						break
					end
					if item and item.id and not usedItemIds[item.id] then
						checks = checks + 1
						local isValid = false
						pcall(function()
							isValid = itemsTab:IsItemValidForSlot(item, slotName, itemsTab.activeItemSet)
						end)
						if isValid then
							local score = scoreItemForSlot(item, slotName, archetypeId, preferSpell)
							if score > bestScore then
								bestScore = score
								bestItem = item
							end
						end
					end
				end

				if bestItem then
					local equipped = false
					if itemsTab.slots and itemsTab.slots[slotName] and itemsTab.slots[slotName].SetSelItemId then
						pcall(function()
							itemsTab.slots[slotName]:SetSelItemId(bestItem.id)
							equipped = true
						end)
					end
					if not equipped then
						itemsTab.activeItemSet[slotName].selItemId = bestItem.id
						equipped = true
					end
					if equipped then
						usedItemIds[bestItem.id] = true
						summary.itemsEquipped = summary.itemsEquipped + 1
					end
				end
			end
		end
	end

	local skillsTab = build.skillsTab
	if skillsTab then
		local before = skillsTab.socketGroupList and #skillsTab.socketGroupList or 0
		local groupsToTry = {}
		if type(bestLoadout.skillGroup) == "string" and bestLoadout.skillGroup ~= "" then
			table.insert(groupsToTry, bestLoadout.skillGroup)
		end
		if archetype
			and type(archetype.skillGroup) == "string"
			and archetype.skillGroup ~= ""
			and archetype.skillGroup ~= bestLoadout.skillGroup then
			table.insert(groupsToTry, archetype.skillGroup)
		end
		if preferSpell then
			table.insert(groupsToTry, "Storm Wave\nArcane Tempo\nControlled Destruction")
			table.insert(groupsToTry, "Spark\nArcane Tempo\nPersistence")
			table.insert(groupsToTry, "Fireball\nArcane Tempo\nConcentrated Effect")
		end

		for _, skillGroup in ipairs(groupsToTry) do
			pcall(function()
				skillsTab:PasteSocketGroup(skillGroup)
			end)
		end

		local after = skillsTab.socketGroupList and #skillsTab.socketGroupList or before
		summary.skillsAdded = math.max(0, after - before)
	end

	if spec and spec.nodes then
		pcall(function()
			spec:ResetNodes()
			if bestClass.classId and not spec:IsClassConnected(bestClass.classId) then
				spec:ConnectToClass(bestClass.classId)
			end
			if bestClass.classId then
				spec:SelectClass(bestClass.classId)
			end
			if bestClass.ascendClassId then
				spec:SelectAscendClass(bestClass.ascendClassId)
			end
		end)

		local targetNodes = 30
		if report.profile and type(report.profile.nodesToAllocate) == "number" then
			targetNodes = math.max(10, math.min(80, math.floor(report.profile.nodesToAllocate)))
		end

		local keywords = getPassiveKeywords(archetypeId, preferSpell)
		local candidates = {}
		for _, node in pairs(spec.nodes) do
			if #candidates >= maxPassiveCandidates then
				break
			end
			if getNowMs() - applyStartMs > (itemBudgetMs + passiveBudgetMs) then
				break
			end
			if node
				and node.id
				and node.sd
				and not node.alloc
				and not node.ascendancyName
				and node.type ~= "ClassStart"
				and node.type ~= "AscendClassStart" then
				local nodeText = lowerSafe(node.sd)
				local nodeScore = 0
				for _, keyword in ipairs(keywords) do
					if nodeText:find(keyword, 1, true) then
						nodeScore = nodeScore + 2
					end
				end
				if node.type == "Notable" then
					nodeScore = nodeScore + 3
				elseif node.type == "Keystone" then
					nodeScore = nodeScore + 2
				end
				if nodeScore > 0 then
					table.insert(candidates, { node = node, score = nodeScore })
				end
			end
		end

		table.sort(candidates, function(a, b)
			return a.score > b.score
		end)

		local passiveAttempts = 0
		for _, entry in ipairs(candidates) do
			if summary.nodesAllocated >= targetNodes then
				break
			end
			if passiveAttempts >= maxPassiveAttempts then
				break
			end
			if getNowMs() - applyStartMs > (itemBudgetMs + passiveBudgetMs) then
				break
			end
			passiveAttempts = passiveAttempts + 1
			local allocated = false
			pcall(function()
				allocated = spec:AllocNode(entry.node)
			end)
			if allocated then
				summary.nodesAllocated = summary.nodesAllocated + 1
			end
		end
	end

	build.buildFlag = true
	if build.calcsTab then
		pcall(function()
			build.calcsTab:BuildOutput()
		end)
	end

	return summary
end
