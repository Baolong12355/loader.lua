-- [[ Auto Rebuild - Runtime Based - No Macro - Debug Enabled ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local debugMode = true -- ✅ Bật/tắt debug

-- ==== Load TowerClass ====
local TowerClass
do
	local ps = player:WaitForChild("PlayerScripts")
	local client = ps:WaitForChild("Client")
	local gameClass = client:WaitForChild("GameClass")
	local towerModule = gameClass:WaitForChild("TowerClass")
	TowerClass = require(towerModule)
end

-- ==== Hàm phụ trợ ====

local function WaitForCash(amount)
	local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
	while cash.Value < amount do task.wait() end
end

local function GetTowerPlaceCostByName(name)
	local gui = player:FindFirstChild("PlayerGui")
	local bar = gui and gui:FindFirstChild("Interface") and gui.Interface:FindFirstChild("BottomBar")
	local towersBar = bar and bar:FindFirstChild("TowersBar")
	if not towersBar then return 0 end
	for _, tower in ipairs(towersBar:GetChildren()) do
		if tower.Name == name then
			local costText = tower:FindFirstChild("CostFrame") and tower.CostFrame:FindFirstChild("CostText")
			if costText then
				return tonumber(tostring(costText.Text):gsub("%D", "")) or 0
			end
		end
	end
	return 0
end

local function GetUpgradeCost(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local ok, cost = pcall(function()
		return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
	end)
	local disc = 0
	if tower.BuffHandler then
		local ok2, d = pcall(function()
			return tower.BuffHandler:GetDiscount() or 0
		end)
		if ok2 then disc = d end
	end
	return math.floor((cost or 0) * (1 - disc))
end

local function GetTowerByX(x)
	for hash, tower in pairs(TowerClass.GetTowers()) do
		local model = tower.Character and tower.Character:GetCharacterModel()
		local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
		if root and root.Position.X == x then
			return hash, tower
		end
	end
	return nil, nil
end

-- ==== Ghi hành động và theo dõi ====
local towerRecords = {}     -- [X] = list of actions
local rebuildAttempts = {}  -- [X] = số lần thử
local soldPositions = {}    -- [X] = true nếu đã từng bán

local function logAction(actionType, data)
	local x = data.Axis
	if not x then return end
	towerRecords[x] = towerRecords[x] or {}
	table.insert(towerRecords[x], {type = actionType, data = data})
	if debugMode then warn("📌 Log", actionType, "at X =", x) end
end

-- ==== Hook ghi lại hành động ====
local old
old = hookmetamethod(game, "__namecall", function(self, ...)
	local method = getnamecallmethod()
	local args = {...}
	if method == "FireServer" then
		if self.Name == "PlaceTower" then
			local a1, name, pos, rot = unpack(args)
			logAction("Place", {
				A1 = a1,
				Name = name,
				Vector = pos,
				Rotation = rot,
				Cost = GetTowerPlaceCostByName(name),
				Axis = pos.X
			})
		elseif self.Name == "SellTower" then
			local hash = args[1]
			local tower = TowerClass.GetTowers()[hash]
			if tower then
				local model = tower.Character and tower.Character:GetCharacterModel()
				local root = model and model.PrimaryPart
				if root then
					local x = root.Position.X
					soldPositions[x] = true
					towerRecords[x] = nil -- ❌ Xoá log để ngăn rebuild lại
					if debugMode then warn("💥 Sold tower at X =", x) end
				end
			end
		elseif self.Name == "TowerUpgradeRequest" then
			local hash, path, count = unpack(args)
			local tower = TowerClass.GetTowers()[hash]
			if tower then
				local model = tower.Character and tower.Character:GetCharacterModel()
				local root = model and model.PrimaryPart
				if root then
					logAction("Upgrade", {
						Path = path,
						Count = count,
						Axis = root.Position.X
					})
				end
			end
		elseif self.Name == "ChangeQueryType" then
			local hash, typ = unpack(args)
			local tower = TowerClass.GetTowers()[hash]
			if tower then
				local model = tower.Character and tower.Character:GetCharacterModel()
				local root = model and model.PrimaryPart
				if root then
					logAction("Target", {
						Type = typ,
						Axis = root.Position.X
					})
				end
			end
		end
	end
	return old(self, ...)
end)

-- ==== Hệ thống Rebuild ====
task.spawn(function()
	while true do
		local rebuildQueue = {}

		for x, actions in pairs(towerRecords) do
			local hash, tower = GetTowerByX(x)
			if not hash and not soldPositions[x] then
				rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
				if rebuildAttempts[x] <= 10 then
					table.insert(rebuildQueue, {x = x, actions = actions, attempts = rebuildAttempts[x]})
				elseif debugMode then
					warn("❌ Bỏ qua X =", x, "sau", rebuildAttempts[x], "lần thử")
				end
			end
		end

		for _, item in ipairs(rebuildQueue) do
			local x, actions = item.x, item.actions
			if debugMode then warn("🔁 Rebuild tại X =", x, "- Lần thử:", rebuildAttempts[x]) end
			for _, act in ipairs(actions) do
				local t = act.type
				local d = act.data
				if t == "Place" then
					WaitForCash(d.Cost or 100)
					local ok = pcall(function()
						Remotes.PlaceTower:InvokeServer(d.A1, d.Name, d.Vector, d.Rotation)
					end)
					if not ok and debugMode then warn("❌ Fail Place tại X =", x) end
					task.wait(1)

				elseif t == "Upgrade" then
					for i = 1, d.Count do
						local hash2, tower2 = GetTowerByX(x)
						if hash2 and tower2 then
							local cost = GetUpgradeCost(tower2, d.Path)
							if cost then WaitForCash(cost) end
							pcall(function()
								Remotes.TowerUpgradeRequest:FireServer(hash2, d.Path, 1)
							end)
						else
							if debugMode then warn("⚠️ Không tìm thấy tower để upgrade tại X =", x) end
						end
						task.wait(0.2)
					end

				elseif t == "Target" then
					local hash2 = GetTowerByX(x)
					if hash2 then
						pcall(function()
							Remotes.ChangeQueryType:FireServer(hash2, d.Type)
						end)
					else
						if debugMode then warn("⚠️ Không tìm thấy tower để đổi target tại X =", x) end
					end
				end
			end
			task.wait(0.2)
		end

		task.wait(0.5)
	end
end)

warn("✅ Auto Rebuild (Runtime) đã khởi động – debug =", debugMode)
