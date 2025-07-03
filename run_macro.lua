-- [TDX] Macro Runner: Place/Upgrade/Sell/ChangeTarget - Place "unsure" dùng Y, Sell/Change cũng dùng Y nếu Place là unsure
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

-- Tìm tower theo X hoặc Y
local function GetTowerByAxis(axisValue, useY)
	local bestHash, bestTower, bestDist
	for hash, tower in pairs(TowerClass.GetTowers()) do
		local success, pos = pcall(function()
			local model = tower.Character:GetCharacterModel()
			local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
			return root and root.Position
		end)
		if success and pos then
			local val = useY and pos.Y or pos.X
			local dist = math.abs(val - axisValue)
			local match = dist <= 1
			if match then
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

-- Chờ đủ tiền
local function WaitForCash(amount)
	while cashStat.Value < amount do
		task.wait()
	end
end

-- Đặt tower: retry cho đến khi ra đúng vị trí (Y nếu unsure, X nếu thường)
local function PlaceTowerRetry(args, axisValue, useY, towerName)
	while true do
		Remotes.PlaceTower:InvokeServer(unpack(args))
		local placed = false
		local t0 = tick()
		repeat
			task.wait(0.1)
			local hash, tower = GetTowerByAxis(axisValue, useY)
			if hash and tower then
				placed = true
				break
			end
		until tick() - t0 > 2
		if placed then break end
		warn("[RETRY] Đặt tower thất bại, thử lại:", towerName, (useY and "Y" or "X"), "=", axisValue)
		task.wait()
	end
end

-- Nâng cấp tower: retry (dùng X)
local function UpgradeTowerRetry(axisValue, upgradePath)
	while true do
		local hash, tower = GetTowerByAxis(axisValue, false)
		if hash and tower then
			local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
			if hp and hp > 0 then
				Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)
				task.wait(0.1)
				return
			end
		end
		task.wait()
	end
end

-- ChangeTarget: retry, dùng X hoặc Y tùy PlaceMode
local function ChangeTargetRetry(axisValue, targetType, useY)
	while true do
		local hash, tower = GetTowerByAxis(axisValue, useY)
		if hash and tower then
			local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
			if hp and hp > 0 then
				Remotes.ChangeQueryType:FireServer(hash, targetType)
				task.wait(0.1)
				return
			end
		end
		task.wait()
	end
end

-- SellTower: retry, dùng X hoặc Y tùy PlaceMode
local function SellTowerRetry(axisValue, useY)
	while true do
		local hash = GetTowerByAxis(axisValue, useY)
		if hash then
			Remotes.SellTower:FireServer(hash)
			task.wait(0.1)
			local stillExist = GetTowerByAxis(axisValue, useY)
			if not stillExist then
				return
			end
		end
		task.wait(0.1)
	end
end

-- Load macro file và config
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "y"
local macroPath = "tdx/macros/" .. macroName .. ".json"
local globalPlaceMode = config["PlaceMode"] or "normal" -- "unsure" hoặc "normal"

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
		local vecTab = entry.TowerVector:split(", ")
		local pos = Vector3.new(unpack(vecTab))
		local args = {
			tonumber(entry.TowerA1),
			entry.TowerPlaced,
			pos,
			tonumber(entry.Rotation or 0)
		}
		WaitForCash(entry.TowerPlaceCost)
		local placeMode = entry.PlaceMode or globalPlaceMode
		-- Lưu ý: quyết định cho các thao tác tiếp theo
		_G.__TDX_PLACE_UNSURE = (placeMode == "unsure")
		if _G.__TDX_PLACE_UNSURE then
			PlaceTowerRetry(args, pos.Y, true, entry.TowerPlaced)    -- unsure: dùng Y
		else
			PlaceTowerRetry(args, pos.X, false, entry.TowerPlaced)   -- normal: dùng X
		end

	elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
		local axisValue = tonumber(entry.TowerUpgraded)
		UpgradeTowerRetry(axisValue, entry.UpgradePath) -- luôn dùng X, luôn retry

	elseif entry.ChangeTarget and entry.TargetType then
		local axisValue = tonumber(entry.ChangeTarget)
		-- Dùng Y nếu Place là unsure, X nếu thường
		ChangeTargetRetry(axisValue, entry.TargetType, _G.__TDX_PLACE_UNSURE or false)

	elseif entry.SellTower then
		local axisValue = tonumber(entry.SellTower)
		-- Dùng Y nếu Place là unsure, X nếu thường
		SellTowerRetry(axisValue, _G.__TDX_PLACE_UNSURE or false)
	end
end

print("✅ Macro chạy hoàn tất.")
