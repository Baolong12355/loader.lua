local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TowersFolder = Workspace:WaitForChild("Game"):WaitForChild("Towers")

local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "y"
local macroPath = "tdx/macros/" .. macroName .. ".json"
local macro = HttpService:JSONDecode(readfile(macroPath))

local placedIndex = 1

-- 🔎 So sánh gần đúng vị trí
local function samePos(a, b)
	return (a - b).Magnitude < 1
end

-- 📊 Đếm số tower có tên gốc (dù đã đổi tên)
local function countTowerByName(name)
	local count = 0
	for _, tower in ipairs(TowersFolder:GetChildren()) do
		if tower.Name:match("%." .. name .. "$") then
			count += 1
		end
	end
	return count
end

-- 🔍 Tìm tower mới được đặt (dù đã đổi tên)
local function findNewTower(name, beforeCount)
	local found = {}
	for _, tower in ipairs(TowersFolder:GetChildren()) do
		if tower.Name:match("%." .. name .. "$") then
			table.insert(found, tower)
		end
	end
	table.sort(found, function(a, b)
		return a.Name < b.Name
	end)
	return found[beforeCount + 1]
end

-- 🔢 Tìm tower theo số thứ tự
local function findTowerByIndex(index)
	for _, tower in ipairs(TowersFolder:GetChildren()) do
		local towerNum = tonumber(tower.Name:match("^(%d+)"))
		if towerNum == tonumber(index) then
			return tower
		end
	end
	return nil
end

-- 💰 Đợi có đủ tiền
local function waitUntilCashEnough(amount)
	while cashStat.Value < amount do task.wait() end
end

-- ▶️ CHẠY MACRO
for _, entry in ipairs(macro) do
	if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
		local x, y, z = entry.TowerVector:match("([^,]+), ([^,]+), ([^,]+)")
		local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
		local args = {
			tonumber(entry.TowerA1),
			entry.TowerPlaced,
			pos,
			tonumber(entry.Rotation) or 0
		}

		local beforeCount = countTowerByName(entry.TowerPlaced)
		local placed = false
		local start = tick()

		while not placed and tick() - start < 3 do
			waitUntilCashEnough(entry.TowerPlaceCost)
			local before = cashStat.Value
			Remotes.PlaceTower:InvokeServer(unpack(args))
			task.wait(0.25)
			local after = cashStat.Value
			local afterCount = countTowerByName(entry.TowerPlaced)

			if after < before and afterCount > beforeCount then
				local tower = findNewTower(entry.TowerPlaced, beforeCount)
				if tower then
					tower.Name = placedIndex .. "." .. entry.TowerPlaced
					print("✅ Đặt:", tower.Name)
					placedIndex += 1
					placed = true
				end
			end
		end

	elseif entry.TowerIndex and entry.UpgradePath and entry.UpgradeCost then
		waitUntilCashEnough(entry.UpgradeCost)
		local upgraded = false
		local start = tick()

		while not upgraded and tick() - start < 5 do
			local tower = findTowerByIndex(entry.TowerIndex)
			if tower then
				local before = cashStat.Value
				Remotes.TowerUpgradeRequest:FireServer(entry.TowerIndex, entry.UpgradePath, 1)
				task.wait(0.25)
				local after = cashStat.Value
				if after < before then
					print("⬆️ Nâng:", tower.Name)
					upgraded = true
					break
				end
			end
			task.wait(0.2)
		end

	elseif entry.ChangeTarget and entry.TargetType then
		Remotes.ChangeQueryType:FireServer(entry.ChangeTarget, entry.TargetType)
		print("🎯 Target:", entry.ChangeTarget, "→", entry.TargetType)
		task.wait(0.2)

	elseif entry.SellTower then
		Remotes.SellTower:FireServer(entry.SellTower)
		print("💸 Bán tower index:", entry.SellTower)
		task.wait(0.2)
	end
end

print("🎉 Hoàn tất chạy macro:", macroName)
