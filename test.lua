local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

local EnemiesFolder = workspace:WaitForChild("Game"):WaitForChild("Enemies")

-- ✅ Tower định hướng
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

-- ✅ Gửi skill
local function SendSkill(hash, index, pos)
	if useFireServer then
		TowerUseAbilityRequest:FireServer(hash, index, pos)
	else
		TowerUseAbilityRequest:InvokeServer(hash, index, pos)
	end
end

-- ✅ Lấy enemy gần nhất
local function GetFirstEnemyPosition()
	for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
		if enemy:IsA("BasePart") and enemy.Name ~= "Arrow" then
			return enemy.Position
		end
	end
	return nil
end

-- ✅ Lấy vị trí tower
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

-- ✅ Lấy range
local function getRange(tower)
	local ok, result = pcall(function() return TowerClass.GetCurrentRange(tower) end)
	if ok and typeof(result) == "number" then
		return result
	elseif tower.Stats and tower.Stats.Radius then
		return tower.Stats.Radius * 4
	end
	return 0
end

-- ✅ Kiểm tra enemy trong range
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

-- ✅ Lấy cấp độ nâng cấp
local function GetCurrentUpgradeLevels(tower)
	if not tower or not tower.LevelHandler then return 0, 0 end
	local p1, p2 = 0, 0
	pcall(function() p1 = tower.LevelHandler:GetLevelOnPath(1) or 0 end)
	pcall(function() p2 = tower.LevelHandler:GetLevelOnPath(2) or 0 end)
	return p1, p2
end

-- ✅ Kiểm tra khả năng dùng skill
local function CanUseAbility(ability)
	if not ability then return false end
	if ability.Passive or ability.CustomTriggered then return false end
	if ability.CooldownRemaining > 0 or ability.Stunned or ability.Disabled or ability.Converted then return false end
	local ok, can = pcall(function() return ability:CanUse(true) end)
	return ok and can
end

-- ✅ Commander skill 1,2 là thường
local function ShouldProcessNonDirectionalSkill(tower, index)
	return tower.Type == "Commander" and index ~= 3
end

-- 🔁 Main loop
RunService.Heartbeat:Connect(function()
	for hash, tower in pairs(TowerClass.GetTowers() or {}) do
		if not tower or not tower.AbilityHandler then continue end

		local towerType = tower.Type
		local directionalInfo = directionalTowerTypes[towerType]
		local p1, p2 = GetCurrentUpgradeLevels(tower)

		for index = 1, 3 do
			pcall(function()
				local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
				if not CanUseAbility(ability) then return end

				local allowUse = true
				local enemyInRange = hasEnemyInRange(tower)
				local range = getRange(tower)

				-- 🎯 Logic đặc biệt
				if towerType == "Ice Breaker" then
					if index == 1 then
						-- skill 1 tự do
					else
						if not enemyInRange then
							allowUse = false
							warn("[Ice Breaker] Skill " .. index .. " không có enemy trong range")
						end
					end
				elseif towerType == "Slammer" then
					if not enemyInRange then
						allowUse = false
						warn("[Slammer] Không có enemy trong range")
					end
				elseif towerType == "John" then
					if p1 >= 5 then
						allowUse = enemyInRange
					elseif p2 >= 5 then
						allowUse = range >= 4.5 and enemyInRange
					else
						allowUse = range >= 4.5 and enemyInRange
					end
				elseif towerType == "Mobster" or towerType == "Golden Mobster" then
					if p1 >= 4 and p1 <= 5 then
						allowUse = enemyInRange
					elseif p2 >= 3 and p2 <= 5 then
						allowUse = true
					else
						allowUse = false
					end
				else
					-- Các tower định hướng khác (trừ commander skill 1,2) cần enemy
					if directionalInfo and not ShouldProcessNonDirectionalSkill(tower, index) and not enemyInRange then
						allowUse = false
					end
				end

				-- 📤 Kích hoạt skill nếu hợp lệ
				if allowUse then
					local pos = GetFirstEnemyPosition()
					if not pos then return end

					print("[Kích hoạt]", towerType, "→ Skill", index)
					SendSkill(hash, index, pos)
					task.wait(0.25)
				end
			end)
		end
	end
end)
