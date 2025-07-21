-- [[ Auto Rebuild Runtime - Hook như record.lua - No Macro - Debug ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local debugMode = true

-- === Load TowerClass
local TowerClass
do
	local ps = player:WaitForChild("PlayerScripts")
	local client = ps:WaitForChild("Client")
	local gameClass = client:WaitForChild("GameClass")
	local towerModule = gameClass:WaitForChild("TowerClass")
	TowerClass = require(towerModule)
end

-- === Tools
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

-- === Data
local towerRecords = {}     -- [X] = list of actions
local rebuildAttempts = {}  -- [X] = số lần thử
local soldPositions = {}    -- [X] = true nếu đã bán

-- === Ghi log
local function logAction(actionType, data)
	local x = data.Axis
	if not x then return end
	towerRecords[x] = towerRecords[x] or {}
	table.insert(towerRecords[x], {type = actionType, data = data})
	if debugMode then warn("📌 Log", actionType, "at X =", x) end
end

-- === Hook chuẩn như record
local raw
raw = hookmetamethod(game, "__namecall", function(self, ...)
	local method = getnamecallmethod()
	local args = { ... }

	if not checkcaller() and typeof(self) == "Instance" and self:IsA("RemoteEvent") or self:IsA("RemoteFunction") then
		local name = self.Name

		if name == "PlaceTower" and method == "InvokeServer" then
			local a1, name, pos, rot = unpack(args)
			logAction("Place", {
				A1 = a1,
				Name = name,
				Vector = pos,
				Rotation = rot,
				Cost = GetTowerPlaceCostByName(name),
				Axis = pos.X
			})
		elseif name == "SellTower" then
			local hash = args[1]
			local tower = TowerClass.GetTowers()[hash]
			if tower then
				local model = tower.Character and tower.Character:GetCharacterModel()
				local root = model and model.PrimaryPart
				if root then
					local x = root.Position.X
					soldPositions[x] = true
					towerRecords[x] = nil
					if debugMode then warn("💥 Bán tower tại X =", x) end
				end
			end
		elseif name == "TowerUpgradeRequest" then
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
		elseif name == "ChangeQueryType" then
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

	return raw(self, ...)
end)

-- === Rebuild Loop
task.spawn(function()
	while true do
		local queue = {}

		for x, actions in pairs(towerRecords) do
			local hash = GetTowerByX(x)
			if not hash and not soldPositions[x] then
				rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
				if rebuildAttempts[x] <= 10 then
					table.insert(queue, {x = x, actions = actions})
				else
					if debugMode then warn("❌ Bỏ qua X =", x, "sau quá 10 lần thử") end
				end
			end
		end

		for _, entry in ipairs(queue) do
			local x, actions = entry.x, entry.actions
			if debugMode then warn("🔁 Rebuild tại X =", x) end
			for _, act in ipairs(actions) do
				local t, d = act.type, act.data
				if t == "Place" then
					WaitForCash(d.Cost or 100)
					local ok = pcall(function()
						Remotes.PlaceTower:InvokeServer(d.A1, d.Name, d.Vector, d.Rotation)
					end)
					if not ok and debugMode then warn("❌ Place thất bại tại X =", x) end
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
						if debugMode then warn("⚠️ Không tìm thấy tower để set target tại X =", x) end
					end
				end
			end
			task.wait(0.2)
		end

		task.wait(0.5)
	end
end)

warn("✅ Auto Rebuild Runtime đã khởi động – Debug:", debugMode)