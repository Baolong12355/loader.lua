local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local EnemyClass = require(PlayerScripts.Client.GameClass:WaitForChild("EnemyClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

-- tower config
local directionalTowerTypes = {
	["Commander"] = { onlyAbilityIndex = 3 },
	["Toxicnator"] = true,
	["Ghost"] = true,
	["Ice Breaker"] = true,
	["Mobster"] = true,
	["Golden Mobster"] = true,
	["Artillery"] = true,
	["Golden Mine Layer"] = true
}

local skipTowerTypes = {
	["Helicopter"] = true,
	["Cryo Helicopter"] = true,
	["Medic"] = true,
	["Combat Drone"] = true
}

local fastTowers = {
	["Ice Breaker"] = true,
	["John"] = true,
	["Slammer"] = true,
	["Mobster"] = true,
	["Golden Mobster"] = true
}

local skipAirTowers = {
	["Ice Breaker"] = true,
	["John"] = true,
	["Slammer"] = true,
	["Mobster"] = true,
	["Golden Mobster"] = true
}

local lastUsedTime = {}
local mobsterUsedEnemies = {}
local cooldownCache = {}

-- enemy cache
local enemyCache = {}
task.spawn(function()
	while true do
		enemyCache = {}
		for _, e in pairs(EnemyClass.GetEnemies()) do
			if e and e.IsAlive and not e.IsFakeEnemy then
				table.insert(enemyCache, e)
			end
		end
		task.wait(0.1)
	end
end)

local function SendSkill(hash, index, pos)
	if useFireServer then
		TowerUseAbilityRequest:FireServer(hash, index, pos)
	else
		TowerUseAbilityRequest:InvokeServer(hash, index, pos)
	end
end

local function getTowerPos(tower)
	local ok, pos = pcall(function() return tower:GetPosition() end)
	if ok then return pos end
	if tower.Model and tower.Model:FindFirstChild("Root") then
		return tower.Model.Root.Position
	end
	return nil
end

local function getRange(tower)
	local ok, result = pcall(function() return TowerClass.GetCurrentRange(tower) end)
	if ok and typeof(result) == "number" then
		return result
	elseif tower.Stats and tower.Stats.Radius then
		return tower.Stats.Radius * 4
	end
	return 0
end

local function getNearestEnemy(pos, range, towerType)
	for _, enemy in ipairs(enemyCache) do
		if enemy.Type ~= "Arrow" and enemy.GetPosition then
			if skipAirTowers[towerType] and enemy.IsAirUnit then continue end
			local ePos = enemy:GetPosition()
			if (ePos - pos).Magnitude <= range then
				return ePos
			end
		end
	end
	return nil
end

local function getMobsterTarget(tower, hash, path)
	local pos = getTowerPos(tower)
	local range = getRange(tower)
	local maxHP = -1
	local chosen = nil
	for _, enemy in ipairs(enemyCache) do
		if enemy.IsAirUnit then continue end
		local id = tostring(enemy)
		if path == 2 and mobsterUsedEnemies[hash] and mobsterUsedEnemies[hash][id] then continue end
		local ePos = enemy:GetPosition()
		if (ePos - pos).Magnitude <= range and enemy.HealthHandler then
			local hp = enemy.HealthHandler:GetMaxHealth()
			if hp > maxHP then
				maxHP = hp
				chosen = enemy
			end
		end
	end
	if chosen and path == 2 then
		mobsterUsedEnemies[hash] = mobsterUsedEnemies[hash] or {}
		mobsterUsedEnemies[hash][tostring(chosen)] = true
	end
	return chosen and chosen:GetPosition() or nil
end

local function getCommanderTarget()
	local list = {}
	for _, e in ipairs(enemyCache) do
		if not e.IsAirUnit and e.Type ~= "Arrow" then table.insert(list, e) end
	end
	if #list == 0 then return nil end
	table.sort(list, function(a, b)
		return (a.HealthHandler:GetMaxHealth() or 0) > (b.HealthHandler:GetMaxHealth() or 0)
	end)
	if math.random(1, 10) <= 6 then
		return list[1]:GetPosition()
	else
		return list[math.random(1, #list)]:GetPosition()
	end
end

local function GetCurrentUpgradeLevels(tower)
	local p1, p2 = 0, 0
	pcall(function() p1 = tower.LevelHandler:GetLevelOnPath(1) or 0 end)
	pcall(function() p2 = tower.LevelHandler:GetLevelOnPath(2) or 0 end)
	return p1, p2
end

local function CanUseAbility(ability)
	if not ability then return false end
	if ability.Passive or ability.CustomTriggered or ability.Stunned or ability.Disabled or ability.Converted then return false end
	if ability.CooldownRemaining > 0 then return false end
	local ok, usable = pcall(function() return ability:CanUse(true) end)
	return ok and usable
end

RunService.Heartbeat:Connect(function()
	local now = tick()
	if #enemyCache == 0 then return end
	for hash, tower in pairs(TowerClass.GetTowers() or {}) do
		if not tower or not tower.AbilityHandler then continue end
		local towerType = tower.Type
		if skipTowerTypes[towerType] then continue end

		local delay = fastTowers[towerType] and 0.1 or 0.2
		if lastUsedTime[hash] and now - lastUsedTime[hash] < delay then continue end
		lastUsedTime[hash] = now

		local p1, p2 = GetCurrentUpgradeLevels(tower)
		local towerPos = getTowerPos(tower)
		local towerRange = getRange(tower)

		for index = 1, 3 do
			pcall(function()
				local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
				if not ability then return end

				cooldownCache[hash] = cooldownCache[hash] or {}
				local cdEnd = cooldownCache[hash][index]
				if cdEnd and now < cdEnd then return end

				if not CanUseAbility(ability) then return end
				cooldownCache[hash][index] = now + (ability.Cooldown or 0)

				local pos = nil
				local allowUse = true

				if towerType == "Ghost" then
					local maxHP = -1
					for _, e in ipairs(enemyCache) do
						if e.Type ~= "Arrow" and e.HealthHandler then
							local hp = e.HealthHandler:GetMaxHealth()
							if hp > maxHP then
								maxHP = hp
								pos = e:GetPosition()
							end
						end
					end
					if pos then SendSkill(hash, index, pos) end
					return
				end

				if towerType == "Ice Breaker" then
					allowUse = index == 1 or (index == 2 and getNearestEnemy(towerPos, 8, towerType))
				elseif towerType == "Slammer" then
					allowUse = getNearestEnemy(towerPos, towerRange, towerType) ~= nil
				elseif towerType == "John" then
					allowUse = (p1 >= 5 and getNearestEnemy(towerPos, towerRange, towerType)) or getNearestEnemy(towerPos, 4.5, towerType)
				elseif towerType == "Mobster" or towerType == "Golden Mobster" then
					if p2 >= 3 and p2 <= 5 then
						pos = getMobsterTarget(tower, hash, 2)
						if not pos then return end
					elseif p1 >= 4 and p1 <= 5 then
						pos = getMobsterTarget(tower, hash, 1)
						if not pos then return end
					else
						allowUse = false
					end
				end

				if towerType == "Commander" and index == 3 then
					pos = getCommanderTarget()
					if not pos then return end
				end

				local directional = directionalTowerTypes[towerType]
				local sendWithPos = typeof(directional) == "table" and directional.onlyAbilityIndex == index or directional == true

				if not pos and sendWithPos then
					pos = getNearestEnemy(towerPos, towerRange, towerType)
					if not pos then return end
				end

				if allowUse then
					if sendWithPos then
						SendSkill(hash, index, pos)
					else
						SendSkill(hash, index)
					end
				end
			end)
		end
	end
end)
