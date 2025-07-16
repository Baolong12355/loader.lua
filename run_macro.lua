-- Tự động chạy khi vào game
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Safe Require
local function SafeRequire(path, timeout)
	timeout = timeout or 5
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		local success, result = pcall(function()
			return require(path)
		end)
		if success then return result end
		task.wait()
	end
	return nil
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

-- Tìm tower theo X (đã bỏ kiểm tra sai số)
local function GetTowerByAxis(axisX)
	for hash, tower in pairs(TowerClass.GetTowers()) do
		local success, pos = pcall(function()
			local model = tower.Character:GetCharacterModel()
			local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
			return root and root.Position
		end)
		if success and pos and pos.X == axisX then
			local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
			if hp and hp > 0 then
				return hash, tower
			end
		end
	end
	return nil, nil
end

-- Lấy giá nâng cấp đã tính giảm giá
local function GetCurrentUpgradeCost(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local maxLvl = tower.LevelHandler:GetMaxLevel()
	local curLvl = tower.LevelHandler:GetLevelOnPath(path)
	if curLvl >= maxLvl then return nil end

	-- Lấy giá gốc
	local ok, baseCost = pcall(function()
		return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
	end)
	if not ok or not baseCost then return nil end

	-- Lấy discount
	local discount = 0
	local ok2, disc = pcall(function()
		return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0
	end)
	if ok2 and typeof(disc) == "number" then
		discount = disc
	end

	-- Tính giá sau giảm
	local finalCost = math.floor(baseCost * (1 - discount))
	return finalCost
end

-- Chờ đủ tiền
local function WaitForCash(amount)
	while cashStat.Value < amount do task.wait() end
end

-- Đặt tower
local function PlaceTowerRetry(args, axisValue, towerName)
	while true do
		Remotes.PlaceTower:InvokeServer(unpack(args))
		local t0 = tick()
		repeat
			task.wait(0.1)
			local hash = GetTowerByAxis(axisValue)
			if hash then return end
		until tick() - t0 > 2
		warn("[RETRY] Đặt tower thất bại, thử lại:", towerName, "X =", axisValue)
	end
end

-- Nâng cấp tower (phân biệt theo mode)
local function UpgradeTowerRetry(axisValue, upgradePath)
	local mode = globalPlaceMode
	local maxTries = mode == "rewrite" and math.huge or 3
	local tries = 0

	while tries < maxTries do
		local hash, tower = GetTowerByAxis(axisValue)
		if not hash or not tower then
			if mode == "rewrite" then tries += 1; task.wait(); continue end
			warn("[SKIP] Không thấy tower tại X =", axisValue)
			return
		end

		local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
		if not hp or hp <= 0 then
			if mode == "rewrite" then tries += 1; task.wait(); continue end
			warn("[SKIP] Tower đã chết tại X =", axisValue)
			return
		end

		local before = tower.LevelHandler:GetLevelOnPath(upgradePath)
		local cost = GetCurrentUpgradeCost(tower, upgradePath)
		if not cost then return end

		WaitForCash(cost)
		Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)

		local upgraded = false
		local t0 = tick()
		repeat
			task.wait(0.1)
			local _, t = GetTowerByAxis(axisValue)
			if t and t.LevelHandler then
				local after = t.LevelHandler:GetLevelOnPath(upgradePath)
				if after > before then upgraded = true break end
			end
		until tick() - t0 > 2

		if upgraded then return end

		tries += 1
		task.wait()
	end
end

-- Đổi target
local function ChangeTargetRetry(axisValue, targetType)
	while true do
		local hash = GetTowerByAxis(axisValue)
		if hash then
			Remotes.ChangeQueryType:FireServer(hash, targetType)
			return
		end
		task.wait()
	end
end

-- Bán tower
local function SellTowerRetry(axisValue)
	while true do
		local hash = GetTowerByAxis(axisValue)
		if hash then
			Remotes.SellTower:FireServer(hash)
			task.wait(0.1)
			if not GetTowerByAxis(axisValue) then return end
		end
		task.wait()
	end
end

-- Load macro
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "event"
local macroPath = "tdx/macros/" .. macroName .. ".json"
globalPlaceMode = config["PlaceMode"] or "normal"

-- Ánh xạ lại tên mode
if globalPlaceMode == "unsure" then
	globalPlaceMode = "rewrite"
elseif globalPlaceMode == "normal" then
	globalPlaceMode = "ashed"
end

if not isfile(macroPath) then
	error("Không tìm thấy macro file: " .. macroPath)
end

local success, macro = pcall(function()
	return HttpService:JSONDecode(readfile(macroPath))
end
if not success then
	error("Lỗi khi đọc macro")
end

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

	elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
		local axisValue = tonumber(entry.TowerUpgraded)
		UpgradeTowerRetry(axisValue, entry.UpgradePath)

	elseif entry.ChangeTarget and entry.TargetType then
		local axisValue = tonumber(entry.ChangeTarget)
		ChangeTargetRetry(axisValue, entry.TargetType)

	elseif entry.SellTower then
		local axisValue = tonumber(entry.SellTower)
		SellTowerRetry(axisValue)
	end
end

print("✅ Macro chạy hoàn tất.")
