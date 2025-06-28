-- [TDX] Macro Runner - Position X Matching Upgrade Support
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Load TowerClass
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

-- Lấy hash tower theo vị trí X (±0.1)
local function GetTowerByX(xTarget)
	for hash, tower in pairs(TowerClass.GetTowers()) do
		local success, pos = pcall(function()
			local model = tower.Character:GetCharacterModel()
			local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
			return root and root.Position
		end)
		if success and pos and math.abs(pos.X - xTarget) < 0.1 then
			return hash, tower
		end
	end
	return nil
end

-- Chờ có đủ tiền
local function WaitForCash(amount)
	while cashStat.Value < amount do
		task.wait()
	end
end

-- Load macro file
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "y"
local macroPath = "tdx/macros/" .. macroName .. ".json"

if not isfile(macroPath) then
	error("Không tìm thấy macro file: " .. macroPath)
end

local success, macro = pcall(function()
	return HttpService:JSONDecode(readfile(macroPath))
end)
if not success then
	error("Lỗi khi đọc macro")
end

-- Chạy macro
for i, entry in ipairs(macro) do
	if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
		local pos = Vector3.new(unpack(entry.TowerVector:split(", ")))
		local args = {
			tonumber(entry.TowerA1),
			entry.TowerPlaced,
			pos,
			tonumber(entry.Rotation or 0)
		}
		WaitForCash(entry.TowerPlaceCost)
		Remotes.PlaceTower:InvokeServer(unpack(args))
		task.wait(0.1)

	elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
		local towerX = tonumber(entry.TowerUpgraded)
		local hash, tower = GetTowerByX(towerX)
		if not hash or not tower then
			warn("[SKIP] Không tìm thấy tower tại X =", towerX)
			continue
		end
		local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
		if not hp or hp <= 0 then
			warn("[SKIP] Tower tại X =", towerX, "đã chết")
			continue
		end
		WaitForCash(entry.UpgradeCost)
		Remotes.TowerUpgradeRequest:FireServer(hash, entry.UpgradePath, 1)
		task.wait(0.1)

	elseif entry.ChangeTarget and entry.TargetType then
		local towerX = tonumber(entry.ChangeTarget)
		local hash, tower = GetTowerByX(towerX)
		if not hash or not tower then continue end
		local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
		if not hp or hp <= 0 then continue end
		Remotes.ChangeQueryType:FireServer(hash, entry.TargetType)
		task.wait(0.1)

	elseif entry.SellTower then
		local towerX = tonumber(entry.SellTower)
		local hash = GetTowerByX(towerX)
		if hash then
			Remotes.SellTower:FireServer(hash)
			task.wait(0.1)
		end
	end
end

print("✅ Macro chạy hoàn tất.")
