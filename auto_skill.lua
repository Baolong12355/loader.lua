-- Phần đầu không thay đổi
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
local mobsterUsedTargets = {} -- [towerHash][enemyHash] = true

local function cleanupMobsterUsedTargets()
	for towerHash, enemyMap in pairs(mobsterUsedTargets) do
		for enemyHash, _ in pairs(enemyMap) do
			local enemy = EnemyClass.GetEnemies()[enemyHash]
			if not enemy or not enemy:IsAlive() then
				mobsterUsedTargets[towerHash][enemyHash] = nil
			end
		end
	end
end

local function SendSkill(hash, index, pos)
	if useFireServer then
		TowerUseAbilityRequest:FireServer(hash, index, pos)
	else
		TowerUseAbilityRequest:InvokeServer(hash, index, pos)
	end
end

local function getTowerPos(tower)
	if tower.GetPosition then
		local ok, result = pcall(function() return tower:GetPosition() end)
		if ok then return result end
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

local function hasEnemyInRange(tower, studsLimit)
	local towerPos = getTowerPos(tower)
	local range = studsLimit or getRange(tower)
	if not towerPos or range <= 0 then return false end
	for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
		if enemy:IsA("BasePart") and enemy.Name ~= "Arrow" and (enemy.Position - towerPos).Magnitude <= range then
			return true
		end
	end
	return false
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

local function ShouldProcessNonDirectionalSkill(tower, index)
	return tower.Type == "Commander" and index ~= 3
end

local function getValidEnemiesInRange(tower)
	local result = {}
	local pos = getTowerPos(tower)
	local range = getRange(tower)
	if not pos then return result end

	local enemies = EnemyClass.GetEnemies()
	for hash, enemy in pairs(enemies) do
		if enemy and enemy.GetPosition and enemy.HealthHandler and enemy:IsAlive() and not enemy.IsAirUnit then
			local enemyPos = enemy:GetPosition()
			if (enemyPos - pos).Magnitude <= range then
				table.insert(result, { obj = enemy, hash = hash })
			end
		end
	end
	return result
end

local function findStrongestEnemy(tower, hash)
	local all = getValidEnemiesInRange(tower)
	local used = mobsterUsedTargets[hash] or {}
	local maxHP = -1
	local target = nil
	for _, info in ipairs(all) do
		if not used[info.hash] then
			local ok1, hp = pcall(function() return info.obj.HealthHandler:GetMaxHealth() end)
			if ok1 and hp > maxHP then
				maxHP = hp
				target = info
			end
		end
	end
	return target
end

RunService.Heartbeat:Connect(function()
	cleanupMobsterUsedTargets()

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

		local directionalInfo = directionalTowerTypes[towerType]
		local p1, p2 = GetCurrentUpgradeLevels(tower)

		for index = 1, 3 do
			pcall(function()
				local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
				if not CanUseAbility(ability) then return end

				local allowUse = true
				local skillTargetPos = nil
				local usedEnemyHash = nil

				if towerType == "Ice Breaker" then
					if index == 1 then
						allowUse = true
					elseif index == 2 then
						allowUse = hasEnemyInRange(tower, 8)
					else
						allowUse = false
					end
				elseif towerType == "Slammer" then
					allowUse = hasEnemyInRange(tower)
				elseif towerType == "John" then
					if p1 >= 5 then
						allowUse = hasEnemyInRange(tower)
					elseif p2 >= 5 then
						allowUse = hasEnemyInRange(tower, 4.5)
					else
						allowUse = hasEnemyInRange(tower, 4.5)
					end
				elseif towerType == "Mobster" or towerType == "Golden Mobster" then
					if p2 >= 3 and p2 <= 5 then
						local target = findStrongestEnemy(tower, hash)
						if target then
							allowUse = true
							skillTargetPos = target.obj:GetPosition()
							usedEnemyHash = target.hash
						else
							allowUse = false
						end
					elseif p1 >= 4 and p1 <= 5 then
						allowUse = hasEnemyInRange(tower)
					else
						allowUse = false
					end
				end

				if allowUse then
					local sendWithPos = false
					local finalPos = skillTargetPos

					if towerType == "Commander" and index == 3 then
						local enemies = getValidEnemiesInRange(tower)
						if #enemies > 0 then
							table.sort(enemies, function(a, b)
								local ha = a.obj.HealthHandler:GetMaxHealth()
								local hb = b.obj.HealthHandler:GetMaxHealth()
								return ha > hb
							end)
							if math.random() <= 0.6 then
								finalPos = enemies[1].obj:GetPosition()
							else
								finalPos = enemies[math.random(1, #enemies)].obj:GetPosition()
							end
						end
					end

					if typeof(directionalInfo) == "table" and directionalInfo.onlyAbilityIndex then
						if index == directionalInfo.onlyAbilityIndex then
							sendWithPos = true
						elseif ShouldProcessNonDirectionalSkill(tower, index) then
							sendWithPos = false
						else
							return
						end
					elseif directionalInfo then
						sendWithPos = true
					end

					if sendWithPos and finalPos then
						SendSkill(hash, index, finalPos)
						if usedEnemyHash then
							mobsterUsedTargets[hash] = mobsterUsedTargets[hash] or {}
							mobsterUsedTargets[hash][usedEnemyHash] = true
						end
					elseif not sendWithPos then
						SendSkill(hash, index)
					end
				end
			end)
		end
	end
end)
