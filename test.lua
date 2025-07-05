

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
	while cashStat.Value < amount do
		task.wait()
	end
end

-- Đặt tower
local function PlaceTowerRetry(args, axisX, towerName)
	print("[Place] Đặt tower:", towerName, "tại X =", axisX)
	local t0 = tick()
	while tick() - t0 < 3 do
		Remotes.PlaceTower:InvokeServer(unpack(args))
		task.wait(0.2)
		local hash, tower = GetTowerByAxis(axisX)
		if hash and tower then
			print("[Place] Thành công:", towerName)
			return true
		end
	end
	warn("[Place] Thất bại:", towerName)
	return false
end

-- Nâng cấp
local function UpgradeTowerRetry(axisX, upgradePath)
	print("[Upgrade] Bắt đầu nâng X =", axisX, "Path =", upgradePath)
	local maxTries = 3
	for try = 1, maxTries do
		local hash, tower = GetTowerByAxis(axisX)
		if not hash then
			warn("[Upgrade] Tower không tồn tại tại X =", axisX)
			break
		end

		if tower.LevelHandler then
			local lvlBefore = tower.LevelHandler:GetLevelOnPath(upgradePath)
			local maxLvl = tower.LevelHandler:GetMaxLevel()
			if lvlBefore >= maxLvl then
				print("[Upgrade] Đã đạt cấp tối đa")
				return
			end

			local success, cost = pcall(function()
				return tower.LevelHandler:GetLevelUpgradeCost(upgradePath, lvlBefore + 1)
			end)
			if not (success and cost) then
				warn("[Upgrade] Không lấy được giá nâng cấp")
				return
			end

			print("[Upgrade] Chờ tiền:", cost)
			WaitForCash(cost)
			Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)

			local t0 = tick()
			while tick() - t0 < 2 do
				task.wait(0.1)
				local _, newTower = GetTowerByAxis(axisX)
				if newTower and newTower.LevelHandler then
					local lvlAfter = newTower.LevelHandler:GetLevelOnPath(upgradePath)
					if lvlAfter > lvlBefore then
						print("[Upgrade] Thành công:", lvlBefore, "→", lvlAfter)
						return
					end
				end
			end
			warn("[Upgrade] Lần thử", try, "thất bại, thử lại...")
		end
		task.wait(0.2)
	end
end

-- Bán tower
local function SellTowerRetry(axisX)
	local t0 = tick()
	while tick() - t0 < 2 do
		local hash = GetTowerByAxis(axisX)
		if hash then
			Remotes.SellTower:FireServer(hash)
			task.wait(0.2)
			if not GetTowerByAxis(axisX) then
				print("[Sell] Bán thành công X =", axisX)
				return
			end
		else
			return
		end
		task.wait(0.1)
	end
end

-- Đổi target
local function ChangeTargetRetry(axisX, targetType)
	local t0 = tick()
	while tick() - t0 < 2 do
		local hash = GetTowerByAxis(axisX)
		if hash then
			Remotes.ChangeQueryType:FireServer(hash, targetType)
			print("[Target] Đổi target tại X =", axisX)
			return
		end
		task.wait(0.1)
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
for index, entry in ipairs(macro) do
	print("▶️ Entry", index)
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
		UpgradeTowerRetry(axisValue, tonumber(entry.UpgradePath))

	elseif entry.ChangeTarget and entry.TargetType then
		local axisValue = tonumber(entry.ChangeTarget)
		ChangeTargetRetry(axisValue, tonumber(entry.TargetType))

	elseif entry.SellTower then
		local axisValue = tonumber(entry.SellTower)
		SellTowerRetry(axisValue)
	end
end

print("✅ [rewrite_unsure] hoàn tất.")
