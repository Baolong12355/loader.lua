local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
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

local function GetFirstEnemyPosition()
	for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
		if enemy:IsA("BasePart") and enemy.Name ~= "Arrow" then
			return enemy.Position
		end
	end
	return nil
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
	local ok, result = pcall(function()
		return TowerClass.GetCurrentRange(tower)
	end)
	if ok and typeof(result) == "number" then
		return result
	elseif tower.Stats and tower.Stats.Radius then
		return tower.Stats.Radius * 4
	end
	return 0
end

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

local function GetCurrentUpgradeLevels(tower)
	if not tower or not tower.LevelHandler then return 0, 0 end
	local p1 = 0
	local p2 = 0
	pcall(function()
		p1 = tower.LevelHandler:GetLevelOnPath(1) or 0
	end)
	pcall(function()
		p2 = tower.LevelHandler:GetLevelOnPath(2) or 0
	end)
	return p1, p2
end

local function CanUseAbility(ability)
	return ability and
		not ability.Passive and
		not ability.CustomTriggered and
		ability.CooldownRemaining <= 0 and
		not ability.Stunned and
		not ability.Disabled and
		not ability.Converted and
		ability:CanUse(true)
end

-- 🔁 Main loop
RunService.Heartbeat:Connect(function()
	for hash, tower in pairs(TowerClass.GetTowers() or {}) do
		local towerType = tower.Type
		local directionalInfo = directionalTowerTypes[towerType]
		local p1, p2 = GetCurrentUpgradeLevels(tower)

		for abilityIndex = 1, 3 do
			pcall(function()
				local ability = tower.AbilityHandler and tower.AbilityHandler:GetAbilityFromIndex(abilityIndex)
				if not CanUseAbility(ability) then return end

				local allowUse = true

				if towerType == "Ice Breaker" and abilityIndex == 1 then
					print("[✔️ Ice Breaker] skill 1 dùng tự do")
				elseif towerType == "Slammer" then
					if not hasEnemyInRange(tower) then
						print("[⛔ Slammer] Không có enemy trong range")
						allowUse = false
					end
				elseif towerType == "John" then
					if p1 >= 5 then
						allowUse = hasEnemyInRange(tower)
						print("[🔍 John] Path1:", p1, " | In range:", allowUse)
					elseif p2 >= 5 then
						local r = getRange(tower)
						allowUse = (r >= 4.5 and hasEnemyInRange(tower))
						print("[🔍 John] Path2:", p2, " | Range:", r, " | Use:", allowUse)
					else
						local r = getRange(tower)
						allowUse = (r >= 4.5 and hasEnemyInRange(tower))
						print("[🔍 John] Thấp hơn cấp | Range:", r, " | Use:", allowUse)
					end
				elseif towerType == "Mobster" or towerType == "Golden Mobster" then
					if p1 >= 4 and p1 <= 5 then
						allowUse = hasEnemyInRange(tower)
						print("[🔫 " .. towerType .. "] Path1:", p1, " | In range:", allowUse)
					elseif p2 >= 3 and p2 <= 5 then
						print("[🎯 " .. towerType .. "] Path2:", p2, " | Xử lý skill định hướng")
						allowUse = true
					else
						print("[❌ " .. towerType .. "] Không đạt điều kiện path")
						allowUse = false
					end
				end

				if allowUse then
					if directionalInfo then
						local pos = GetFirstEnemyPosition()
						if pos then
							print("[🔥 Dùng skill định hướng] Tower:", towerType, " | Skill:", abilityIndex)
							TowerUseAbilityRequest:FireServer(hash, abilityIndex, pos)
						end
					else
						print("[⚡ Dùng skill thường] Tower:", towerType, " | Skill:", abilityIndex)
						TowerUseAbilityRequest:FireServer(hash, abilityIndex)
					end
					task.wait(0.25)
				end
			end)
		end
	end
end)
