repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Safe require
local function SafeRequire(module)
	local success, result = pcall(require, module)
	return success and result or nil
end

local function LoadTowerClass()
	local ps = player:WaitForChild("PlayerScripts")
	local client = ps:WaitForChild("Client")
	local gameClass = client:WaitForChild("GameClass")
	local towerModule = gameClass:WaitForChild("TowerClass")
	return SafeRequire(towerModule)
end

local TowerClass = LoadTowerClass()
if not TowerClass then error("Không thể tải TowerClass") end

-- Get tower theo X
local function GetTowerByAxis(axisX)
	for hash, tower in pairs(TowerClass.GetTowers()) do
		local model = tower.Character and tower.Character:GetCharacterModel()
		local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
		if root and math.abs(root.Position.X - axisX) <= 1 then
			local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
			if hp and hp > 0 then
				return hash, tower
			end
		end
	end
	return nil, nil
end

-- Chờ đủ tiền
local function WaitForCash(amount)
	while cashStat.Value < amount do task.wait(0.1) end
end

-- Đặt tower
local function PlaceTowerRetry(args, axisX, towerName)
	while true do
		Remotes.PlaceTower:InvokeServer(unpack(args))
		task.wait(0.15)
		local hash, tower = GetTowerByAxis(axisX)
		if hash and tower then return true end
		warn("[Place Retry] Thử lại đặt:", towerName)
	end
end

-- Nâng cấp đúng 1 lần
local function UpgradeTowerRetry(axisX, upgradePath)
	while true do
		local hash, tower = GetTowerByAxis(axisX)
		if not (hash and tower and tower.LevelHandler) then break end

		local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
		if not hp or hp <= 0 then break end

		local lvlBefore = tower.LevelHandler:GetLevelOnPath(upgradePath)
		local maxLvl = tower.LevelHandler:GetMaxLevel()
		if lvlBefore >= maxLvl then break end

		local success, cost = pcall(function()
			return tower.LevelHandler:GetLevelUpgradeCost(upgradePath, lvlBefore)
		end)
		if not (success and cost) then break end

		WaitForCash(cost)
		Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)

		local t0 = tick()
		while tick() - t0 < 1.5 do
			task.wait(0.1)
			local _, newTower = GetTowerByAxis(axisX)
			if newTower and newTower.LevelHandler then
				local lvlAfter = newTower.LevelHandler:GetLevelOnPath(upgradePath)
				if lvlAfter > lvlBefore then
					return -- Nâng thành công
				end
			end
		end
		warn("[Upgrade Retry] Thử lại nâng cấp")
	end
end

-- Bán tower
local function SellTowerRetry(axisX)
	while true do
		local hash = GetTowerByAxis(axisX)
		if hash then
			Remotes.SellTower:FireServer(hash)
			task.wait(0.2)
			if not GetTowerByAxis(axisX) then return end
		else
			return
		end
	end
end

-- Đổi target
local function ChangeTargetRetry(axisX, targetType)
	while true do
		local hash = GetTowerByAxis(axisX)
		if hash then
			Remotes.ChangeQueryType:FireServer(hash, targetType)
			return
		end
		task.wait(0.1)
	end
end

-- Load macro
local config = getgenv().TDX_Config or {}
local macroPath = config["Macro Path"] or "tdx/macros/x.json"

if not isfile(macroPath) then
	error("Không tìm thấy macro: " .. macroPath)
end

local success, macro = pcall(function()
	return HttpService:JSONDecode(readfile(macroPath))
end)
if not success then error("Lỗi khi đọc macro") end

-- Chạy từng dòng
for _, entry in ipairs(macro) do
	if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
		local vecTab = entry.TowerVector:split(", ")
		local pos = Vector3.new(unpack(vecTab))
		local args = {
			tonumber(entry.TowerA1),
			entry.TowerPlaced,
			pos,
			tonumber(entry.Rotation or 0)
		}
		WaitForCash(entry.TowerPlaceCost)
		PlaceTowerRetry(args, pos.X, entry.TowerPlaced)

	elseif entry.TowerUpgraded and entry.UpgradePath then
		local axisValue = tonumber(entry.TowerUpgraded)
		local path = tonumber(entry.UpgradePath)
		UpgradeTowerRetry(axisValue, path)

	elseif entry.ChangeTarget and entry.TargetType then
		local axisValue = tonumber(entry.ChangeTarget)
		ChangeTargetRetry(axisValue, tonumber(entry.TargetType))

	elseif entry.SellTower then
		local axisValue = tonumber(entry.SellTower)
		SellTowerRetry(axisValue)
	end
end

print("✅ [rewrite_unsure] macro hoàn tất.")
