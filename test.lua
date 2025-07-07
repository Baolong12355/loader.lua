-- 📦 Auto-Skill PRO với cấp độ và điều kiện phạm vi chuẩn

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")

local EnemiesFolder = workspace:WaitForChild("Game"):WaitForChild("Enemies")

local skipTowerTypes = {
	["Farm"] = true, ["Relic"] = true, ["Scarecrow"] = true,
	["Helicopter"] = true, ["Cryo Helicopter"] = true, ["Combat Drone"] = true,
	["AA Turret"] = true, ["XWM Turret"] = true, ["Barracks"] = true,
	["Cryo Blaster"] = true, ["Grenadier"] = true, ["Juggernaut"] = true,
	["Machine Gunner"] = true, ["Zed"] = true, ["Troll Tower"] = true,
	["Missile Trooper"] = true, ["Patrol Boat"] = true, ["Railgunner"] = true,
	["Mine Layer"] = true, ["Sentry"] = true, ["Commander"] = true,
	["Toxicnator"] = true, ["Ghost"] = true, ["Ice Breaker"] = true,
	["Mobster"] = true, ["Golden Mobster"] = true, ["Artillery"] = true,
	["EDJ"] = false, ["Accelerator"] = true, ["Engineer"] = true
}

local directionalTowerTypes = {
	["Commander"] = { onlyAbilityIndex = 3 },
	["Toxicnator"] = true, ["Ghost"] = true, ["Ice Breaker"] = true,
	["Mobster"] = true, ["Golden Mobster"] = true,
	["Artillery"] = true, ["Golden Mine Layer"] = true
}

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
	if ok and typeof(result) == "number" then return result end
	if tower.Stats and tower.Stats.Radius then
		return tower.Stats.Radius * 4
	end
	return 0
end

local function hasEnemyInRange(tower)
	local pos = getTowerPos(tower)
	local range = getRange(tower)
	if not pos or range <= 0 then return false end
	for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
		if enemy:IsA("BasePart") and (enemy.Position - pos).Magnitude <= range then
			return true
		end
	end
	return false
end

local function GetPathLevels(tower)
	local p1, p2 = 0, 0
	pcall(function()
		p1 = tower.LevelHandler:GetLevelOnPath(1)
	end)
	pcall(function()
		p2 = tower.LevelHandler:GetLevelOnPath(2)
	end)
	return p1, p2
end

local function CanUseAbility(ability)
	return ability and not ability.Passive and not ability.CustomTriggered and
		ability.CooldownRemaining <= 0 and not ability.Stunned and
		not ability.Disabled and not ability.Converted and ability:CanUse(true)
end

local function ShouldProcessTower(tower)
	return tower and not tower.Destroyed and tower.HealthHandler and
		tower.HealthHandler:GetHealth() > 0 and
		not skipTowerTypes[tower.Type] and tower.AbilityHandler
end

local function ShouldProcessNonDirectionalSkill(tower, index)
	return tower.Type == "Commander" and index ~= 3 and
		tower.HealthHandler and tower.HealthHandler:GetHealth() > 0 and tower.AbilityHandler
end

local function GetFirstEnemyPosition()
	for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
		if enemy:IsA("BasePart") and enemy.Name ~= "Arrow" then
			return enemy.Position
		end
	end
	return nil
end

-- 🔁 MAIN LOOP
RunService.Heartbeat:Connect(function()
	for hash, tower in pairs(TowerClass.GetTowers() or {}) do
		local tType = tower.Type
		local dirInfo = directionalTowerTypes[tType]
		local p1, p2 = GetPathLevels(tower)

		if dirInfo and tower.AbilityHandler then
			for i = 1, 3 do
				pcall(function()
					local skill = tower.AbilityHandler:GetAbilityFromIndex(i)
					if not CanUseAbility(skill) then return end

					if tType == "Ice Breaker" and i == 1 then
						-- không check
					elseif tType == "Slammer" and not hasEnemyInRange(tower) then
						return
					elseif tType == "John" then
						if p1 >= 5 then
							if not hasEnemyInRange(tower) then return end
						elseif p2 >= 5 then
							if getRange(tower) < 4.5 or not hasEnemyInRange(tower) then return end
						else
							if getRange(tower) < 4.5 or not hasEnemyInRange(tower) then return end
						end
					elseif tType == "Mobster" or tType == "Golden Mobster" then
						if p1 >= 4 and p1 <= 5 then
							if not hasEnemyInRange(tower) then return end
						elseif p2 >= 3 and p2 <= 5 then
							-- dùng luôn
						else return end
					end

					local pos = GetFirstEnemyPosition()
					if not pos then return end

					if typeof(dirInfo) == "table" and dirInfo.onlyAbilityIndex then
						if i == dirInfo.onlyAbilityIndex then
							TowerUseAbilityRequest:FireServer(hash, i, pos)
							task.wait(0.25)
							return
						elseif ShouldProcessNonDirectionalSkill(tower, i) then
							TowerUseAbilityRequest:FireServer(hash, i)
							task.wait(0.25)
						end
					else
						TowerUseAbilityRequest:FireServer(hash, i, pos)
						task.wait(0.25)
						return
					end
				end)
			end
		elseif ShouldProcessTower(tower) then
			for i = 1, 3 do
				pcall(function()
					local skill = tower.AbilityHandler:GetAbilityFromIndex(i)
					if CanUseAbility(skill) then
						TowerUseAbilityRequest:FireServer(hash, i)
						task.wait(0.25)
					end
				end)
			end
		end
	end
end)
