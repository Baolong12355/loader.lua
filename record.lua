-- 📜 TDX Macro Recorder - Đúng định dạng ooooo.json
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TowerClass = require(LocalPlayer.PlayerScripts.Client.GameClass.TowerClass)

local SAVE_FOLDER = "tdx/macros"
local MACRO_NAME = getgenv().TDX_Config and getgenv().TDX_Config["Macro Name"] or "recorded"
local SAVE_PATH = SAVE_FOLDER .. "/" .. MACRO_NAME .. ".json"

local recorded = {}
local towerData = {}

if not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end
local function add(entry) table.insert(recorded, entry) end

task.spawn(function()
	while true do
		task.wait(5)
		pcall(function()
			writefile(SAVE_PATH, HttpService:JSONEncode(recorded))
		end)
	end
end)

local TargetMap = {
	First = 0, Last = 1, Strongest = 2, Weakest = 3, Closest = 4, Farthest = 5
}

-- 📌 Đặt tower
Remotes.PlaceTower.OnClientEvent:Connect(function(_, towerType, pos, rotation)
	local config = require(ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common"):WaitForChild("ResourceManager")).GetTowerConfig(towerType)
	local cost = config and config.UpgradePathData.BaseLevelData.Cost or 0
	local vec = string.format("%.15f, %.15f, %.15f", pos.X, pos.Y, pos.Z)
	local timeKey = tostring(tick())

	add({
		TowerPlaced = towerType,
		TowerVector = vec,
		Rotation = rotation,
		TowerPlaceCost = cost,
		TowerA1 = timeKey
	})

	task.delay(0.2, function()
		for hash, tower in pairs(TowerClass.GetTowers()) do
			local model = tower.Character and tower.Character:GetCharacterModel()
			local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
			if root and (root.Position - pos).Magnitude < 0.1 then
				towerData[hash] = {
					path1Level = tower.LevelHandler:GetLevelOnPath(1),
					path2Level = tower.LevelHandler:GetLevelOnPath(2)
				}
			end
		end
	end)
end)

-- 🔼 Nâng cấp
Remotes.TowerUpgradeRequest.OnClientEvent:Connect(function(hash, path, _)
	local tower = TowerClass.GetTower(hash)
	if not tower then return end

	local model = tower.Character:GetCharacterModel()
	local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
	if not root then return end

	local x = tonumber(string.format("%.15f", root.Position.X))
	local new1 = tower.LevelHandler:GetLevelOnPath(1)
	local new2 = tower.LevelHandler:GetLevelOnPath(2)
	local upgradedPath = path

	local old = towerData[hash]
	if old then
		if new1 > old.path1Level then upgradedPath = 1
		elseif new2 > old.path2Level then upgradedPath = 2 end
	end

	towerData[hash] = { path1Level = new1, path2Level = new2 }

	add({
		TowerUpgraded = x,
		UpgradePath = upgradedPath,
		UpgradeCost = tower.LevelHandler:GetLevelUpgradeCost(upgradedPath, 1)
	})
end)

-- 🎯 Đổi target
Remotes.ChangeQueryType.OnClientEvent:Connect(function(hash, targetType)
	local tower = TowerClass.GetTower(hash)
	if not tower then return end

	local model = tower.Character:GetCharacterModel()
	local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
	if not root then return end

	local x = tonumber(string.format("%.15f", root.Position.X))
	local targetNum = TargetMap[targetType] or -1

	add({
		TowerTargetChange = x,
		TargetWanted = targetNum,
		TargetChangedAt = math.floor(tick())
	})
end)

-- ❌ Bán tower
Remotes.SellTower.OnClientEvent:Connect(function(hash)
	local tower = TowerClass.GetTower(hash)
	if not tower then return end

	local model = tower.Character:GetCharacterModel()
	local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
	if not root then return end

	local x = tonumber(string.format("%.15f", root.Position.X))

	add({
		SellTower = x
	})
end)

print("🎥 Đang ghi macro đúng định dạng ooooo.json... sẽ lưu tại:\n📁 " .. SAVE_PATH)
