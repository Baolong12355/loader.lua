local HttpService = game:GetService("HttpService") local ReplicatedStorage = game:GetService("ReplicatedStorage") local Players = game:GetService("Players") local LocalPlayer = Players.LocalPlayer local Remotes = ReplicatedStorage:WaitForChild("Remotes") local TowerClass = require(LocalPlayer.PlayerScripts.Client.GameClass.TowerClass)

local recorded = {} local towerData = {}

local SAVE_FOLDER = "tdx/macros" local SAVE_NAME = "recorded.json" local SAVE_PATH = SAVE_FOLDER .. "/" .. SAVE_NAME

if typeof(isfolder) == "function" and typeof(makefolder) == "function" and not isfolder(SAVE_FOLDER) then makefolder(SAVE_FOLDER) end

local function add(entry) print("[GHI]", HttpService:JSONEncode(entry)) table.insert(recorded, entry) end

local function getTimeLeft() local ok, result = pcall(function() local text = Players.LocalPlayer :WaitForChild("PlayerGui") :WaitForChild("Interface") :WaitForChild("GameInfoBar") :WaitForChild("TimeLeft") :WaitForChild("TimeLeftText").Text

local minutes, seconds = text:match("^(%d+):(%d+)$")
	if minutes and seconds then
		return tonumber(minutes) * 60 + tonumber(seconds)
	end
end)
return ok and result or 0

end

local towerPrices = {} do local interface = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Interface") local towersBar = interface:WaitForChild("BottomBar"):WaitForChild("TowersBar")

for _, tower in ipairs(towersBar:GetChildren()) do
	if tower.Name ~= "TowerTemplate" and not tower:IsA("UIGridLayout") then
		local costFrame = tower:FindFirstChild("CostFrame")
		if costFrame then
			local costText = costFrame:FindFirstChild("CostText")
			if costText then
				local price = tonumber(costText.Text:gsub("$", "") or "0")
				towerPrices[tower.Name] = price
			end
		end
	end
end

end

spawn(function() while true do task.wait(5) if typeof(writefile) == "function" then writefile(SAVE_PATH, HttpService:JSONEncode(recorded)) else print("[Lưu JSON]", HttpService:JSONEncode(recorded)) end end end)

local function GetTowerXFromHash(hash) local tower = TowerClass.GetTower(hash) if not tower then return nil end local model = tower.Character and tower.Character:GetCharacterModel() local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) return root and tonumber(string.format("%.15f", root.Position.X)) or nil end

local oldNamecall oldNamecall = hookmetamethod(game, "__namecall", function(self, ...) local method = getnamecallmethod() if method == "FireServer" and typeof(self) == "Instance" and self:IsA("RemoteEvent") then local args = { ... } local remoteName = self.Name

if remoteName == "SellTower" and typeof(args[1]) == "number" then
		local x = GetTowerXFromHash(args[1])
		if x then add({ SellTower = x }) end

	elseif remoteName == "TowerUpgradeRequest" and typeof(args[1]) == "number" then
		local x = GetTowerXFromHash(args[1])
		if x then
			add({
				TowerUpgraded = x,
				UpgradePath = args[2],
				UpgradeCost = 0
			})
		end

	elseif remoteName == "ChangeQueryType" and typeof(args[1]) == "number" then
		local x = GetTowerXFromHash(args[1])
		if x then
			add({
				TowerTargetChange = x,
				TargetWanted = args[2],
				TargetChangedAt = getTimeLeft()
			})
		end
	end
end
return oldNamecall(self, ...)

end)

local originalInvoke = hookfunction(Remotes.PlaceTower.InvokeServer, function(self, a1, towerName, pos, rotation) add({ TowerA1 = tostring(a1), TowerPlaced = towerName, TowerVector = string.format("%.15f, %.15f, %.15f", pos.X, pos.Y, pos.Z), Rotation = rotation, TowerPlaceCost = towerPrices[towerName] or 0 }) return originalInvoke(self, a1, towerName, pos, rotation) end)

print("Macro Recorder đã sẵn sàng. Lưu file tại:", SAVE_PATH)

