-- 📦 Auto Skill Debug - Ice Breaker (debug riêng Ice Breaker)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts")

local TowerClass = require(PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")
local useFireServer = TowerUseAbilityRequest:IsA("RemoteEvent")
local EnemiesFolder = workspace:WaitForChild("Game"):WaitForChild("Enemies")

local function SendSkill(hash, index, pos)
	if useFireServer then
		TowerUseAbilityRequest:FireServer(hash, index, pos)
	else
		TowerUseAbilityRequest:InvokeServer(hash, index, pos)
	end
end

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

local function hasEnemyInStuds(tower, studsLimit)
	local pos = getTowerPos(tower)
	if not pos then return false end
	for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
		if enemy:IsA("BasePart") then
			local dist = (enemy.Position - pos).Magnitude
			if dist <= studsLimit then
				print(string.format("[🎯 Ice Breaker] Enemy phát hiện ở %.2f studs (<= %.2f)", dist, studsLimit))
				return true
			end
		end
	end
	return false
end

local function CanUseAbility(ability)
	if not ability then return false end
	if ability.Passive or ability.CustomTriggered or ability.Stunned or ability.Disabled or ability.Converted then return false end
	if ability.CooldownRemaining > 0 then return false end
	local ok, usable = pcall(function() return ability:CanUse(true) end)
	return ok and usable
end

-- 🔁 Main chỉ xử lý Ice Breaker
RunService.Heartbeat:Connect(function()
	for hash, tower in pairs(TowerClass.GetTowers() or {}) do
		if not tower or not tower.AbilityHandler then continue end
		if tower.Type ~= "Ice Breaker" then continue end

		for index = 1, 3 do
			pcall(function()
				local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
				if not CanUseAbility(ability) then return end

				local allowUse = false
				if index == 1 then
					allowUse = true
					print("[⚡ Ice Breaker] Skill 1 luôn dùng được")
				elseif index == 2 then
					allowUse = hasEnemyInStuds(tower, 8)
					if not allowUse then
						warn("[⛔ Ice Breaker] Không có enemy trong 8 studs → KHÔNG dùng Skill 2")
					else
						print("[⚡ Ice Breaker] Skill 2 được dùng vì enemy trong 8 studs")
					end
				else
					warn("[⛔ Ice Breaker] Skill", index, "không được hỗ trợ hoặc bị tắt")
				end

				if allowUse then
					local pos = GetFirstEnemyPosition()
					SendSkill(hash, index, pos)
					task.wait(0.25)
				end
			end)
		end
	end
end)
