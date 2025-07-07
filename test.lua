local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

local EnemiesFolder = workspace:WaitForChild("Game"):WaitForChild("Enemies")

-- Danh sách tower định hướng
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

-- Skip 2 tower đặc biệt
local skipTowerTypes = {
	["Helicopter"] = true,
	["Cryo Helicopter"] = true,
}

-- Gửi skill
local function SendSkill(hash, index, pos)
	if useFireServer then
		TowerUseAbilityRequest:FireServer(hash, index, pos)
	else
		TowerUseAbilityRequest:InvokeServer(hash, index, pos)
	end
end

-- Lấy enemy đầu tiên
local function GetFirstEnemyPosition()
	for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
		if enemy:IsA("BasePart") and enemy.Name ~= "Arrow" then
			return enemy.Position
		end
	end
	return nil
end

-- Lấy vị trí tower
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

-- Lấy range
local function getRange(tower)
	local ok, r = pcall(function() return TowerClass.GetCurrentRange(tower) end)
	if ok and typeof(r) == "number" then
		return r
	elseif tower.Stats and tower.Stats.Radius then
		return tower.Stats.Radius * 4
	end
	return 0
end

-- Kiểm tra enemy trong range
local function hasEnemyInRange(tower)
	local towerPos = getTowerPos(tower)
	local range = getRange(tower)
	if not towerPos or range <= 0 then return false end
	for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
		if enemy:IsA("BasePart") then
			local dist = (enemy.Position - towerPos).Magnitude
			if dist <= range then
				return true
			end
		end
	end
	return false
end

-- Lấy cấp nâng path 1,2
local function GetCurrentUpgradeLevels(tower)
	if not tower or not tower.LevelHandler then return 0, 0 end
	local p1, p2 = 0, 0
	pcall(function() p1 = tower.LevelHandler:GetLevelOnPath(1) or 0 end)
	pcall(function() p2 = tower.LevelHandler:GetLevelOnPath(2) or 0 end)
	return p1, p2
end

-- Kiểm tra có thể dùng
local function CanUseAbility(ability)
	if not ability then return false end
	if ability.Passive or ability.CustomTriggered then return false end
	if ability.CooldownRemaining > 0 then return false end
	if ability.Stunned or ability.Disabled or ability.Converted then return false end
	local ok, can = pcall(function() return ability:CanUse(true) end)
	return ok and can
end

-- Commander skill 1/2
local function ShouldProcessNonDirectionalSkill(tower, index)
	return tower.Type == "Commander" and index ~= 3
end

-- MAIN
RunService.Heartbeat:Connect(function()
	for hash, tower in pairs(TowerClass.GetTowers() or {}) do
		if not tower or not tower.AbilityHandler then continue end
		if skipTowerTypes[tower.Type] then continue end

		local towerType = tower.Type
		local directionalInfo = directionalTowerTypes[towerType]
		local p1, p2 = GetCurrentUpgradeLevels(tower)

		local range = getRange(tower)
		local hasEnemy = hasEnemyInRange(tower)
		local enemyPos = GetFirstEnemyPosition()

		for index = 1, 3 do
			pcall(function()
				local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
				if not CanUseAbility(ability) then return end

				local allow = true

				if towerType == "Ice Breaker" and index == 1 then
					-- Skill 1 tự do
				elseif towerType == "Ice Breaker" and index ~= 1 then
					if not hasEnemy then allow = false end
				elseif towerType == "Slammer" then
					if not hasEnemy then allow = false end
				elseif towerType == "John" then
					if p1 >= 5 then
						allow = hasEnemy
					elseif p2 >= 5 then
						allow = (range >= 4.5 and hasEnemy)
					else
						allow = (range >= 4.5 and hasEnemy)
					end
				elseif towerType == "Mobster" or towerType == "Golden Mobster" then
					if p1 >= 4 and p1 <= 5 then
						allow = hasEnemy
					elseif p2 >= 3 and p2 <= 5 then
						allow = true
					else
						allow = false
					end
				end

				if allow then
					local sendPos = nil
					if typeof(directionalInfo) == "table" and directionalInfo.onlyAbilityIndex then
						if index == directionalInfo.onlyAbilityIndex then
							sendPos = enemyPos
						elseif ShouldProcessNonDirectionalSkill(tower, index) then
							sendPos = nil
						else
							return
						end
					elseif directionalInfo then
						sendPos = enemyPos
					end
					SendSkill(hash, index, sendPos)
					task.wait(0.25)
				end
			end)
		end
	end
end)
