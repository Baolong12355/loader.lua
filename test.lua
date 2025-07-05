repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Safe require TowerClass
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

-- Tìm tower theo X
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
	while cashStat.Value < amount do task.wait() end
end

-- Lấy giá nâng cấp hiện tại
local function GetCurrentUpgradeCost(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local success, cost = pcall(function()
		return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
	end)
	if success and cost then return cost end
	return nil
end

-- Đặt tower
local function PlaceTowerRetry(args, axisX, towerName)
	for _ = 1, 3 do
		Remotes.PlaceTower:InvokeServer(unpack(args))
		task.wait(0.2)
		local hash, tower = GetTowerByAxis(axisX)
		if hash and tower then return true end
	end
	warn("[PlaceTowerRetry] thất bại:", towerName, axisX)
	return false
end

-- Nâng cấp tower: spam cho đến khi max
local function UpgradeUntilMax(axisX, upgradePath)
	for _ = 1, 10 do
		local hash, tower = GetTowerByAxis(axisX)
		if not (hash and tower and tower.LevelHandler) then return end
		local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
		if not (hp and hp > 0) then return end

		local lvl = tower.LevelHandler:GetLevelOnPath(upgradePath)
		local maxLvl = tower.LevelHandler:GetMaxLevel()
		if lvl >= maxLvl then return end

		local cost = GetCurrentUpgradeCost(tower, upgradePath)
		if not cost then return end

		WaitForCash(cost)
		Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)

		local t0 = tick()
		while tick() - t0 < 1.5 do
			task.wait(0.1)
			local _, newTower = GetTowerByAxis(axisX)
			if newTower and newTower.LevelHandler then
				local newLvl = newTower.LevelHandler:GetLevelOnPath(upgradePath)
				if newLvl > lvl then
					break -- nâng thành công, tiếp tục vòng lặp
				end
			end
		end
	end
end

-- Bán tower
local function SellTowerRetry(axisX)
	for _ = 1, 3 do
		local hash = GetTowerByAxis(axisX)
		if hash then
			Remotes.SellTower:FireServer(hash)
			task.wait(0.2)
			local stillExist = GetTowerByAxis(axisX)
			if not stillExist then return end
		else
			return
		end
		task.wait(0.2)
	end
end

-- Đổi target
local function ChangeTargetRetry(axisX, targetType)
	for _ = 1, 3 do
		local hash = GetTowerByAxis(axisX)
		if hash then
			Remotes.ChangeQueryType:FireServer(hash, targetType)
			return
		end
		task.wait(0.2)
	end
end

-- Load macro
local config = getgenv().TDX_Config or {}
local macroPath = config["Macro Path"] or "tdx/macros/x.json"
if not isfile(macroPath) then error("Không tìm thấy macro: " .. macroPath) end

local success, macro = pcall(function()
	return HttpService:JSONDecode(readfile(macroPath))
end)
if not success then error("Lỗi khi đọc macro") end

-- Chạy macro
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
		UpgradeUntilMax(axisValue, path)

	elseif entry.ChangeTarget and entry.TargetType then
		local axisValue = tonumber(entry.ChangeTarget)
		ChangeTargetRetry(axisValue, tonumber(entry.TargetType))

	elseif entry.SellTower then
		local axisValue = tonumber(entry.SellTower)
		SellTowerRetry(axisValue)
	end
end

print("✅ rewrite_unsure hoàn tất.")
