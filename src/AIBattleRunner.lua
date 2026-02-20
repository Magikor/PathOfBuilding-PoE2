-- Headless AI vs Human battle runner for PathOfBuilding-PoE2
-- Run from this directory with: luajit AIBattleRunner.lua

dofile("HeadlessWrapper.lua")

local build = assert(_G.build, "HeadlessWrapper failed to initialize build")
local newBuild = assert(_G.newBuild, "HeadlessWrapper failed to expose newBuild")
local runCallback = assert(_G.runCallback, "HeadlessWrapper failed to expose runCallback")

if build.importTab and build.importTab.api and type(build.importTab.api.ValidateAuth) == "function" then
	build.importTab.api.ValidateAuth = function(_, callback)
		if callback then
			callback(true, false)
		end
	end
end

math.randomseed(os.time())

local REALISTIC_MODE = os.getenv("POB2_AI_REALISTIC_MODE") == "1"

local function envNumber(name)
	local raw = os.getenv(name)
	if not raw then
		return nil
	end
	return tonumber(raw)
end

local DPS_WEIGHT = tonumber(os.getenv("POB2_AI_DPS_WEIGHT")) or 90
local LIFE_WEIGHT = tonumber(os.getenv("POB2_AI_LIFE_WEIGHT")) or 35
local HIT_WEIGHT = tonumber(os.getenv("POB2_AI_HIT_WEIGHT")) or 20
local MIN_LIFE_FLOOR = tonumber(os.getenv("POB2_AI_MIN_LIFE")) or 150
local MIN_HIT_FLOOR = tonumber(os.getenv("POB2_AI_MIN_MAXHIT")) or 150
local LIFE_FLOOR_PENALTY = tonumber(os.getenv("POB2_AI_LIFE_PENALTY")) or 100
local HIT_FLOOR_PENALTY = tonumber(os.getenv("POB2_AI_HIT_PENALTY")) or 80
local SPELL_DAMAGE_MAX = envNumber("POB2_AI_MAX_SPELL_DAMAGE") or (REALISTIC_MODE and 240 or 420)
local ELEMENTAL_DAMAGE_MAX = envNumber("POB2_AI_MAX_ELEMENTAL_DAMAGE") or (REALISTIC_MODE and 220 or 420)
local CRIT_BONUS_MAX = envNumber("POB2_AI_MAX_CRIT_BONUS") or (REALISTIC_MODE and 280 or 520)
local LIFE_MAX = envNumber("POB2_AI_MAX_LIFE") or (REALISTIC_MODE and 220 or 320)
local MANA_MAX = envNumber("POB2_AI_MAX_MANA") or (REALISTIC_MODE and 220 or 360)

local SPELL_DAMAGE_MIN = REALISTIC_MODE and 15 or 30
local ELEMENTAL_DAMAGE_MIN = REALISTIC_MODE and 10 or 20
local CRIT_BONUS_MIN = REALISTIC_MODE and 20 or 40
local LIFE_MIN = REALISTIC_MODE and 20 or 20
local MANA_MIN = REALISTIC_MODE and 20 or 20

local function addItem(raw)
	build.itemsTab:CreateDisplayItemFromRaw(raw)
	build.itemsTab:AddDisplayItem()
end

local function addSkillSetup()
	build.skillsTab:PasteSocketGroup("Spark 20/0  1\n")
end

local function pickDps(output)
	local best = 0
	for key, value in pairs(output or {}) do
		if type(value) == "number" and key:find("DPS") and value > best then
			best = value
		end
	end
	return best
end

local function evaluateBuild(label, cfg)
	newBuild()

	addItem(string.format([[
New Item
Withered Wand
%d%% increased spell damage
%d%% increased Critical Damage Bonus
]], cfg.spellDamageInc, cfg.critBonus))

	addItem(string.format([[
New Item
Ring
+%d to maximum life
]], cfg.flatLife))

	addItem(string.format([[
New Item
Twig Focus
%d%% increased Elemental Damage
+%d to maximum Mana
]], cfg.elementalDamageInc, cfg.flatMana))

	if cfg.customMods and #cfg.customMods > 0 then
		build.configTab.input.customMods = cfg.customMods
		build.configTab:BuildModList()
	end

	addSkillSetup()
	runCallback("OnFrame")

	local output = build.calcsTab.mainOutput or {}
	local calcsOutput = build.calcsTab.calcsOutput or {}

	local dps = pickDps(output)
	local life = output.Life or 0
	local physMaxHit = calcsOutput.PhysicalMaximumHitTaken or 0

	local lifePenalty = 0
	if life < MIN_LIFE_FLOOR then
		lifePenalty = (MIN_LIFE_FLOOR - life) * LIFE_FLOOR_PENALTY
	end

	local hitPenalty = 0
	if physMaxHit < MIN_HIT_FLOOR then
		hitPenalty = (MIN_HIT_FLOOR - physMaxHit) * HIT_FLOOR_PENALTY
	end

	local score = (dps * DPS_WEIGHT) + (life * LIFE_WEIGHT) + (physMaxHit * HIT_WEIGHT) - lifePenalty - hitPenalty

	return {
		label = label,
		dps = dps,
		life = life,
		physicalMaximumHitTaken = physMaxHit,
		score = score,
		config = cfg,
	}
end

local function clone(tbl)
	local out = {}
	for k, v in pairs(tbl) do
		out[k] = v
	end
	return out
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local humanBaselines = {
	{
		label = "human_noob",
		spellDamageInc = 20,
		elementalDamageInc = 20,
		critBonus = 25,
		flatLife = 20,
		flatMana = 20,
		customMods = "",
	},
	{
		label = "human_mid",
		spellDamageInc = 80,
		elementalDamageInc = 70,
		critBonus = 90,
		flatLife = 60,
		flatMana = 60,
		customMods = "+20% to all elemental resistances",
	},
	{
		label = "human_endgame",
		spellDamageInc = 160,
		elementalDamageInc = 140,
		critBonus = 180,
		flatLife = 120,
		flatMana = 120,
		customMods = "+60% to all elemental resistances\n+20% to chaos resistance",
	},
}

local availableCustomMods = {
	"+20% to all elemental resistances",
	"+20% to chaos resistance",
	"10% increased Movement Speed",
	"10% increased Cast Speed",
	"20% increased Spell Damage",
	"20% increased Lightning Damage",
	"20% increased Critical Hit Chance for Spells",
	"15% increased Mana Regeneration Rate",
}

local realisticOffensiveMods = {
	"10% increased Cast Speed",
	"20% increased Spell Damage",
	"20% increased Lightning Damage",
	"20% increased Critical Hit Chance for Spells",
}

local realisticUtilityMods = {
	"+20% to all elemental resistances",
	"+20% to chaos resistance",
	"10% increased Movement Speed",
	"15% increased Mana Regeneration Rate",
}

local function joinMods(mods)
	if #mods == 0 then
		return ""
	end
	return table.concat(mods, "\n")
end

local function randomCustomMods()
	if REALISTIC_MODE then
		local selected = {}
		if math.random() < 0.6 then
			selected[#selected + 1] = realisticOffensiveMods[math.random(1, #realisticOffensiveMods)]
		end
		if math.random() < 0.55 then
			selected[#selected + 1] = realisticUtilityMods[math.random(1, #realisticUtilityMods)]
		end
		if #selected == 0 and math.random() < 0.35 then
			if math.random() < 0.5 then
				selected[1] = realisticOffensiveMods[math.random(1, #realisticOffensiveMods)]
			else
				selected[1] = realisticUtilityMods[math.random(1, #realisticUtilityMods)]
			end
		end
		return joinMods(selected)
	end

	local selected = {}
	for i = 1, #availableCustomMods do
		if math.random() < 0.33 then
			selected[#selected + 1] = availableCustomMods[i]
		end
	end
	if #selected == 0 and math.random() < 0.4 then
		selected[1] = availableCustomMods[math.random(1, #availableCustomMods)]
	end
	return joinMods(selected)
end

local function randomCandidate()
	return {
		spellDamageInc = math.random(SPELL_DAMAGE_MIN, SPELL_DAMAGE_MAX),
		elementalDamageInc = math.random(ELEMENTAL_DAMAGE_MIN, ELEMENTAL_DAMAGE_MAX),
		critBonus = math.random(CRIT_BONUS_MIN, CRIT_BONUS_MAX),
		flatLife = math.random(LIFE_MIN, LIFE_MAX),
		flatMana = math.random(MANA_MIN, MANA_MAX),
		customMods = randomCustomMods(),
	}
end

local function crossoverCandidate(a, b)
	return {
		spellDamageInc = (math.random() < 0.5) and a.spellDamageInc or b.spellDamageInc,
		elementalDamageInc = (math.random() < 0.5) and a.elementalDamageInc or b.elementalDamageInc,
		critBonus = (math.random() < 0.5) and a.critBonus or b.critBonus,
		flatLife = (math.random() < 0.5) and a.flatLife or b.flatLife,
		flatMana = (math.random() < 0.5) and a.flatMana or b.flatMana,
		customMods = (math.random() < 0.5) and a.customMods or b.customMods,
	}
end

local function mutateCandidate(parent)
	local nextCfg = clone(parent)
	local statDelta = REALISTIC_MODE and 22 or 40
	local critDelta = REALISTIC_MODE and 26 or 50
	local lifeDelta = REALISTIC_MODE and 16 or 28
	local manaDelta = REALISTIC_MODE and 18 or 30
	nextCfg.spellDamageInc = clamp(nextCfg.spellDamageInc + math.random(-statDelta, statDelta), SPELL_DAMAGE_MIN, SPELL_DAMAGE_MAX)
	nextCfg.elementalDamageInc = clamp(nextCfg.elementalDamageInc + math.random(-statDelta, statDelta), ELEMENTAL_DAMAGE_MIN, ELEMENTAL_DAMAGE_MAX)
	nextCfg.critBonus = clamp(nextCfg.critBonus + math.random(-critDelta, critDelta), CRIT_BONUS_MIN, CRIT_BONUS_MAX)
	nextCfg.flatLife = clamp(nextCfg.flatLife + math.random(-lifeDelta, lifeDelta), LIFE_MIN, LIFE_MAX)
	nextCfg.flatMana = clamp(nextCfg.flatMana + math.random(-manaDelta, manaDelta), MANA_MIN, MANA_MAX)
	if math.random() < 0.2 then
		nextCfg.customMods = randomCustomMods()
	end
	return nextCfg
end

local function runEvolutionAttempt(generations, populationSize, eliteSize, attemptLabel)
	print(string.format("[AIBattleRunner] Evolution attempt %s", attemptLabel))

	local population = {}
	for i = 1, populationSize do
		population[i] = randomCandidate()
	end

	local bestResult = nil

	for g = 1, generations do
		print(string.format("[AIBattleRunner] Generation %d/%d", g, generations))
		local scored = {}
		for i = 1, #population do
			scored[i] = evaluateBuild("ai_" .. attemptLabel .. "_g" .. g .. "_" .. i, population[i])
		end

		table.sort(scored, function(a, b)
			return a.score > b.score
		end)

		if not bestResult or scored[1].score > bestResult.score then
			bestResult = scored[1]
		end

		local nextPopulation = {}
		for i = 1, eliteSize do
			nextPopulation[i] = clone(scored[i].config)
		end

		while #nextPopulation < populationSize do
			local parentA = scored[math.random(1, eliteSize)].config
			local parentB = scored[math.random(1, eliteSize)].config
			local child = crossoverCandidate(parentA, parentB)
			nextPopulation[#nextPopulation + 1] = mutateCandidate(child)
		end

		population = nextPopulation
	end

	return bestResult
end

local function runEvolution()
	local generations = tonumber(os.getenv("POB2_AI_GENERATIONS")) or 8
	local populationSize = tonumber(os.getenv("POB2_AI_POPULATION")) or 24
	local eliteSize = tonumber(os.getenv("POB2_AI_ELITES")) or 6
	local restarts = tonumber(os.getenv("POB2_AI_RESTARTS")) or 3

	if eliteSize > populationSize then
		eliteSize = populationSize
	end
	if restarts < 1 then
		restarts = 1
	end

	local bestResult = nil
	for attempt = 1, restarts do
		local candidate = runEvolutionAttempt(generations, populationSize, eliteSize, tostring(attempt))
		if candidate and (not bestResult or candidate.score > bestResult.score) then
			bestResult = candidate
		end
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
			local parts = {}
			for i = 1, maxIndex do
				parts[#parts + 1] = encodeJson(value[i])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, v in pairs(value) do
			parts[#parts + 1] = '"' .. jsonEscape(k) .. '":' .. encodeJson(v)
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

local scoredHumans = {}
for i = 1, #humanBaselines do
	local human = humanBaselines[i]
	scoredHumans[i] = evaluateBuild(human.label, human)
end

table.sort(scoredHumans, function(a, b)
	return a.score > b.score
end)

local bestHuman = scoredHumans[1]
local bestAi = runEvolution()

local winner = (bestAi.score > bestHuman.score) and "AI" or "HUMAN"
local leadPercent
if bestAi.score <= 0 or bestHuman.score <= 0 then
	leadPercent = 0
elseif winner == "AI" then
	leadPercent = ((bestAi.score / bestHuman.score) - 1) * 100
else
	leadPercent = ((bestHuman.score / bestAi.score) - 1) * 100
end

print("=== POB2 HEADLESS AI vs HUMAN BATTLE ===")
print(string.format("Best Human Score (%s): %.2f", bestHuman.label, bestHuman.score))
print(string.format("Best AI Score (%s): %.2f", bestAi.label, bestAi.score))
print(string.format("Winner: %s by %.2f%%", winner, leadPercent))
print(
	string.format(
		"Human DPS/Life/MaxHit: %.2f / %.2f / %.2f",
		bestHuman.dps,
		bestHuman.life,
		bestHuman.physicalMaximumHitTaken
	)
)
print(
	string.format(
		"AI DPS/Life/MaxHit: %.2f / %.2f / %.2f",
		bestAi.dps,
		bestAi.life,
		bestAi.physicalMaximumHitTaken
	)
)

local report = {
	generatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	realisticMode = REALISTIC_MODE,
	constraints = {
		spellDamageMax = SPELL_DAMAGE_MAX,
		elementalDamageMax = ELEMENTAL_DAMAGE_MAX,
		critBonusMax = CRIT_BONUS_MAX,
		lifeMax = LIFE_MAX,
		manaMax = MANA_MAX,
	},
	winner = winner,
	leadPercent = leadPercent,
	bestHuman = bestHuman,
	bestAI = bestAi,
	humans = scoredHumans,
}

local root = "../.."
local outputPaths = {
	root .. "/poe2/public/data/ai-build-battle-pob2.json",
	"Builds/ai-build-battle-pob2.json",
}

for i = 1, #outputPaths do
	local outPath = outputPaths[i]
	local file = io.open(outPath, "w")
	if file then
		file:write(encodeJson(report))
		file:close()
		print("Saved report: " .. outPath)
	else
		print("Could not write report to: " .. outPath)
	end
end
