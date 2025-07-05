local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Load TowerClass
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

-- Tìm tower theo X
local function GetTowerByAxis(axisValue)
	local bestHash, bestTower, bestDist
	for hash, tower in pairs(TowerClass.GetTowers()) do
		local success, pos = pcall(function()
			return tower.CFrame.Position
		end)
		if success and pos then
			local dist = math.abs(pos.X - axisValue)
			if dist <= 1 then
				local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
				if hp and hp > 0 then
					if not bestDist or dist < bestDist then
						bestHash, bestTower, bestDist = hash, tower, dist
					end
				end
			end
		end
	end
	return bestHash, bestTower
end

-- Chờ đủ tiền
local function WaitForCash(amount)
	while cashStat.Value < amount do
		task.wait()
	end
end

-- Đặt tower
local function PlaceTowerRetry(args, axisValue, towerName)
	while true do
		Remotes.PlaceTower:InvokeServer(unpack(args))
		local placed = false
		local t0 = tick()
		repeat
			task.wait(0.1)
			local hash, tower = GetTowerByAxis(axisValue)
			if hash and tower then
				placed = true
				break
			end
		until tick() - t0 > 2
		if placed then break end
		warn("[RETRY] Đặt tower thất bại, thử lại:", towerName, "X =", axisValue)
		task.wait()
	end
end

-- Nâng cấp tower: kiểm tra tăng cấp độ
local function UpgradeTowerRetry(axisValue, upgradePath)
	local isUnsure = globalPlaceMode == "unsure"
	local maxTries = isUnsure and math.huge or 3
	local tries = 0

	while tries < maxTries do
		local hash, tower = GetTowerByAxis(axisValue)
		if hash and tower and tower.LevelHandler then
			local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
			if hp and hp > 0 then
				local beforeLevel = tower.LevelHandler:GetLevelOnPath(upgradePath)
				Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)

				-- Đợi và kiểm tra cấp độ tăng
				local success = false
				local t0 = tick()
				repeat
					task.wait(0.1)
					local _, check = GetTowerByAxis(axisValue)
					local afterLevel = check and check.LevelHandler and check.LevelHandler:GetLevelOnPath(upgradePath)
					if afterLevel and (not beforeLevel or afterLevel > beforeLevel) then
						success = true
						break
					end
				until tick() - t0 > 2

				if success then return end
			end
		end
		tries += 1
		task.wait()
	end
end

-- Đổi mục tiêu
local function ChangeTargetRetry(axisValue, targetType)
	while true do
		local hash, tower = GetTowerByAxis(axisValue)
		if hash and tower then
			local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
			if hp and hp > 0 then
				Remotes.ChangeQueryType:FireServer(hash, targetType)
				return
			end
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
			local stillExist = GetTowerByAxis(axisValue)
			if not stillExist then
				return
			end
		end
		task.wait(0.1)
	end
end

-- Load macro
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "y"
local macroPath = "tdx/macros/" .. macroName .. ".json"
globalPlaceMode = config["PlaceMode"] or "normal"

if not isfile(macroPath) then
	error("Không tìm thấy macro file: " .. macroPath)
end

local success, macro = pcall(function()
	return HttpService:JSONDecode(readfile(macroPath))
end)
if not success then
	error("Lỗi khi đọc macro")
end

-- Chạy macro
for i, entry in ipairs(macro) do
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
		UpgradeTowerRetry(axisValue, entry.UpgradePath)

	elseif entry.ChangeTarget and entry.TargetType then
		local axisValue = tonumber(entry.ChangeTarget)
		local targetType = entry.TargetType
		ChangeTargetRetry(axisValue, targetType)

	elseif entry.SellTower then
		local axisValue = tonumber(entry.SellTower)
		SellTowerRetry(axisValue)
	end
end

print("✅ Macro chạy hoàn tất.")
