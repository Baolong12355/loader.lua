local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

local EnemiesFolder = workspace:WaitForChild("Game"):WaitForChild("Enemies")

-- 🟨 Các tower bị bỏ qua
local skipTowerTypes = {
    ["Farm"] = true, ["Relic"] = true, ["Scarecrow"] = true,
    ["Helicopter"] = true, ["Cryo Helicopter"] = true,
    ["Combat Drone"] = true, ["AA Turret"] = true, ["XWM Turret"] = true,
    ["Barracks"] = true, ["Cryo Blaster"] = true, ["Grenadier"] = true,
    ["Juggernaut"] = true, ["Machine Gunner"] = true, ["Zed"] = true,
    ["Troll Tower"] = true, ["Missile Trooper"] = true, ["Patrol Boat"] = true,
    ["Railgunner"] = true, ["Mine Layer"] = true, ["Sentry"] = true,
    ["Commander"] = true, -- xử lý riêng
    ["Toxicnator"] = true, ["Ghost"] = true, ["Ice Breaker"] = true,
    ["Mobster"] = true, ["Golden Mobster"] = true, ["Artillery"] = true,
    ["EDJ"] = false, ["Accelerator"] = true, ["Engineer"] = true
}

-- 🟥 Tower định hướng
local directionalTowerTypes = {
    ["Commander"] = { onlyAbilityIndex = 3 },
    ["Toxicnator"] = true, ["Ghost"] = true, ["Ice Breaker"] = true,
    ["Mobster"] = true, ["Golden Mobster"] = true,
    ["Artillery"] = true, ["Golden Mine Layer"] = true
}

-- ✅ Hàm phụ trợ
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
	local ok, result = pcall(function() return TowerClass.GetCurrentRange(tower) end)
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
	local p1, p2 = 0, 0
	pcall(function() p1 = tower.LevelHandler:GetLevelOnPath(1) or 0 end)
	pcall(function() p2 = tower.LevelHandler:GetLevelOnPath(2) or 0 end)
	return p1, p2
end

local function CanUseAbility(ability)
	return ability and not ability.Passive and not ability.CustomTriggered
		and ability.CooldownRemaining <= 0 and not ability.Stunned
		and not ability.Disabled and not ability.Converted and ability:CanUse(true)
end

-- ✅ Skill thường cho commander
local function ShouldProcessNonDirectionalSkill(tower, abilityIndex)
	return tower.Type == "Commander" and abilityIndex ~= 3
		and tower.HealthHandler and tower.HealthHandler:GetHealth() > 0
		and tower.AbilityHandler
end

-- 🔁 Loop chính
RunService.Heartbeat:Connect(function()
	for hash, tower in pairs(TowerClass.GetTowers() or {}) do
		local towerType = tower.Type
		local directionalInfo = directionalTowerTypes[towerType]
		local p1, p2 = GetCurrentUpgradeLevels(tower)

		if skipTowerTypes[towerType] and towerType ~= "Commander" then
			continue
		end

		for abilityIndex = 1, 3 do
			pcall(function()
				local ability = tower.AbilityHandler and tower.AbilityHandler:GetAbilityFromIndex(abilityIndex)
				if not CanUseAbility(ability) then return end

				local allowUse = true

				if towerType == "Ice Breaker" and abilityIndex == 1 then
					print("[✔️ Ice Breaker] skill 1 dùng tự do")
				elseif towerType == "Slammer" then
					allowUse = hasEnemyInRange(tower)
					if not allowUse then print("[⛔ Slammer] Không có enemy trong range") end
				elseif towerType == "John" then
					if p1 >= 5 then
						allowUse = hasEnemyInRange(tower)
					elseif p2 >= 5 then
						local r = getRange(tower)
						allowUse = (r >= 4.5 and hasEnemyInRange(tower))
					else
						local r = getRange(tower)
						allowUse = (r >= 4.5 and hasEnemyInRange(tower))
					end
					print("[John] P1:", p1, "| P2:", p2, "| Use:", allowUse)
				elseif towerType == "Mobster" or towerType == "Golden Mobster" then
					if p1 >= 4 and p1 <= 5 then
						allowUse = hasEnemyInRange(tower)
						print("[🔫 "..towerType.."] P1:", p1, "InRange:", allowUse)
					elseif p2 >= 3 and p2 <= 5 then
						allowUse = true
						print("[🎯 "..towerType.."] P2:", p2, "Skill định hướng")
					else
						allowUse = false
						print("[❌ "..towerType.."] Không đủ điều kiện path")
					end
				end

				if allowUse then
					local enemyPos = GetFirstEnemyPosition()

					if typeof(directionalInfo) == "table" and directionalInfo.onlyAbilityIndex then
						if abilityIndex == directionalInfo.onlyAbilityIndex then
							if enemyPos then
								print("[🎯 Commander] dùng skill 3 định hướng")
								TowerUseAbilityRequest:FireServer(hash, abilityIndex, enemyPos)
								task.wait(0.25)
							end
						elseif ShouldProcessNonDirectionalSkill(tower, abilityIndex) then
							print("[🧱 Commander] skill thường được xử lý")
							TowerUseAbilityRequest:FireServer(hash, abilityIndex)
							task.wait(0.25)
						end
					elseif directionalInfo then
						if enemyPos then
							print("[🔥 "..towerType.."] skill định hướng:", abilityIndex)
							TowerUseAbilityRequest:FireServer(hash, abilityIndex, enemyPos)
							task.wait(0.25)
						end
					else
						print("[⚡ "..towerType.."] skill thường:", abilityIndex)
						TowerUseAbilityRequest:FireServer(hash, abilityIndex)
						task.wait(0.25)
					end
				end
			end)
		end
	end
end)
