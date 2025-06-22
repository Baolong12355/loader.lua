-- 📜 TDX Macro Recorder (Executor + /record on|off + ooooo.json Format)
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TowerClass = require(LocalPlayer.PlayerScripts.Client.GameClass.TowerClass)

-- ⚙️ Cấu hình lưu file
local SAVE_FOLDER = "tdx/macros"
local MACRO_NAME = getgenv().TDX_Config and getgenv().TDX_Config["Macro Name"] or "recorded"
local SAVE_PATH = SAVE_FOLDER .. "/" .. MACRO_NAME .. ".json"
getgenv().TDX_RecordEnabled = true

-- 📦 Biến toàn cục
local recorded = {}
local towerData = {}

if not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end

local function add(entry)
	if getgenv().TDX_RecordEnabled then
		table.insert(recorded, entry)
	end
end

-- Tự động lưu mỗi 5s
task.spawn(function()
	while true do
		task.wait(5)
		pcall(function()
			writefile(SAVE_PATH, HttpService:JSONEncode(recorded))
		end)
	end
end)

-- 🎯 Target type mapping
local TargetMap = {
	First = 0, Last = 1, Strongest = 2, Weakest = 3, Closest = 4, Farthest = 5
}

-- ✅ Hook đặt tower
local originalInvoke = hookfunction(Remotes.PlaceTower.InvokeServer, function(self, towerA1, towerName, pos, rotation)
	local config = require(ReplicatedStorage:WaitForChild("TDX_Shared"):WaitForChild("Common"):WaitForChild("ResourceManager")).GetTowerConfig(towerName)
	local cost = config and config.UpgradePathData.BaseLevelData.Cost or 0

	add({
		TowerA1 = tostring(towerA1),
		TowerPlaced = towerName,
		TowerVector = string.format("%.15f, %.15f, %.15f", pos.X, pos.Y, pos.Z),
		Rotation = rotation,
		TowerPlaceCost = cost
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

	return originalInvoke(self, towerA1, towerName, pos, rotation)
end)

-- 🔼 Upgrade
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

-- 🎯 Change Target
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

-- ❌ Sell
Remotes.SellTower.OnClientEvent:Connect(function(hash)
	local tower = TowerClass.GetTower(hash)
	if not tower then return end

	local model = tower.Character:GetCharacterModel()
	local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
	if not root then return end

	local x = tonumber(string.format("%.15f", root.Position.X))
	add({ SellTower = x })
end)

-- 💬 Chat command: /record on | /record off
local function handleChatCommand(msg)
	local args = string.split(msg:lower(), " ")
	if args[1] == "/record" then
		if args[2] == "on" then
			getgenv().TDX_RecordEnabled = true
			print("✅ Ghi macro đã bật")
		elseif args[2] == "off" then
			getgenv().TDX_RecordEnabled = false
			print("❌ Ghi macro đã tắt")
		end
	end
end

-- 🔁 Chat system compatibility (TextChatService mới + chat cũ)
local function setupChatCommand()
	local TextChatService = game:GetService("TextChatService")
	local channel = TextChatService:FindFirstChild("TextChannels") and TextChatService.TextChannels:FindFirstChild("RBXGeneral")

	if channel then
		channel.OnIncomingMessage = function(message)
			local source = message.TextSource
			if source and source.UserId == Players.LocalPlayer.UserId then
				handleChatCommand(message.Text)
			end
		end
	else
		-- fallback chat cũ
		LocalPlayer.Chatted:Connect(handleChatCommand)
	end
end

setupChatCommand()

print("🎥 [TDX Macro Recorder] Sẵn sàng! Gõ /record on hoặc /record off")
print("📁 Macro sẽ được lưu vào: " .. SAVE_PATH)
