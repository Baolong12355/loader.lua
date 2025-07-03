-- [TDX] Macro Runner - Position X Matching Upgrade Support (with config mode, optimized unsure repeat, and PlaceTower retry)
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

---------------------------------------------------------------------
-- Utility: Safe Require
---------------------------------------------------------------------
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

---------------------------------------------------------------------
-- Utility: Load TowerClass
---------------------------------------------------------------------
local function LoadTowerClass()
	local ps = player:WaitForChild("PlayerScripts")
	local client = ps:WaitForChild("Client")
	local gameClass = client:WaitForChild("GameClass")
	local towerModule = gameClass:WaitForChild("TowerClass")
	return SafeRequire(towerModule)
end

local TowerClass = LoadTowerClass()
if not TowerClass then error("Không thể tải TowerClass") end

---------------------------------------------------------------------
-- Utility: Find tower by X position (normal/unsure)
---------------------------------------------------------------------
local function FindTowerByX(xTarget, unsureMode)
    local bestHash, bestTower, bestDist
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local success, pos = pcall(function()
            local model = tower.Character:GetCharacterModel()
            local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
            return root and root.Position
        end)
        if success and pos then
            local dist = math.abs(pos.X - xTarget)
            local match = (unsureMode and dist <= 0.99) or (not unsureMode and dist < 0.99)
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

---------------------------------------------------------------------
-- Utility: Wait for enough cash
---------------------------------------------------------------------
local function WaitForCash(amount)
	while cashStat.Value < amount do
		task.wait()
	end
end

---------------------------------------------------------------------
-- Utility: Retry PlaceTower until success
---------------------------------------------------------------------
local function PlaceTowerRetry(args, posX, towerName, retryWait)
    retryWait = retryWait or 0.1
    while true do
        Remotes.PlaceTower:InvokeServer(unpack(args))
        -- Kiểm tra tower đã xuất hiện tại vị trí X & còn sống (max 2s)
        local placed = false
        local t0 = tick()
        repeat
            task.wait()
            local hash, tower = FindTowerByX(posX, true)
            if hash and tower then
                placed = true
                break
            end
        until tick() - t0 > 2
        if placed then
            break
        end
        warn("[RETRY] Đặt tower thất bại, thử lại:", towerName, "tại X =", posX)
        task.wait(retryWait)
    end
end

---------------------------------------------------------------------
-- Utility: Upgrade tower unsure mode (loop until success)
---------------------------------------------------------------------
local function UpgradeTowerUnsure(towerX, upgradePath)
    while true do
        local hash, tower = FindTowerByX(towerX, true)
        if hash and tower then
            local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
            if hp and hp > 0 then
                Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)
                task.wait(0.1)
                return -- Thành công, thoát vòng lặp
            end
        end
        task.wait() -- Đợi rồi thử lại
    end
end

---------------------------------------------------------------------
-- Load macro file & config
---------------------------------------------------------------------
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "y"
local macroPath = "tdx/macros/" .. macroName .. ".json"
local globalUpgradeMode = config["UpgradeMode"] or "normal" -- "unsure" hoặc "normal"
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

---------------------------------------------------------------------
-- MAIN: Run macro
---------------------------------------------------------------------
for i, entry in ipairs(macro) do
	------------------- PLACE TOWER --------------------
	if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
		local pos = Vector3.new(unpack(entry.TowerVector:split(", ")))
		local args = {
			tonumber(entry.TowerA1),
			entry.TowerPlaced,
			pos,
			tonumber(entry.Rotation or 0)
		}
		WaitForCash(entry.TowerPlaceCost)
		local mode = entry.PlaceMode or globalPlaceMode
		if mode == "unsure" then
			PlaceTowerRetry(args, pos.X, entry.TowerPlaced)
		else
			Remotes.PlaceTower:InvokeServer(unpack(args))
			task.wait(0.1)
		end

	------------------- UPGRADE TOWER ------------------
	elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
		local towerX = tonumber(entry.TowerUpgraded)
		local mode = entry.UpgradeMode or globalUpgradeMode
		if mode == "unsure" then
			UpgradeTowerUnsure(towerX, entry.UpgradePath)
		else
			local hash, tower = FindTowerByX(towerX, false)
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
		end

	------------------- CHANGE TARGET ------------------
	elseif entry.ChangeTarget and entry.TargetType then
		local towerX = tonumber(entry.ChangeTarget)
		local hash, tower = FindTowerByX(towerX, false)
		if not hash or not tower then continue end
		local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
		if not hp or hp <= 0 then continue end
		Remotes.ChangeQueryType:FireServer(hash, entry.TargetType)
		task.wait(0.1)

	------------------- SELL TOWER ---------------------
	elseif entry.SellTower then
		local towerX = tonumber(entry.SellTower)
		local hash = FindTowerByX(towerX, false)
		if hash then
			Remotes.SellTower:FireServer(hash)
			task.wait(0.1)
		end
	end
end

print("✅ Macro chạy hoàn tất.")
