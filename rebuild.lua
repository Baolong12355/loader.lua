-- ⚙️ ROBLOX SERVICES
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- ⚙️ TOWER CLASS
local function SafeRequire(path, timeout)
	timeout = timeout or 5
	local t0 = os.clock()
	while os.clock() - t0 < timeout do
		local success, result = pcall(function()
			return require(path)
		end)
		if success then
			return result
		end
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

-- 🧠 UTILS
local function GetTowerByAxis(axisX)
	for hash, tower in pairs(TowerClass.GetTowers()) do
		local model = tower.Character and tower.Character:GetCharacterModel()
		local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
		if root and root.Position.X == axisX then
			local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
			if hp and hp > 0 then
				return hash, tower
			end
		end
	end
	return nil, nil
end

local function GetCurrentUpgradeCost(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local maxLvl = tower.LevelHandler:GetMaxLevel()
	local curLvl = tower.LevelHandler:GetLevelOnPath(path)
	if curLvl >= maxLvl then return nil end

	local ok, baseCost = pcall(function()
		return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
	end)
	if not ok or not baseCost then return nil end

	local discount = 0
	local ok2, disc = pcall(function()
		return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0
	end)
	if ok2 and typeof(disc) == "number" then
		discount = disc
	end

	return math.floor(baseCost * (1 - discount))
end

local function WaitForCash(amount)
	while cashStat.Value < amount do task.wait() end
end

-- 🔁 RETRY FUNCS (fromRebuild hỗ trợ debug)
local function PlaceTowerRetry(args, axisValue, towerName, fromRebuild)
	while true do
		Remotes.PlaceTower:InvokeServer(unpack(args))
		task.wait(0.1)
		local hash = GetTowerByAxis(axisValue)
		if hash then
			if fromRebuild then print("[REBUILD] ✅ Đặt:", towerName, "X:", axisValue) end
			return
		end
		if fromRebuild then warn("[REBUILD] 🔁 Thử lại đặt:", towerName, "X:", axisValue) end
	end
end

local function UpgradeTowerRetry(axisX, path, fromRebuild)
	local mode = globalPlaceMode
	local maxTry = mode == "rewrite" and math.huge or 3
	local count = 0
	while count < maxTry do
		local _, tower = GetTowerByAxis(axisX)
		if not tower then count += 1 task.wait() continue end
		local hp = tower.HealthHandler:GetHealth()
		if hp <= 0 then count += 1 task.wait() continue end

		local before = tower.LevelHandler:GetLevelOnPath(path)
		local cost = GetCurrentUpgradeCost(tower, path)
		if not cost then return end
		WaitForCash(cost)

		Remotes.TowerUpgradeRequest:FireServer(_, path, 1)
		task.wait(0.1)

		local _, updated = GetTowerByAxis(axisX)
		if updated and updated.LevelHandler:GetLevelOnPath(path) > before then
			if fromRebuild then print("[REBUILD] ✅ Upgrade:", axisX, "-> Path:", path) end
			return
		end

		if fromRebuild then warn("[REBUILD] 🔁 Upgrade thất bại:", axisX) end
		count += 1
		task.wait()
	end
end

local function ChangeTargetRetry(axisX, targetType, fromRebuild)
	local hash = GetTowerByAxis(axisX)
	if hash then
		Remotes.ChangeQueryType:FireServer(hash, targetType)
		if fromRebuild then print("[REBUILD] 🎯 ChangeTarget:", axisX, "→", targetType) end
	end
end

local function SellTowerRetry(axisX, fromRebuild)
	local hash = GetTowerByAxis(axisX)
	if hash then
		Remotes.SellTower:FireServer(hash)
		if fromRebuild then print("[REBUILD] 🗑️ SellTower:", axisX) end
	end
end

-- 📦 LOAD MACRO
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "event"
local macroPath = "tdx/macros/" .. macroName .. ".json"
globalPlaceMode = config["PlaceMode"] or "rewrite"

if not isfile(macroPath) then error("Không tìm thấy macro: " .. macroPath) end
local success, macro = pcall(function() return HttpService:JSONDecode(readfile(macroPath)) end)
if not success then error("Không đọc được macro") end
print("[REBUILD] Macro đã load:", macroName)

-- 🎯 BẮT ĐẦU TỪ DÒNG rebuild
local rebuildIndex = nil
local skipTowers = {}
local skipModeBe = false

for i, entry in ipairs(macro) do
	if entry.SuperFunction == "rebuild" then
		rebuildIndex = i
		if entry.Skip then
			for _, name in ipairs(entry.Skip) do
				skipTowers[name] = true
			end
		end
		skipModeBe = entry.Be or false
		break
	end
end

if not rebuildIndex then warn("[REBUILD] Không tìm thấy dòng SuperFunction: rebuild") return end

-- 📍 GHI LẠI tower theo X
local towerRecords = {}
for i = 1, rebuildIndex do
	local entry = macro[i]
	if entry.TowerVector then
		local vecTab = entry.TowerVector:split(", ")
		local pos = Vector3.new(unpack(vecTab))
		local axisX = pos.X
		towerRecords[axisX] = towerRecords[axisX] or {}
		table.insert(towerRecords[axisX], entry)
	end
end

-- 🔍 XÁC ĐỊNH tower mất/hỏng
local rebuildQueue = {}

for axisX, actions in pairs(towerRecords) do
	local lastPlace = nil
	for _, a in ipairs(actions) do
		if a.TowerPlaced then lastPlace = a.TowerPlaced end
	end

	local _, tower = GetTowerByAxis(axisX)
	if (not tower) or (tower.HealthHandler and tower.HealthHandler:GetHealth() <= 0) then
		if skipModeBe and skipTowers[lastPlace] then
			print("[REBUILD] ❌ Skip do nằm trong Skip (Be=true):", lastPlace)
		else
			table.insert(rebuildQueue, {name = lastPlace, x = axisX, actions = actions})
		end
	end
end

-- 🔃 SẮP XẾP theo độ ưu tiên
local priority = {
	["Medic"] = 1,
	["Golden Mobster"] = 2,
	["Mobster"] = 2,
	["DJ"] = 3,
	["Commander"] = 4
}

table.sort(rebuildQueue, function(a, b)
	return (priority[a.name] or 99) < (priority[b.name] or 99)
end)

-- 🔨 TIẾN HÀNH REBUILD
for _, taskData in ipairs(rebuildQueue) do
	local name = taskData.name
	local axisX = taskData.x
	local actions = taskData.actions

	for _, record in ipairs(actions) do
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

print("[REBUILD] ✅ Toàn bộ quá trình rebuild hoàn tất.")