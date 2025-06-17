local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TowersFolder = Workspace:WaitForChild("Game"):WaitForChild("Towers")

local config = getgenv().TDX_Config or {}
local mode = config["Macros"] or "run"
local macroName = config["Macro Name"] or "y"
local macroPath = "tdx/macros/" .. macroName .. ".json"

-- 💠 Bảng lưu các tower đã rename
local renamed = {}
local renameIndex = 1

-- 🌀 Luôn kiểm tra tower mới để rename
task.spawn(function()
	while true do
		for _, tower in ipairs(TowersFolder:GetChildren()) do
			if not renamed[tower] and tower:IsA("Model") then
				if not tower.Name:match("^%d+%.") then
					tower.Name = renameIndex .. "." .. tower.Name
					renamed[tower] = true
					renameIndex += 1
					print("🔁 Đổi tên tower:", tower.Name)
				end
			end
		end
		task.wait(0.3)
	end
end)

-- 🪙 Đợi đủ tiền
local function waitUntilCashEnough(amount)
	while cashStat.Value < amount do task.wait() end
end

-- 🔍 Tìm tower theo số thứ tự
local function findTowerByIndex(index)
	for _, tower in ipairs(TowersFolder:GetChildren()) do
		local num = tonumber(tower.Name:match("^(%d+)"))
		if num == tonumber(index) then
			return tower
		end
	end
end

-- ▶️ CHẠY MACROS
if mode == "run" then
	local macro = HttpService:JSONDecode(readfile(macroPath))

	for _, entry in ipairs(macro) do
		if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
			local x, y, z = entry.TowerVector:match("([^,]+), ([^,]+), ([^,]+)")
			local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
			local args = {
				tonumber(entry.TowerA1),
				entry.TowerPlaced,
				pos,
				tonumber(entry.Rotation) or 0
			}

			waitUntilCashEnough(entry.TowerPlaceCost)
			Remotes.PlaceTower:InvokeServer(unpack(args))
			task.wait(0.4)

		elseif entry.TowerIndex and entry.UpgradePath and entry.UpgradeCost then
			waitUntilCashEnough(entry.UpgradeCost)
			for _ = 1, 20 do
				local tower = findTowerByIndex(entry.TowerIndex)
				if tower then
					local before = cashStat.Value
					Remotes.TowerUpgradeRequest:FireServer(entry.TowerIndex, entry.UpgradePath, 1)
					task.wait(0.3)
					if cashStat.Value < before then
						break
					end
				end
				task.wait(0.2)
			end

		elseif entry.ChangeTarget and entry.TargetType then
			Remotes.ChangeQueryType:FireServer(entry.ChangeTarget, entry.TargetType)
			task.wait(0.2)

		elseif entry.SellTower then
			Remotes.SellTower:FireServer(entry.SellTower)
			task.wait(0.2)
		end
	end

	print("✅ Đã hoàn
