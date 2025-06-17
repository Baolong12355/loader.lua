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

local function waitUntilCashEnough(amount)
	while cashStat.Value < amount do task.wait() end
end

local function countTowerByName(name)
	local count = 0
	for _, tower in ipairs(TowersFolder:GetChildren()) do
		if tower.Name == name or tower.Name:match("%." .. name .. "$") then
			count += 1
		end
	end
	return count
end

local function findTowerByIndex(index)
	for _, tower in ipairs(TowersFolder:GetChildren()) do
		local num = tonumber(tower.Name:match("^(%d+)"))
		if num == tonumber(index) then
			return tower
		end
	end
	return nil
end

-- ▶️ Chạy từng bước macro
for _, entry in ipairs(macro) do
	-- Đặt tower
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
			local beforeCash = cashStat.Value
			Remotes.PlaceTower:InvokeServer(unpack(args))
			task.wait(0.25)
			local afterCash = cashStat.Value

			local count = 0
			for _, tower in ipairs(TowersFolder:GetChildren()) do
				if tower:IsA("Model") and (tower.Name == entry.TowerPlaced or tower.Name:match("%." .. entry.TowerPlaced .. "$")) then
					count += 1
					if count > beforeCount then
						tower.Name = count .. "." .. entry.TowerPlaced
						print("✅ Đặt:", tower.Name)
						placed = true
						break
					end
				end
			end

			if afterCash < beforeCash and not placed then
				print("⚠️ Đặt thành công nhưng không rename được")
				placed = true
			end
		end

	-- Nâng cấp tower
	elseif entry.TowerIndex and entry.UpgradePath and entry.UpgradeCost then
		waitUntilCashEnough(entry.UpgradeCost)
		local start = tick()
		while tick() - start < 5 do
			local tower = findTowerByIndex(entry.TowerIndex)
			if tower then
				local before = cashStat.Value
				Remotes.TowerUpgradeRequest:FireServer(entry.TowerIndex, entry.UpgradePath, 1)
				task.wait(0.25)
				if cashStat.Value < before then
					print("⬆️ Nâng cấp:", tower.Name)
					break
				end
			end
			task.wait(0.1)
		end

	-- Đổi target
	elseif entry.ChangeTarget and entry.TargetType then
		Remotes.ChangeQueryType:FireServer(entry.ChangeTarget, entry.TargetType)
		task.wait(0.2)

	-- Bán tower
	elseif entry.SellTower then
		Remotes.SellTower:FireServer(entry.SellTower)
		task.wait(0.2)
	end
end

print("✅ Đã chạy xong macro:", macroName)
