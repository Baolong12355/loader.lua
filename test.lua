
repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Safe require TowerClass
local function SafeRequire(module)
local success, result = pcall(require, module)
return success and result or nil
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

-- Tìm tower gần đúng theo X
local function GetTowerByAxis(axisX)
local bestHash, bestTower, bestDist
for hash, tower in pairs(TowerClass.GetTowers()) do
local success, pos = pcall(function()
local model = tower.Character:GetCharacterModel()
local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
return root and root.Position
end)
if success and pos then
local dist = math.abs(pos.X - axisX)
if dist <= 1 then
local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
if hp and hp > 0 then
if not bestDist or dist < bestDist then
bestHash, bestTower, bestDist = hash, tower, dist
end
end
end
end
end
return bestHash, bestTower
end

-- Lấy giá đặt tower theo tên
local function GetTowerPlaceCostByName(name)
local playerGui = player:FindFirstChild("PlayerGui")
if not playerGui then return 0 end
local interface = playerGui:FindFirstChild("Interface")
if not interface then return 0 end
local bottomBar = interface:FindFirstChild("BottomBar")
if not bottomBar then return 0 end
local towersBar = bottomBar:FindFirstChild("TowersBar")
if not towersBar then return 0 end

for _, tower in ipairs(towersBar:GetChildren()) do  
	if tower.Name == name then  
		local costFrame = tower:FindFirstChild("CostFrame")  
		local costText = costFrame and costFrame:FindFirstChild("CostText")  
		if costText then  
			local raw = tostring(costText.Text):gsub("%D", "")  
			return tonumber(raw) or 0  
		end  
	end  
end  
return 0

end

-- Lấy giá nâng cấp
local function GetCurrentUpgradeCosts(tower)
if not tower or not tower.LevelHandler then
return {
path1 = {cost = "N/A", currentLevel = "N/A", maxLevel = "N/A", exists = true},
path2 = {cost = "N/A", currentLevel = "N/A", maxLevel = "N/A", exists = false}
}
end

local result = {  
	path1 = {cost = "MAX", currentLevel = 0, maxLevel = 0, exists = true},  
	path2 = {cost = "MAX", currentLevel = 0, maxLevel = 0, exists = false}  
}  

local maxLevel = tower.LevelHandler:GetMaxLevel()  
local lvl1 = tower.LevelHandler:GetLevelOnPath(1)  
result.path1.currentLevel = lvl1  
result.path1.maxLevel = maxLevel  

if lvl1 < maxLevel then  
	local ok, cost = pcall(function()  
		return tower.LevelHandler:GetLevelUpgradeCost(1, 1)  
	end)  
	result.path1.cost = ok and math.floor(cost) or "LỖI"  
end  

local hasPath2 = pcall(function()  
	return tower.LevelHandler:GetLevelOnPath(2) ~= nil  
end)  

if hasPath2 then  
	result.path2.exists = true  
	local lvl2 = tower.LevelHandler:GetLevelOnPath(2)  
	result.path2.currentLevel = lvl2  
	result.path2.maxLevel = maxLevel  

	if lvl2 < maxLevel then  
		local ok2, cost2 = pcall(function()  
			return tower.LevelHandler:GetLevelUpgradeCost(2, 1)  
		end)  
		result.path2.cost = ok2 and math.floor(cost2) or "LỖI"  
	end  
end  

return result

end

-- Chờ đủ tiền
local function WaitForCash(amount)
while cashStat.Value < amount do task.wait() end
end

-- Đặt tower
local function PlaceTowerRetry(args, axisX, towerName, cost)
for i = 1, 10 do
print(string.format("🧱 [Place Attempt %d] %s tại X=%.2f", i, towerName, axisX))
WaitForCash(cost)
Remotes.PlaceTower:InvokeServer(unpack(args))
local t0 = tick()
repeat
task.wait(0.1)
local hash, tower = GetTowerByAxis(axisX)
if hash and tower then
print(string.format("✅ [Placed] %s tại X=%.2f", towerName, axisX))
return true
end
until tick() - t0 > 2
print(string.format("❌ [Place Retry] Thất bại (%d/10): %s tại X=%.2f", i, towerName, axisX))
end
warn("[Place Retry] ❌ Đặt thất bại hoàn toàn:", towerName)
return false
end

-- Nâng cấp tower
local function UpgradeTowerRetry(axisX, upgradePath)
for attempt = 1, 5 do
local hash, tower = GetTowerByAxis(axisX)
if not hash or not tower then
print(string.format("❌ [Upgrade] Không tìm thấy tower tại X=%.2f", axisX))
return
end

local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()  
	if not hp or hp <= 0 then  
		print(string.format("❌ [Upgrade] Tower tại X=%.2f đã bị tiêu diệt", axisX))  
		return  
	end  

	local costInfo = GetCurrentUpgradeCosts(tower)  
	local info = upgradePath == 1 and costInfo.path1 or costInfo.path2  

	if info.cost == "MAX" then  
		print(string.format("⚠️ [Upgrade] Tower X=%.2f đã max cấp (Path %d)", axisX, upgradePath))  
		return  
	end  
	if info.cost == "LỖI" or type(info.cost) ~= "number" then  
		print(string.format("❗ [Upgrade] Không thể lấy giá nâng cấp X=%.2f | Path=%d", axisX, upgradePath))  
		return  
	end  

	print(string.format("🔧 [Upgrade] X=%.2f | Path=%d | Level=%d | Cost=%d | Attempt=%d", axisX, upgradePath, info.currentLevel, info.cost, attempt))  

	WaitForCash(info.cost)  
	Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)  

	local t0 = tick()  
	while tick() - t0 < 1.5 do  
		task.wait(0.1)  
		local _, t = GetTowerByAxis(axisX)  
		if t and t.LevelHandler then  
			local newLevel = t.LevelHandler:GetLevelOnPath(upgradePath)  
			if newLevel > info.currentLevel then  
				print(string.format("✅ [Upgrade Success] X=%.2f | Path=%d | New Level=%d", axisX, upgradePath, newLevel))  
				return  
			end  
		end  
	end  

	print(string.format("❌ [Upgrade Failed] X=%.2f | Path=%d | Không nâng được", axisX, upgradePath))  
	task.wait(0.2)  
end

end

-- Bán tower
local function SellTowerRetry(axisX)
for _ = 1, 3 do
local hash = GetTowerByAxis(axisX)
if hash then
Remotes.SellTower:FireServer(hash)
task.wait(0.2)
if not GetTowerByAxis(axisX) then return end
else
return
end
task.wait(0.1)
end
end

-- Đổi target
local function ChangeTargetRetry(axisX, targetType)
for _ = 1, 3 do
local hash = GetTowerByAxis(axisX)
if hash then
Remotes.ChangeQueryType:FireServer(hash, targetType)
return
end
task.wait(0.1)
end
end

-- Load macro
local config = getgenv().TDX_Config or {}
local macroPath = config["Macro Path"] or "tdx/macros/x.json"

if not isfile(macroPath) then
error("Không tìm thấy macro: " .. macroPath)
end

local success, macro = pcall(function()
return HttpService:JSONDecode(readfile(macroPath))
end)
if not success then error("Lỗi khi đọc macro") end

-- Chạy macro
for _, entry in ipairs(macro) do
if entry.TowerPlaced and entry.TowerVector then
local vecTab = entry.TowerVector:split(", ")
local pos = Vector3.new(unpack(vecTab))
local args = {
tonumber(entry.TowerA1),
entry.TowerPlaced,
pos,
tonumber(entry.Rotation or 0)
}
local cost = tonumber(entry.TowerPlaceCost) or 0
if cost == 0 then
cost = GetTowerPlaceCostByName(entry.TowerPlaced)
end
PlaceTowerRetry(args, pos.X, entry.TowerPlaced, cost)

elseif entry.TowerUpgraded and entry.UpgradePath then  
	local axisValue = tonumber(entry.TowerUpgraded)  
	UpgradeTowerRetry(axisValue, tonumber(entry.UpgradePath))  

elseif entry.ChangeTarget and entry.TargetType then  
	local axisValue = tonumber(entry.ChangeTarget)  
	ChangeTargetRetry(axisValue, tonumber(entry.TargetType))  

elseif entry.SellTower then  
	local axisValue = tonumber(entry.SellTower)  
	SellTowerRetry(axisValue)  
end

end

print("✅ rewrite_unsure hoàn tất.")

