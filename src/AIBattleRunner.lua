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

local function addItem(raw)
	build.itemsTab:CreateDisplayItemFromRaw(raw)
	build.itemsTab:AddDisplayItem()
end

local function addSkillSetup()
	build.skillsTab:PasteSocketGroup("Lightning Arrow 20/0  1\nMartial Tempo 20/0  1\n")
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
Heavy Bow
%d%% increased attack damage
%d%% increased Critical Damage Bonus
]], cfg.attackDamageInc, cfg.critBonus))

	addItem(string.format([[
New Item
Ring
+%d to maximum life
]], cfg.flatLife))

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

	local score = dps + (life * 120) + (physMaxHit * 80)

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
}

local function joinMods(mods)
	if #mods == 0 then
		return ""
	end
	return table.concat(mods, "\n")
end

local function randomCustomMods()
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
		attackDamageInc = math.random(10, 220),
		critBonus = math.random(20, 260),
		flatLife = math.random(10, 180),
		customMods = randomCustomMods(),
	}
end

local function crossoverCandidate(a, b)
	return {
		attackDamageInc = (math.random() < 0.5) and a.attackDamageInc or b.attackDamageInc,
		critBonus = (math.random() < 0.5) and a.critBonus or b.critBonus,
		flatLife = (math.random() < 0.5) and a.flatLife or b.flatLife,
		customMods = (math.random() < 0.5) and a.customMods or b.customMods,
	}
end

local function mutateCandidate(parent)
	local nextCfg = clone(parent)
	nextCfg.attackDamageInc = clamp(nextCfg.attackDamageInc + math.random(-18, 18), 10, 240)
	nextCfg.critBonus = clamp(nextCfg.critBonus + math.random(-24, 24), 20, 280)
	nextCfg.flatLife = clamp(nextCfg.flatLife + math.random(-14, 14), 10, 220)
	if math.random() < 0.2 then
		nextCfg.customMods = randomCustomMods()
	end
	return nextCfg
end

local function runEvolution()
	local generations = tonumber(os.getenv("POB2_AI_GENERATIONS")) or 8
	local populationSize = tonumber(os.getenv("POB2_AI_POPULATION")) or 24
	local eliteSize = tonumber(os.getenv("POB2_AI_ELITES")) or 6

	if eliteSize > populationSize then
		eliteSize = populationSize
	end

	local population = {}
	for i = 1, populationSize do
		population[i] = randomCandidate()
	end

	local bestResult = nil

	for g = 1, generations do
		print(string.format("[AIBattleRunner] Generation %d/%d", g, generations))
		local scored = {}
		for i = 1, #population do
			scored[i] = evaluateBuild("ai_g" .. g .. "_" .. i, population[i])
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
	winner = winner,
	leadPercent = leadPercent,
	bestHuman = bestHuman,
	bestAI = bestAi,
	humans = scoredHumans,
}

local root = "../.."
local outPath = root .. "/poe2/public/data/ai-build-battle-pob2.json"
local file = io.open(outPath, "w")
if file then
	file:write(encodeJson(report))
	file:close()
	print("Saved report: " .. outPath)
else
	print("Could not write report to: " .. outPath)
end
