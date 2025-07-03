-- [TDX] Macro Runner - Position X Matching Upgrade Support (PlaceTower retry until success - robust TowerVector parsing)
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

-- Tìm tower theo X, với tuỳ chọn unsure (tìm quanh vị trí)
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
            local match = (unsureMode and dist <= 0.95) or (not unsureMode and dist < 0.91)
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

-- Chờ có đủ tiền
local function WaitForCash(amount)
	while cashStat.Value < amount do
		task.wait()
	end
end

-- Lặp lại đặt tower cho đến khi thành công (tower xuất hiện đúng vị trí)
local function PlaceTowerRepeat(args, towerX, cost)
    while true do
        WaitForCash(cost)
        Remotes.PlaceTower:InvokeServer(unpack(args))
        task.wait(0.1)
        local hash, tower = FindTowerByX(towerX, false)
        if hash and tower then
            local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
            if hp and hp > 0 then
                return
            end
        end
    end
end

-- Nâng cấp tower ở chế độ unsure: lặp đến khi thành công
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
        task.wait()
    end
end

-- Load macro file và config
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "y"
local macroPath = "tdx/macros/" .. macroName .. ".json"
local globalUpgradeMode = config["UpgradeMode"] or "normal" -- "unsure" hoặc "normal"

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
		-- Phân tách TowerVector an toàn
		local x, y, z = string.match(entry.TowerVector, "([^,]+),%s*([^,]+),%s*([^,]+)")
		x, y, z = tonumber(x), tonumber(y), tonumber(z)
		if not x or not y or not z then
			error("TowerVector không hợp lệ: " .. tostring(entry.TowerVector))
		end
		local pos = Vector3.new(x, y, z)
		local args = {
			tonumber(entry.TowerA1),
			entry.TowerPlaced,
			pos,
			tonumber(entry.Rotation or 0),
			entry.TowerPlaceCost
		}
		local towerX = pos.X
		PlaceTowerRepeat(args, towerX, entry.TowerPlaceCost)

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

	elseif entry.ChangeTarget and entry.TargetType then
		local towerX = tonumber(entry.ChangeTarget)
		local hash, tower = FindTowerByX(towerX, false)
		if not hash or not tower then continue end
		local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
		if not hp or hp <= 0 then continue end
		Remotes.ChangeQueryType:FireServer(hash, entry.TargetType)
		task.wait(0.1)

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
