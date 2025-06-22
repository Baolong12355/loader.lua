-- 📜 FIXED TDX Macro Recorder – HOOK NAMECALL thay vì OnClientEvent
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TowerClass = require(LocalPlayer.PlayerScripts.Client.GameClass.TowerClass)

local recorded = {}
local towerData = {}

local SAVE_FOLDER = "tdx/macros"
local SAVE_NAME = "recorded.json"
local SAVE_PATH = SAVE_FOLDER .. "/" .. SAVE_NAME

if not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end

local function add(entry)
	print("📝 Ghi:", HttpService:JSONEncode(entry))
	table.insert(recorded, entry)
end

-- Tự động lưu file
task.spawn(function()
	while true do
		task.wait(5)
		writefile(SAVE_PATH, HttpService:JSONEncode(recorded))
		print("💾 Đã lưu:", #recorded, "entry.")
	end
end)

-- 🎯 Target Type map
local TargetMap = {
	First = 0, Last = 1, Strongest = 2, Weakest = 3, Closest = 4, Farthest = 5
}

-- ✅ Hook PlaceTower (InvokeServer)
local originalInvoke = hookfunction(Remotes.PlaceTower.InvokeServer, function(self, a1, towerName, pos, rotation)
	add({
		TowerA1 = tostring(a1),
		TowerPlaced = towerName,
		TowerVector = string.format("%.15f, %.15f, %.15f", pos.X, pos.Y, pos.Z),
		Rotation = rotation,
		TowerPlaceCost = 0
	})
	return originalInvoke(self, a1, towerName, pos, rotation)
end)

-- ✅ Hook FireServer cho Sell, Upgrade, Target Change
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
	local method = getnamecallmethod()
	if method == "FireServer" and typeof(self) == "Instance" and self:IsA("RemoteEvent") then
		local args = { ... }
		local remoteName = self.Name

		if remoteName == "SellTower" and typeof(args[1]) == "number" then
			add({ SellTower = args[1] })

		elseif remoteName == "TowerUpgradeRequest" and typeof(args[1]) == "number" and typeof(args[2]) == "number" then
			add({
				TowerUpgraded = args[1],
				UpgradePath = args[2],
				UpgradeCost = 0
			})

		elseif remoteName == "ChangeQueryType" and typeof(args[1]) == "number" and typeof(args[2]) == "number" then
			add({
				TowerTargetChange = args[1],
				TargetWanted = args[2],
				TargetChangedAt = math.floor(tick())
			})
		end
	end
	return oldNamecall(self, ...)
end)

print("✅ Macro Recorder đã HOẠT ĐỘNG. Ghi mọi hành động gửi qua Remote.")
