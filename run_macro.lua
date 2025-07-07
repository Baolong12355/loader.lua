-- Tự động chạy khi vào game
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Safe Require
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

-- Tìm tower theo X
local function GetTowerByAxis(axisX)
	for hash, tower in pairs(TowerClass.GetTowers()) do
		local success, pos = pcall(function()
			local model = tower.Character:GetCharacterModel()
			local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
			return root and root.Position
		end)
		if success and pos and math.abs(pos.X - axisX) <= 1 then
			local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
			if hp and hp > 0 then
				return hash, tower
			end
		end
	end
	return nil, nil
end

-- Lấy giá nâng cấp
local function GetCurrentUpgradeCost(tower, path)
	if not tower or not tower.LevelHandler then return nil end
	local maxLvl = tower.LevelHandler:GetMaxLevel()
	local curLvl = tower.LevelHandler:GetLevelOnPath(path)
	if curLvl >= maxLvl then return nil end
	local ok, cost = pcall(function()
		return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
	end)
	return ok and cost or nil
end

-- Chờ đủ tiền
local function WaitForCash(amount)
	while cashStat.Value < amount do task.wait() end
end

-- Đặt tower
local function PlaceTowerRetry(args, axisValue, towerName)
	while true do
		Remotes.PlaceTower:InvokeServer(unpack(args))
		local t0 = tick()
		repeat
			task.wait(0.1)
			local hash = GetTowerByAxis(axisValue)
			if hash then return end
		until tick() - t0 > 2
		warn("[RETRY] Đặt tower thất bại, thử lại:", towerName, "X =", axisValue)
	end
end

-- Nâng cấp tower (phân biệt theo mode)
local function UpgradeTowerRetry(axisValue, upgradePath)
	local mode = globalPlaceMode
	local maxTries = mode == "rewrite" and math.huge or 3
	local tries = 0

	while tries < maxTries do
		local hash, tower = GetTowerByAxis(axisValue)
		if not hash or not tower then
			if mode == "rewrite" then tries += 1; task.wait(); continue end
			warn("[SKIP] Không thấy tower tại X =", axisValue)
			return
		end

		local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
		if not hp or hp <= 0 then
			if mode == "rewrite" then tries += 1; task.wait(); continue end
			warn("[SKIP] Tower đã chết tại X =", axisValue)
			return
		end

		local before = tower.LevelHandler:GetLevelOnPath(upgradePath)
		local cost = GetCurrentUpgradeCost(tower, upgradePath)
		if not cost then return end

		WaitForCash(cost)
		Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)

		local upgraded = false
		local t0 = tick()
		repeat
			task.wait(0.1)
			local _, t = GetTowerByAxis(axisValue)
			if t and t.LevelHandler then
				local after = t.LevelHandler:GetLevelOnPath(upgradePath)
				if after > before then upgraded = true break end
			end
		until tick() - t0 > 2

		if upgraded then return end

		tries += 1
		task.wait()
	end
end

-- Đổi target
local function ChangeTargetRetry(axisValue, targetType)
	while true do
		local hash = GetTowerByAxis(axisValue)
		if hash then
			Remotes.ChangeQueryType:FireServer(hash, targetType)
			return
		end
		task.wait(0.1)
	end
end

-- Bán tower
local function SellTowerRetry(axisValue)
	while true do
		local hash = GetTowerByAxis(axisValue)
		if hash then
			Remotes.SellTower:FireServer(hash)
			task.wait(0.1)
			if not GetTowerByAxis(axisValue) then return end
		end
		task.wait()
	end
end

-- Load macro
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "x"
local macroPath = "tdx/macros/" .. macroName .. ".json"
globalPlaceMode = config["PlaceMode"] or "normal"

-- Ánh xạ lại tên mode
if globalPlaceMode == "unsure" then
	globalPlaceMode = "rewrite"
elseif globalPlaceMode == "normal" then
	globalPlaceMode = "ashed"
end

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
for _, entry in ipairs(macro) do
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
		PlaceTowerRetry(args, pos.X, entry.TowerPlaced)

	elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
		local axisValue = tonumber(entry.TowerUpgraded)
		UpgradeTowerRetry(axisValue, entry.UpgradePath)

	elseif entry.ChangeTarget and entry.TargetType then
		local axisValue = tonumber(entry.ChangeTarget)
		ChangeTargetRetry(axisValue, entry.TargetType)

	elseif entry.SellTower then
		local axisValue = tonumber(entry.SellTower)
		SellTowerRetry(axisValue)
	end
end

print("✅ Macro chạy hoàn tất.")			return enemy.Position
		end
	end
	return nil
end

local function getTowerPos(tower)
	if tower.GetPosition then
		local ok, result = pcall(function() return tower:GetPosition() end)
		if ok then return result end
	end
	if tower.Model and tower.Model:FindFirstChild("Root") then
		return tower.Model.Root.Position
	end
	return nil
end

local function getRange(tower)
	local ok, result = pcall(function() return TowerClass.GetCurrentRange(tower) end)
	if ok and typeof(result) == "number" then
		return result
	elseif tower.Stats and tower.Stats.Radius then
		return tower.Stats.Radius * 4
	end
	return 0
end

local function hasEnemyInRange(tower)
	local towerPos = getTowerPos(tower)
	local range = getRange(tower)
	if not towerPos or range <= 0 then return false end
	for _, enemy in ipairs(EnemiesFolder:GetChildren()) do
		if enemy:IsA("BasePart") and (enemy.Position - towerPos).Magnitude <= range then
			return true
		end
	end
	return false
end

local function GetCurrentUpgradeLevels(tower)
	if not tower or not tower.LevelHandler then return 0, 0 end
	local p1, p2 = 0, 0
	pcall(function() p1 = tower.LevelHandler:GetLevelOnPath(1) or 0 end)
	pcall(function() p2 = tower.LevelHandler:GetLevelOnPath(2) or 0 end)
	return p1, p2
end

local function CanUseAbility(ability)
	if not ability then return false end
	if ability.Passive then return false end
	if ability.CustomTriggered then return false end
	if ability.CooldownRemaining > 0 then return false end
	if ability.Stunned then return false end
	if ability.Disabled then return false end
	if ability.Converted then return false end
	local ok, can = pcall(function() return ability:CanUse(true) end)
	return ok and can
end

local function ShouldProcessNonDirectionalSkill(tower, index)
	return tower.Type == "Commander" and index ~= 3
end

-- 🔁 Main
RunService.Heartbeat:Connect(function()
	for hash, tower in pairs(TowerClass.GetTowers() or {}) do
		if not tower or not tower.AbilityHandler then continue end

		local towerType = tower.Type
		local directionalInfo = directionalTowerTypes[towerType]
		local p1, p2 = GetCurrentUpgradeLevels(tower)

		for index = 1, 3 do
			pcall(function()
				local ability = tower.AbilityHandler:GetAbilityFromIndex(index)
				if not CanUseAbility(ability) then return end

				local allowUse = true

				-- Special logic
				if towerType == "Ice Breaker" and index == 1 then
					-- Free use
				elseif towerType == "Slammer" then
					if not hasEnemyInRange(tower) then
						allowUse = false
						warn("[Slammer] Không có enemy trong range")
					end
				elseif towerType == "John" then
					local range = getRange(tower)
					if p1 >= 5 then
						allowUse = hasEnemyInRange(tower)
					elseif p2 >= 5 then
						allowUse = range >= 4.5 and hasEnemyInRange(tower)
					else
						allowUse = range >= 4.5 and hasEnemyInRange(tower)
					end
				elseif towerType == "Mobster" or towerType == "Golden Mobster" then
					if p1 >= 4 and p1 <= 5 then
						allowUse = hasEnemyInRange(tower)
					elseif p2 >= 3 and p2 <= 5 then
						allowUse = true
					else
						allowUse = false
					end
				end

				if allowUse then
					local pos = GetFirstEnemyPosition()
					local sendWithPos = false

					if typeof(directionalInfo) == "table" and directionalInfo.onlyAbilityIndex then
						if index == directionalInfo.onlyAbilityIndex then
							sendWithPos = true
						elseif ShouldProcessNonDirectionalSkill(tower, index) then
							sendWithPos = false
						else
							return
						end
					elseif directionalInfo then
						sendWithPos = true
					end

					if sendWithPos then
						if pos then
							print("[🎯 Dùng skill định hướng]", towerType, "→", index)
							SendSkill(hash, index, pos)
						end
					else
						print("[⚡ Dùng skill thường]", towerType, "→", index)
						SendSkill(hash, index)
					end
					task.wait(0.25)
				end
			end)
		end
	end
end)
