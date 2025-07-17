-- TDX Macro Runner - Rebuild Optimized (No Live Tower Logging)

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Require TowerClass
local function SafeRequire(path, timeout)
	timeout = timeout or 5
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		local success, result = pcall(function() return require(path) end)
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

-- Check if no tower exists at X
local function IsTowerMissing(axisX)
	for _, tower in pairs(TowerClass.GetTowers()) do
		local ok, pos = pcall(function()
			local model = tower.Character:GetCharacterModel()
			local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
			return root and root.Position
		end)
		if ok and pos and pos.X == axisX then
			return false
		end
	end
	return true
end

-- Retry Helpers
local function WaitForCash(amount)
	while cashStat.Value < amount do task.wait() end
end

local function GetCurrentUpgradeCost(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local maxLvl = tower.LevelHandler:GetMaxLevel()
	local curLvl = tower.LevelHandler:GetLevelOnPath(path)
	if curLvl >= maxLvl then return nil end
	local ok, baseCost = pcall(function()
		return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
	end)
	if not ok then return nil end
	local discount = 0
	local ok2, disc = pcall(function()
		return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0
	end)
	if ok2 and typeof(disc) == "number" then discount = disc end
	return math.floor(baseCost * (1 - discount))
end

local function GetTowerByAxis(axisX)
	for hash, tower in pairs(TowerClass.GetTowers()) do
		local ok, pos = pcall(function()
			local model = tower.Character:GetCharacterModel()
			local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
			return root and root.Position
		end)
		if ok and pos and pos.X == axisX then
			local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
			if hp and hp > 0 then return hash, tower end
		end
	end
	return nil, nil
end

local function PlaceTowerRetry(args, axisX, towerName)
	while true do
		Remotes.PlaceTower:InvokeServer(unpack(args))
		task.wait(0.1)
		local hash = GetTowerByAxis(axisX)
		if hash then
			print("[REBUILD] ✅ Đặt lại:", towerName, "X =", axisX)
			return
		end
		warn("[REBUILD] ❌ Thử lại đặt:", towerName, "X =", axisX)
	end
end

local function UpgradeTowerRetry(axisX, path)
	local tries = 0
	local maxTries = globalPlaceMode == "rewrite" and math.huge or 3
	while tries < maxTries do
		local hash, tower = GetTowerByAxis(axisX)
		if not hash or not tower then tries += 1 task.wait() continue end
		local before = tower.LevelHandler:GetLevelOnPath(path)
		local cost = GetCurrentUpgradeCost(tower, path)
		if not cost then return end
		WaitForCash(cost)
		Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
		task.wait(0.1)
		local _, t = GetTowerByAxis(axisX)
		if t and t.LevelHandler:GetLevelOnPath(path) > before then
			print("[REBUILD] ✅ Upgrade X =", axisX, "path =", path)
			return
		end
		tries += 1
	end
end

local function ChangeTargetRetry(axisX, targetType)
	local hash = GetTowerByAxis(axisX)
	if hash then
		Remotes.ChangeQueryType:FireServer(hash, targetType)
		print("[REBUILD] 🎯 ChangeTarget X =", axisX, "→", targetType)
	end
end

local function SellTowerRetry(axisX)
	local hash = GetTowerByAxis(axisX)
	if hash then
		Remotes.SellTower:FireServer(hash)
		print("[REBUILD] 🗑️ SellTower X =", axisX)
	end
end

-- GLOBALS
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "event"
local macroPath = "tdx/macros/" .. macroName .. ".json"
globalPlaceMode = config["PlaceMode"] or "rewrite"

if not isfile(macroPath) then error("Không tìm thấy macro: " .. macroPath) end

local success, macro = pcall(function()
	return HttpService:JSONDecode(readfile(macroPath))
end)
if not success then error("Lỗi khi đọc macro") end

-- Skip logic
local skipTowers = {}
local skipModeBe = false
local rebuildStartIndex = 0
local rebuildWatcherRunning = false

-- Watcher
function startRebuildWatcher(macro, maxLine)
	if rebuildWatcherRunning then return end
	rebuildWatcherRunning = true
	rebuildStartIndex = maxLine
	print("[REBUILD] 🔁 Đang theo dõi tower mất...")

	task.spawn(function()
		while true do
			local towerRecords = {}
			local lastIndex = {}

			for i = 1, maxLine do
				local e = macro[i]
				local axisX = nil
				if e.TowerVector then
					local ok, vecTab = pcall(function() return e.TowerVector:split(", ") end)
					if ok then
						local vec = Vector3.new(unpack(vecTab))
						axisX = vec.X
					end
				elseif e.TowerUpgraded then axisX = tonumber(e.TowerUpgraded)
				elseif e.SellTower then axisX = tonumber(e.SellTower)
				elseif e.ChangeTarget then axisX = tonumber(e.ChangeTarget)
				end

				if axisX then
					towerRecords[axisX] = towerRecords[axisX] or {}
					table.insert(towerRecords[axisX], e)
					lastIndex[axisX] = i
				end
			end

			for axisX, actions in pairs(towerRecords) do
				local lastLine = lastIndex[axisX] or 0
				local name = "?"
				for _, act in ipairs(actions) do
					if act.TowerPlaced then name = act.TowerPlaced break end
				end

				if skipTowers[name] then
					if skipModeBe and lastLine < rebuildStartIndex then continue end
					if not skipModeBe then continue end
				end

				if IsTowerMissing(axisX) then
					print("[REBUILD] ⚙️ Tower biến mất tại X =", axisX, "→", name)
					for _, record in ipairs(actions) do
						if record.TowerPlaced and record.TowerVector then
							local ok, vecTab = pcall(function() return record.TowerVector:split(", ") end)
							if ok then
								local vec = Vector3.new(unpack(vecTab))
								local args = {
									tonumber(record.TowerA1),
									record.TowerPlaced,
									vec,
									tonumber(record.Rotation or 0)
								}
								WaitForCash(record.TowerPlaceCost)
								PlaceTowerRetry(args, axisX, record.TowerPlaced)
							end
						elseif record.TowerUpgraded then
							UpgradeTowerRetry(axisX, record.UpgradePath)
						elseif record.ChangeTarget then
							ChangeTargetRetry(axisX, record.TargetType)
						elseif record.SellTower then
							SellTowerRetry(axisX)
						end
					end
				end
			end

			task.wait(2)
		end
	end)
end

-- Run macro
for i, entry in ipairs(macro) do
	if entry.SuperFunction == "rebuild" then
		skipTowers = {}
		if entry.Skip then
			for _, name in ipairs(entry.Skip) do
				skipTowers[name] = true
			end
		end
		skipModeBe = entry.Be or false
		startRebuildWatcher(macro, i)
	elseif entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
		local ok, vecTab = pcall(function() return entry.TowerVector:split(", ") end)
		if ok then
			local vec = Vector3.new(unpack(vecTab))
			local args = {
				tonumber(entry.TowerA1),
				entry.TowerPlaced,
				vec,
				tonumber(entry.Rotation or 0)
			}
			WaitForCash(entry.TowerPlaceCost)
			PlaceTowerRetry(args, vec.X, entry.TowerPlaced)
		end
	elseif entry.TowerUpgraded then
		UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath)
	elseif entry.ChangeTarget then
		ChangeTargetRetry(tonumber(entry.ChangeTarget), entry.TargetType)
	elseif entry.SellTower then
		SellTowerRetry(tonumber(entry.SellTower))
	end
end

print("✅ Macro hoàn tất + đang theo dõi rebuild.")