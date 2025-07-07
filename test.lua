local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

local EnemiesFolder = workspace:WaitForChild("Game"):WaitForChild("Enemies")

-- 🟥 Tower định hướng
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

-- ❌ Tower cần bỏ qua (không có kỹ năng hoặc phụ thuộc người chơi)
local skipTowerTypes = {
	["Helicopter"] = true,
	["Cryo Helicopter"] = true
}

-- 📤 Gửi kỹ năng
local function SendSkill(hash, index, pos)
	if useFireServer then
		TowerUseAbilityRequest:FireServer(hash, index, pos)
	else
		TowerUseAbilityRequest:InvokeServer(hash, index, pos)
	end
end

-- 🔍 Enemy gần nhất
local function GetFirstEnemyPosition()
	for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
		if enemy:IsA("BasePart") and enemy.Name ~= "Arrow" then
			return enemy.Position
		end
	end
	return nil
end

-- 📌 Vị trí tower
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

-- 📏 Lấy phạm vi tower
local function getRange(tower)
	local ok, result = pcall(function() return TowerClass.GetCurrentRange(tower) end)
	if ok and typeof(result) == "number" then
		return result
	elseif tower.Stats and tower.Stats.Radius then
		return tower.Stats.Radius * 4
	end
	return 0
end

-- 👁️‍🗨️ Có enemy trong phạm vi?
local function hasEnemyInRange(tower)
	local towerPos = getTowerPos(tower)
	local range = getRange(tower)
	if not towerPos or range <= 0 then return false end
	for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
		if enemy:IsA("BasePart") and (enemy.Position - towerPos).Magnitude <= range then
			return true
		end
	end
	return false
end

-- 📶 Lấy cấp độ path
local function GetCurrentUpgradeLevels(tower)
	if not tower or not tower.LevelHandler then return 0, 0 end
	local p1, p2 = 0, 0
	pcall(function() p1 = tower.LevelHandler:GetLevelOnPath(1) or 0 end)
	pcall(function() p2 = tower.LevelHandler:GetLevelOnPath(2) or 0 end)
	return p1, p2
end

-- ✅ Dùng được kỹ năng?
local function CanUseAbility(ability)
	if not ability then return false end
	if ability.Passive or ability.CustomTriggered then return false end
	if ability.CooldownRemaining > 0 or ability.Stunned or ability.Disabled or ability.Converted then return false end
	local ok, can = pcall(function() return ability:CanUse(true) end)
	return ok and can
end

-- Commander skill thường
local function ShouldProcessNonDirectionalSkill(tower, index)
	return tower.Type == "Commander" and index ~= 3
end

-- 🔁 Vòng lặp chính
RunService.Heartbeat:Connect(function()
	for hash, tower in pairs(TowerClass.GetTowers() or {}) do
		if not tower or not tower.AbilityHandler then continue end
		if skipTowerTypes[tower.Type] then continue end

		local towerType = tower.Type
		local directionalInfo = directionalTowerTypes[towerType]
		local p1, p2 = GetCurrentUpgradeLevels(tower)

		for index = 1, 3 do
			pcall(function()
				local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
				if not CanUseAbility(ability) then return end

				local allowUse = true

				-- ⚙️ Điều kiện đặc biệt
				if towerType == "Ice Breaker" and index == 1 then
					-- skill 1 luôn dùng được
				elseif towerType == "Slammer" then
					allowUse = hasEnemyInRange(tower)
				elseif towerType == "John" then
					local range = getRange(tower)
					if p1 >= 5 then
						allowUse = hasEnemyInRange(tower)
					elseif p2 >= 5 then
						allowUse = range >= 4.5 and hasEnemyInRange(tower)
					else
						allowUse = range >= 4.5 and hasEnemyInRange(tower)
					end
				elseif towerType == "Mobster" or towerType == "Golden Mobster" then
					if p1 >= 4 and p1 <= 5 then
						allowUse = hasEnemyInRange(tower)
					elseif p2 >= 3 and p2 <= 5 then
						allowUse = true
					else
						allowUse = false
					end
				end

				if allowUse then
					local pos = GetFirstEnemyPosition()
					local sendWithPos = false

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

					SendSkill(hash, index, sendWithPos and pos or nil)
					task.wait(0.25)
				end
			end)
		end
	end
end)
