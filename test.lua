-- ⚙️ Auto Rebuild Runtime - Không cần macro - Theo cơ chế run_macro.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- TowerClass
local TowerClass = require(player.PlayerScripts.Client.GameClass.TowerClass)

-- 🧠 Dữ liệu rebuild
local towerRecords = {}        -- [x] = list of actions (place, upgrade, etc.)
local soldPositions = {}       -- [x] = true nếu đã bị bán
local rebuildAttempts = {}     -- [x] = số lần thử
local maxRetry = 10

-- 🔧 Công cụ
local function GetTowerByX(x)
	for hash, tower in pairs(TowerClass.GetTowers()) do
		local model = tower.Character and tower.Character:GetCharacterModel()
		local root = model and model.PrimaryPart
		if root and math.floor(root.Position.X) == math.floor(x) then
			return hash, tower
		end
	end
	return nil, nil
end

local function WaitForCash(target)
	local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")
	repeat task.wait() until cash.Value >= target
end

local function GetPlaceCost(towerName)
	local gui = player:FindFirstChild("PlayerGui")
	local interface = gui and gui:FindFirstChild("Interface")
	local bar = interface and interface:FindFirstChild("BottomBar")
	local towersBar = bar and bar:FindFirstChild("TowersBar")
	if not towersBar then return 0 end

	for _, btn in pairs(towersBar:GetChildren()) do
		if btn.Name == towerName then
			local costText = btn:FindFirstChild("CostFrame") and btn.CostFrame:FindFirstChild("CostText")
			if costText then
				return tonumber(costText.Text:match("%d+")) or 0
			end
		end
	end
	return 0
end

local function GetUpgradeCost(tower, path)
	if not tower or not tower.LevelHandler then return 0 end
	local cost = tower.LevelHandler:GetLevelUpgradeCost(path, 1)
	local discount = tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0
	return math.floor(cost * (1 - discount))
end

-- 📌 Ghi lại hành động
local function logAction(x, act)
	towerRecords[x] = towerRecords[x] or {}
	table.insert(towerRecords[x], act)
end

-- 🪝 Hook để ghi hành động
local old
old = hookmetamethod(game, "__namecall", function(self, ...)
	local method = getnamecallmethod()
	local args = { ... }

	if not checkcaller() and typeof(self) == "Instance" and self:IsA("RemoteEvent") or self:IsA("RemoteFunction") then
		local name = self.Name

		if name == "PlaceTower" and method == "InvokeServer" then
			local a1, towerName, pos, rot = unpack(args)
			local cost = GetPlaceCost(towerName)
			logAction(pos.X, {type = "Place", data = {a1 = a1, name = towerName, pos = pos, rot = rot, cost = cost}})
		elseif name == "SellTower" then
			local hash = args[1]
			local tower = TowerClass.GetTowers()[hash]
			if tower then
				local model = tower.Character and tower.Character:GetCharacterModel()
				local root = model and model.PrimaryPart
				if root then
					local x = math.floor(root.Position.X)
					soldPositions[x] = true
					towerRecords[x] = nil
				end
			end
		elseif name == "TowerUpgradeRequest" then
			local hash, path, count = unpack(args)
			local tower = TowerClass.GetTowers()[hash]
			if tower then
				local root = tower.Character and tower.Character:GetCharacterModel().PrimaryPart
				if root then
					logAction(root.Position.X, {type = "Upgrade", data = {path = path, count = count}})
				end
			end
		elseif name == "ChangeQueryType" then
			local hash, mode = unpack(args)
			local tower = TowerClass.GetTowers()[hash]
			if tower then
				local root = tower.Character and tower.Character:GetCharacterModel().PrimaryPart
				if root then
					logAction(root.Position.X, {type = "Target", data = {mode = mode}})
				end
			end
		end
	end

	return old(self, ...)
end)

-- 🔁 Rebuild loop
task.spawn(function()
	while true do
		for x, actions in pairs(towerRecords) do
			local hash = GetTowerByX(x)
			if not hash and not soldPositions[x] then
				rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
				if rebuildAttempts[x] > maxRetry then
					warn("🚫 Bỏ qua X =", x, "sau quá", maxRetry, "lần thử")
					towerRecords[x] = nil
				else
					task.spawn(function()
						for _, act in ipairs(actions) do
							if act.type == "Place" then
								local d = act.data
								WaitForCash(d.cost)
								local ok = pcall(function()
									Remotes.PlaceTower:InvokeServer(d.a1, d.name, d.pos, d.rot)
								end)
								if not ok then warn("❌ Lỗi Place tại X =", x) end
								task.wait(0.5)
							elseif act.type == "Upgrade" then
								for i = 1, act.data.count do
									local hash2, tower2 = GetTowerByX(x)
									if tower2 then
										local cost = GetUpgradeCost(tower2, act.data.path)
										WaitForCash(cost)
										pcall(function()
											Remotes.TowerUpgradeRequest:FireServer(hash2, act.data.path, 1)
										end)
									end
									task.wait(0.2)
								end
							elseif act.type == "Target" then
								local hash2 = GetTowerByX(x)
								if hash2 then
									pcall(function()
										Remotes.ChangeQueryType:FireServer(hash2, act.data.mode)
									end)
								end
							end
						end
					end)
				end
			end
		end
		task.wait(0.25)
	end
end)

warn("✅ Auto Rebuild Runtime đã khởi động – không cần macro – tối ưu")