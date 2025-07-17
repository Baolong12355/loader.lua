-- ROBLOX SERVICES
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- LOAD TOWER CLASS
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

-- UTILS
local function GetTowerByAxis(axisX)
	for hash, tower in pairs(TowerClass.GetTowers()) do
		local model = tower.Character and tower.Character:GetCharacterModel()
		local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
		if root and root.Position.X == axisX then
			local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
			if hp and hp > 0 then return hash, tower end
		end
	end
	return nil, nil
end

local function WaitForCash(amount)
	while cashStat.Value < amount do task.wait() end
end

local function GetCurrentUpgradeCost(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local maxLvl = tower.LevelHandler:GetMaxLevel()
	local curLvl = tower.LevelHandler:GetLevelOnPath(path)
	if curLvl >= maxLvl then return nil end
	local ok, baseCost = pcall(function() return tower.LevelHandler:GetLevelUpgradeCost(path, 1) end)
	if not ok or not baseCost then return nil end
	local discount = 0
	local ok2, disc = pcall(function() return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end)
	if ok2 and typeof(disc) == "number" then discount = disc end
	return math.floor(baseCost * (1 - discount))
end

-- RETRY FUNCS
local function PlaceTowerRetry(args, axisX, towerName, fromRebuild)
	while true do
		Remotes.PlaceTower:InvokeServer(unpack(args))
		task.wait(0.1)
		local hash = GetTowerByAxis(axisX)
		if hash then
			if fromRebuild then print("[REBUILD] ✅ Đặt:", towerName, "X:", axisX) end
			return
		end
		if fromRebuild then warn("[REBUILD] ❌ Lỗi đặt:", towerName, "X:", axisX) end
	end
end

local function UpgradeTowerRetry(axisX, path, fromRebuild)
	local maxTries = globalPlaceMode == "rewrite" and math.huge or 3
	local tries = 0
	while tries < maxTries do
		local _, tower = GetTowerByAxis(axisX)
		if not tower or tower.HealthHandler:GetHealth() <= 0 then
			tries += 1; task.wait(); continue
		end
		local before = tower.LevelHandler:GetLevelOnPath(path)
		local cost = GetCurrentUpgradeCost(tower, path)
		if not cost then return end
		WaitForCash(cost)
		Remotes.TowerUpgradeRequest:FireServer(_, path, 1)
		task.wait(0.1)
		local _, t = GetTowerByAxis(axisX)
		if t and t.LevelHandler:GetLevelOnPath(path) > before then
			if fromRebuild then print("[REBUILD] ✅ Upgrade X:", axisX, "Path:", path) end
			return
		end
		if fromRebuild then warn("[REBUILD] 🔁 Upgrade thất bại:", axisX) end
		tries += 1
		task.wait()
	end
end

local function ChangeTargetRetry(axisX, targetType, fromRebuild)
	local hash = GetTowerByAxis(axisX)
	if hash then
		Remotes.ChangeQueryType:FireServer(hash, targetType)
		if fromRebuild then print("[REBUILD] 🎯 ChangeTarget X:", axisX, "→", targetType) end
	end
end

local function SellTowerRetry(axisX, fromRebuild)
	local hash = GetTowerByAxis(axisX)
	if hash then
		Remotes.SellTower:FireServer(hash)
		if fromRebuild then print("[REBUILD] 🗑️ SellTower X:", axisX) end
	end
end

-- GLOBAL CONFIG
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "event"
local macroPath = "tdx/macros/" .. macroName .. ".json"
globalPlaceMode = config["PlaceMode"] or "rewrite"

if not isfile(macroPath) then error("Không tìm thấy macro: " .. macroPath) end
local success, macro = pcall(function() return HttpService:JSONDecode(readfile(macroPath)) end)
if not success then error("Không đọc được macro") end
print("[MACRO] ✅ Đã load macro:", macroName)

-- SKIP VARS
local skipTowers = {}
local skipModeBe = false
local rebuildStartIndex = nil
local rebuildWatcherRunning = false

-- 🧠 Rebuild Watcher
function startRebuildWatcher(macro, maxLine)
	if rebuildWatcherRunning then return end
	rebuildWatcherRunning = true
	rebuildStartIndex = maxLine
	print("[REBUILD] 🚨 BẮT ĐẦU theo dõi mất tower...")

	task.spawn(function()
		while rebuildWatcherRunning do
			local towerRecords = {}
			local towerLastIndex = {}

			for i = 1, maxLine do
				local entry = macro[i]
				if entry.TowerVector then
					local vec = Vector3.new(unpack(entry.TowerVector:split(", ")))
					local axisX = vec.X
					towerRecords[axisX] = towerRecords[axisX] or {}
					table.insert(towerRecords[axisX], entry)
					towerLastIndex[axisX] = i
				end
			end

			for axisX, records in pairs(towerRecords) do
				local _, tower = GetTowerByAxis(axisX)

				-- Lấy tên tower cuối cùng
				local lastTowerName = nil
				for _, r in ipairs(records) do
					if r.TowerPlaced then lastTowerName = r.TowerPlaced end
				end

				local lastLine = towerLastIndex[axisX] or 0

				-- Kiểm tra skip
				if skipTowers[lastTowerName] then
					if skipModeBe then
						if lastLine < rebuildStartIndex then
							print("[REBUILD] ⏩ Bỏ qua:", lastTowerName, "(Be = true, phía trên)")
							continue
						end
					else
						print("[REBUILD] ⏩ Bỏ qua:", lastTowerName, "(Không có Be)")
						continue
					end
				end

				if not tower or (tower.HealthHandler and tower.HealthHandler:GetHealth() <= 0) then
					print("[REBUILD] 🔄 Tower mất:", lastTowerName, "X:", axisX)
					for _, record in ipairs(records) do
						if record.TowerPlaced then
							local vec = Vector3.new(unpack(record.TowerVector:split(", ")))
							local args = {
								tonumber(record.TowerA1),
								record.TowerPlaced,
								vec,
								tonumber(record.Rotation or 0)
							}
							WaitForCash(record.TowerPlaceCost)
							PlaceTowerRetry(args, axisX, record.TowerPlaced, true)
						elseif record.TowerUpgraded then
							UpgradeTowerRetry(axisX, record.UpgradePath, true)
						elseif record.ChangeTarget then
							ChangeTargetRetry(axisX, record.TargetType, true)
						elseif record.SellTower then
							SellTowerRetry(axisX, true)
						end
					end
				end
			end

			task.wait(2)
		end
	end)
end

-- 🔁 CHẠY MACRO BÌNH THƯỜNG
local currentLineIndex = 0

for i, entry in ipairs(macro) do
	currentLineIndex = i

	if entry.SuperFunction == "rebuild" then
		skipTowers = {}
		if entry.Skip then
			for _, name in ipairs(entry.Skip) do
				skipTowers[name] = true
			end
		end
		skipModeBe = entry.Be or false
		startRebuildWatcher(macro, i)
	elseif entry.TowerPlaced then
		local vec = Vector3.new(unpack(entry.TowerVector:split(", ")))
		local args = {
			tonumber(entry.TowerA1),
			entry.TowerPlaced,
			vec,
			tonumber(entry.Rotation or 0)
		}
		WaitForCash(entry.TowerPlaceCost)
		PlaceTowerRetry(args, vec.X, entry.TowerPlaced)
	elseif entry.TowerUpgraded then
		local vec = Vector3.new(unpack(entry.TowerVector:split(", ")))
		UpgradeTowerRetry(vec.X, entry.UpgradePath)
	elseif entry.ChangeTarget then
		local vec = Vector3.new(unpack(entry.TowerVector:split(", ")))
		ChangeTargetRetry(vec.X, entry.TargetType)
	elseif entry.SellTower then
		local vec = Vector3.new(unpack(entry.TowerVector:split(", ")))
		SellTowerRetry(vec.X)
	end

	task.wait()
end