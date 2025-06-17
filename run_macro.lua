local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TowersFolder = Workspace:WaitForChild("Game"):WaitForChild("Towers")

local config = getgenv().TDX_Config or {}
local mode = config["Macros"] or "run"
local macroName = config["Macro Name"] or "y"
local macroPath = "tdx/macros/" .. macroName .. ".json"

local placedIndex = 1

-- ⏳ Tiện ích
local function waitUntilCashEnough(amount)
	while cashStat.Value < amount do task.wait() end
end

local function countTowerByName(name)
	local count = 0
	for _, t in ipairs(TowersFolder:GetChildren()) do
		if t.Name:match("%." .. name .. "$") then count += 1 end
	end
	return count
end

local function findNewTower(name, beforeCount)
	local found = {}
	for _, t in ipairs(TowersFolder:GetChildren()) do
		if t.Name:match("%." .. name .. "$") then
			table.insert(found, t)
		end
	end
	table.sort(found, function(a, b)
		return a.Name < b.Name
	end)
	return found[beforeCount + 1]
end

local function findTowerByIndex(index)
	for _, tower in ipairs(TowersFolder:GetChildren()) do
		local towerNum = tonumber(tower.Name:match("^(%d+)"))
		if towerNum == tonumber(index) then
			return tower
		end
	end
	return nil
end

-- === ▶️ CHẾ ĐỘ CHẠY MACRO ===
if mode == "run" then
	local macro = HttpService:JSONDecode(readfile(macroPath))

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

			while not placed and tick() - start < 2 do
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
					end
					placed = true
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

-- === 🎬 CHẾ ĐỘ GHI LẠI ===
elseif mode == "record" then
	local recorded = {}

	local placing = Remotes:WaitForChild("PlaceTower")
	local upgrade = Remotes:WaitForChild("TowerUpgradeRequest")
	local changeTarget = Remotes:WaitForChild("ChangeQueryType")
	local sellTower = Remotes:WaitForChild("SellTower")

	placing.OnClientInvoke = function(...)
		task.defer(function(...)
			local args = {...}
			table.insert(recorded, {
				TowerPlaced = args[2],
				TowerVector = tostring(args[3]),
				Rotation = args[4],
				TowerPlaceCost = cashStat.Value,
				TowerA1 = args[1]
			})
			print("🎬 Ghi đặt:", args[2])
		end, ...)
	end

	local oldUpgrade = upgrade.FireServer
	upgrade.FireServer = function(self, id, path, which)
		task.defer(function()
			table.insert(recorded, {
				TowerIndex = id,
				UpgradePath = path,
				UpgradeCost = cashStat.Value
			})
			print("🎬 Ghi nâng:", id, "→", path)
		end)
		return oldUpgrade(self, id, path, which)
	end

	local oldChange = changeTarget.FireServer
	changeTarget.FireServer = function(self, index, type)
		task.defer(function()
			table.insert(recorded, {
				ChangeTarget = index,
				TargetType = type
			})
			print("🎬 Ghi target:", index, "→", type)
		end)
		return oldChange(self, index, type)
	end

	local oldSell = sellTower.FireServer
	sellTower.FireServer = function(self, index)
		task.defer(function()
			table.insert(recorded, {
				SellTower = index
			})
			print("🎬 Ghi bán:", index)
		end)
		return oldSell(self, index)
	end

	game:BindToClose(function()
		writefile(macroPath, HttpService:JSONEncode(recorded))
		print("💾 Đã lưu macro vào:", macroPath)
	end)

	print("🎬 Bắt đầu ghi macro vào:", macroPath)
end
