local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local Towers = Workspace:WaitForChild("Game"):WaitForChild("Towers")

local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "y"
local macroPath = "tdx/macros/" .. macroName .. ".json"
local macro = HttpService:JSONDecode(readfile(macroPath))

local placedIndex = 1

-- Đợi đủ tiền
local function waitUntilCashEnough(cost)
	while cashStat.Value < cost do task.wait() end
end

-- Đếm số lượng tower đang có tên giống
local function countTower(name)
	local count = 0
	for _, tower in ipairs(Towers:GetChildren()) do
		if tower.Name:match("%." .. name .. "$") then
			count += 1
		end
	end
	return count
end

-- Tìm tower mới được đặt
local function findNewTower(name, before)
	for _, tower in ipairs(Towers:GetChildren()) do
		if tower.Name:match("%." .. name .. "$") then
			before -= 1
			if before < 0 then
				return tower
			end
		end
	end
end

-- Tìm tower theo số thứ tự
local function findTowerByIndex(index)
	for _, tower in ipairs(Towers:GetChildren()) do
		local num = tonumber(tower.Name:match("^(%d+)"))
		if num == tonumber(index) then
			return tower
		end
	end
end

-- Bắt đầu thực thi macro
for _, entry in ipairs(macro) do
	if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost and entry.TowerA1 then
		local x, y, z = entry.TowerVector:match("([^,]+), ([^,]+), ([^,]+)")
		local vec = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
		local args = {
			tonumber(entry.TowerA1),
			entry.TowerPlaced,
			vec,
			tonumber(entry.Rotation) or 0
		}

		local beforeCount = countTower(entry.TowerPlaced)
		local start = tick()
		local placed = false

		while not placed and tick() - start < 2 do
			waitUntilCashEnough(entry.TowerPlaceCost)
			local beforeCash = cashStat.Value
			Remotes.PlaceTower:InvokeServer(unpack(args))
			task.wait(0.25)
			local afterCash = cashStat.Value
			local afterCount = countTower(entry.TowerPlaced)

			if afterCount > beforeCount then
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
		local args = {
			entry.TowerIndex,
			entry.UpgradePath,
			1
		}
		local upgraded = false
		local start = tick()

		while not upgraded and tick() - start < 5 do
			local tower = findTowerByIndex(entry.TowerIndex)
			if tower then
				local before = cashStat.Value
				Remotes.TowerUpgradeRequest:FireServer(unpack(args))
				task.wait(0.25)
				if cashStat.Value < before then
					print("⬆️ Nâng:", tower.Name)
					upgraded = true
					break
				end
			end
			task.wait(0.2)
		end

	elseif entry.ChangeTarget and entry.TargetType then
		Remotes.ChangeQueryType:FireServer(entry.ChangeTarget, entry.TargetType)
		print("🎯 Đổi target:", entry.ChangeTarget, "→", entry.TargetType)
		task.wait(0.2)

	elseif entry.SellTower then
		Remotes.SellTower:FireServer(entry.SellTower)
		print("💸 Bán tower index:", entry.SellTower)
		task.wait(0.2)
	end
end

print("🎉 Đã chạy xong macro:", macroName)
