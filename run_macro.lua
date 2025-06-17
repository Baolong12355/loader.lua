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
local recorded = {}

-- Utility: đợi đủ tiền
local function waitUntilCashEnough(amount)
	while cashStat.Value < amount do task.wait() end
end

-- Utility: tìm tower theo số đầu tiên
local function findTowerByIndex(index)
	for _, tower in ipairs(TowersFolder:GetChildren()) do
		local towerNum = tonumber(tower.Name:match("^(%d+)"))
		if towerNum == tonumber(index) then
			return tower
		end
	end
	return nil
end

-- === Chế độ RUN ===
if mode == "run" then
	local macro = HttpService:JSONDecode(readfile(macroPath))

	local function countTowerByName(name)
		local count = 0
		for _, t in ipairs(TowersFolder:GetChildren()) do
			if t.Name:match("%." .. name .. "$") then count += 1 end
		end
		return count
	end

	local function findNewTower(name, beforeCount)
		for _, t in ipairs(TowersFolder:GetChildren()) do
			if t.Name:match("%." .. name .. "$") then
				beforeCount -= 1
				if beforeCount < 0 then return t end
			end
		end
		return nil
	end

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
			local start = tick()

			while tick() - start < 1 do
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
						placedIndex += 1
					end
					break
				end
			end

		elseif entry.TowerIndex and entry.UpgradePath and entry.UpgradeCost then
			waitUntilCashEnough(entry.UpgradeCost)
			local start = tick()
			while tick() - start < 5 do
				local tower = findTowerByIndex(entry.TowerIndex)
				if tower then
					local before = cashStat.Value
					Remotes.TowerUpgradeRequest:FireServer(entry.TowerIndex, entry.UpgradePath, 1)
					task.wait(0.25)
					if cashStat.Value < before then break end
				end
				task.wait(0.1)
			end

		elseif entry.ChangeTarget and entry.TargetType then
			Remotes.ChangeQueryType:FireServer(entry.ChangeTarget, entry.TargetType)
			task.wait(0.2)

		elseif entry.SellTower then
			Remotes.SellTower:FireServer(entry.SellTower)
			task.wait(0.2)
		end
	end

	print("✅ Đã chạy xong macro:", macroName)

-- === Chế độ RECORD ===
elseif mode == "record" then
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
		end)
		return oldChange(self, index, type)
	end

	local oldSell = sellTower.FireServer
	sellTower.FireServer = function(self, index)
		task.defer(function()
			table.insert(recorded, {
				SellTower = index
			})
		end)
		return oldSell(self, index)
	end

	game:BindToClose(function()
		writefile(macroPath, HttpService:JSONEncode(recorded))
		print("💾 Đã lưu macro vào:", macroPath)
	end)

	print("🎬 Đang ghi macro vào:", macroPath)
end
