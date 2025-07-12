local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local EnemyClass = require(PlayerScripts.Client.GameClass:WaitForChild("EnemyClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")
local EnemiesFolder = workspace:WaitForChild("Game"):WaitForChild("Enemies")

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

local lastUsedTime = {}
local mobsterUsedEnemies = {}

local function SendSkill(hash, index, pos)
	if useFireServer then
		TowerUseAbilityRequest:FireServer(hash, index, pos)
	else
		TowerUseAbilityRequest:InvokeServer(hash, index, pos)
	end
end

local function GetAliveEnemies()
	local result = {}
	for _, e in pairs(EnemyClass.GetEnemies()) do
		if e and e.IsAlive and not e.IsFakeEnemy then
			table.insert(result, e)
		end
	end
	return result
end

local function getTowerPos(tower)
	if tower.GetPosition then
		local ok, pos = pcall(function() return tower:GetPosition() end)
		if ok then return pos end
	end
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

local function getNearestEnemy(towerPos, range)
	for _, enemy in pairs(GetAliveEnemies()) do
		if enemy and enemy.GetPosition then
			local pos = enemy:GetPosition()
			if (pos - towerPos).Magnitude <= range and enemy.Type ~= "Arrow" then
				return pos
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

	for _, enemy in pairs(GetAliveEnemies()) do
		if enemy.IsAirUnit then continue end
		local ePos = enemy:GetPosition()
		if (ePos - pos).Magnitude <= range and enemy.HealthHandler then
			local id = tostring(enemy)
			if path == 2 and mobsterUsedEnemies[hash] and mobsterUsedEnemies[hash][id] then
				continue
			end
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
	local alive = GetAliveEnemies()

	for i = #alive, 1, -1 do
		if alive[i].IsAirUnit or alive[i].Type == "Arrow" then
			table.remove(alive, i)
		end
	end

	if #alive == 0 then return nil end

	table.sort(alive, function(a, b)
		return (a.HealthHandler:GetMaxHealth() or 0) > (b.HealthHandler:GetMaxHealth() or 0)
	end)

	if math.random(1, 10) <= 6 then
		return alive[1]:GetPosition()
	else
		return alive[math.random(1, #alive)]:GetPosition()
	end
end

local function GetCurrentUpgradeLevels(tower)
	if not tower or not tower.LevelHandler then return 0, 0 end
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
	for hash, tower in pairs(TowerClass.GetTowers() or {}) do
		if not tower or not tower.AbilityHandler then continue end
		local towerType = tower.Type
		if skipTowerTypes[towerType] then continue end

		local delay = fastTowers[towerType] and 0.1 or 0.2
		if lastUsedTime[hash] and now - lastUsedTime[hash] < delay then
			continue
		end
		lastUsedTime[hash] = now

		local p1, p2 = GetCurrentUpgradeLevels(tower)
		local directionalInfo = directionalTowerTypes[towerType]

		for index = 1, 3 do
			pcall(function()
				local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
				if not CanUseAbility(ability) then return end

				local allowUse = true
				local pos = nil

				-- ✅ Logic đặc biệt
				if towerType == "Ghost" then
					local maxHP = -1
					for _, enemy in pairs(GetAliveEnemies()) do
						if enemy.Type ~= "Arrow" and enemy.HealthHandler then
							local hp = enemy.HealthHandler:GetMaxHealth()
							if hp > maxHP then
								maxHP = hp
								pos = enemy:GetPosition()
							end
						end
					end
					if not pos then return end
					SendSkill(hash, index, pos)
					return
				end

				if towerType == "Ice Breaker" then
					allowUse = (index == 1) or (index == 2 and getNearestEnemy(getTowerPos(tower), 8))
				elseif towerType == "Slammer" then
					allowUse = getNearestEnemy(getTowerPos(tower), getRange(tower)) ~= nil
				elseif towerType == "John" then
					allowUse = (p1 >= 5 and getNearestEnemy(getTowerPos(tower), getRange(tower))) or getNearestEnemy(getTowerPos(tower), 4.5)
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

				if not pos and allowUse then
					if towerType == "Commander" and index == 3 then
						pos = getCommanderTarget()
					else
						pos = getNearestEnemy(getTowerPos(tower), getRange(tower))
					end
					if not pos then return end
				end

				local sendWithPos = false
				if typeof(directionalInfo) == "table" and directionalInfo.onlyAbilityIndex then
					sendWithPos = index == directionalInfo.onlyAbilityIndex
				elseif directionalInfo then
					sendWithPos = true
				end

				if sendWithPos and pos then
					SendSkill(hash, index, pos)
				elseif not sendWithPos then
					SendSkill(hash, index)
				end
			end)
		end
	end
end)
