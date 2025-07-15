-- final ready-to-flow (đã xuống hàng đầy đủ)
local HttpService   = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players        = game:GetService("Players")
local player         = Players.LocalPlayer
local cashStat       = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes        = ReplicatedStorage:WaitForChild("Remotes")

------------------------------------------------------------------------
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

local function LoadTowerModule()
	local ps   = player:WaitForChild("PlayerScripts")
	local cli  = ps:WaitForChild("Client")
	local gc   = cli:WaitForChild("GameClass")
	local tm   = gc:WaitForChild("TowerClass")
	return SafeRequire(tm)
end
local TowerClass = LoadTowerModule()
if not TowerClass then error("Không thể tải TowerClass") end

---------------------------------------------------------------------- UTILS
local function GetTowerByAxis(axisX)
	for hash, tower in pairs(TowerClass.GetTowers()) do
		local success, pos = pcall(function()
			local model = tower.Character:GetCharacterModel()
			local root  = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
			return root and root.Position
		end)
		if success and pos and math.abs(pos.X - axisX) <= 1 then
			local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
			if hp and hp > 0 then return hash, tower end
		end
	end
	return nil, nil
end

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

local function WaitForCash(amount)
	while cashStat.Value < amount do task.wait() end
end

---------------------------------------------------------------------- ROBUST PLACE / UP / TARGET / SELL
local function PlaceTowerRetry(args, axisValue, towerName)
	while true do
		Remotes.PlaceTower:InvokeServer(unpack(args))
		local t0 = tick()
		repeat
			task.wait(0.1)
			if GetTowerByAxis(axisValue) then return end
		until tick() - t0 > 2
		warn("[RETRY] Đặt tower thất bại:", towerName, "X =", axisValue)
	end
end

local function UpgradeTowerRetry(axisValue, upgradePath)
	local tries = 0
	while true do
		local hash, tower = GetTowerByAxis(axisValue)
		if not hash or not tower then warn("[SKIP] Không thấy tower X =", axisValue) return end
		local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
		if not hp or hp <= 0 then warn("[SKIP] Tower chết X =", axisValue) return end

		local cost = GetCurrentUpgradeCost(tower, upgradePath)
		if not cost then return end
		WaitForCash(cost)
		Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)
		local big = tick()
		repeat
			task.wait(0.1)
			if tick()-big > 2 then break end
		until false
		return
	end
end

local function ChangeTargetRetry(axisValue, targetType)
	Remotes.ChangeQueryType:FireServer(GetTowerByAxis(axisValue), targetType)
end

local function SellTowerRetry(axisValue)
	Remotes.SellTower:FireServer(GetTowerByAxis(axisValue))
end

---------------------------------------------------------------------- SUPERFUNCTION REBUILD
local function doRebuild(jsonLine)
	local js
	local ok, err = pcall(function()
		js = HttpService:JSONDecode(jsonLine)
	end)
	if not ok or not js or js.SuperFunction~="rebuild" then return end

	local skipList   = js.Skip or {}
	local exactOnly  = js.Be or false

	local cls = LoadTowerModule()
	if not cls then return end

	local build = {}
	-- đóng nóng đội hình hiện tại
	for hash,tower in pairs(cls.GetTowers()) do
		local pos
		pcall(function()
			pos = (tower.Character:GetCharacterModel().PrimaryPart or
			       tower.Character:GetCharacterModel():FindFirstChild("HumanoidRootPart")).Position
		end)
		if not exactOnly or (exactOnly and not table.find(skipList, tower.Type)) then
			if not table.find(skipList, tower.Type) then
				local rec = {
					[1] = hash,
					[2] = tower.Type,
					[3] = pos,
					[4] = 0,
					[5] = 0,
					[6] = tower.QueryTypeIndex,
					[7] = 1,          -- fake
					[8] = {},
					[9] = 0,
					[10]= 0,
					[11]= {},
					[12]= {},
					[13]= 0
				}
				build[#build+1] = rec
			end
		end
	end

	-- flush thành macro mới
	local function vec(v)
		return string.format("Vector3.new(%.2f,%.2f,%.2f)", v.X, v.Y, v.Z)
	end
	local macro = {
		{ SuperFunction  = "rebuild", Skip = skipList },
		ite = function() end   -- dummy
	}
	for _, info in ipairs(build) do
		macro[#macro+1] = {
			TowerPlaced = info[2],
			TowerVector  = vec(info[3]),
			TowerPlaceCost = 0,          -- rebuild chỉ ràng buộc
			Rotation     = 0,
			TowerA1      = 0
		}
	end

	-- overwrite macro hiện tại
	local json = HttpService:JSONEncode(macro)
	writefile("tdx/macros/rebuild.json", json)
	warn("🔁 rebuild() store:"..json)
end

---------------------------------------------------------------------- MAIN MACRO DRIVER
local function runSanMacro()
	local cfg  = getgenv().TDX_Config or {}
	local name = cfg["Macro Name"] or "event"
	local path = "tdx/macros/"..name..".json"

	if not isfile(path) then error("Không có "..path) end
	local macroTbl = HttpService:JSONDecode(readfile(path))

	for _,entry in ipairs(macroTbl) do
		-------------------------------------------------- case super
		if entry.SuperFunction then    -- ["rebuild"]
			doRebuild(HttpService:JSONEncode(entry))
			continue
		end

		-------------------------------------------------- case normal
		if entry.TowerPlaced and entry.TowerVector then
			local vecTab = entry.TowerVector:split(", ")
			local pos    = Vector3.new(tonumber(vecTab[1]), tonumber(vecTab[2]), tonumber(vecTab[3]))
			local args   = {
				tonumber(entry.TowerA1) or 0,
				entry.TowerPlaced,
				pos,
				tonumber(entry.Rotation or 0)
			}
			WaitForCash(entry.TowerPlaceCost)
			PlaceTowerRetry(args, pos.X, entry.TowerPlaced)

		elseif entry.TowerUpgraded then
			UpgradeTowerRetry(entry.TowerUpgraded, entry.UpgradePath)

		elseif entry.ChangeTarget then
			ChangeTargetRetry(entry.ChangeTarget, entry.TargetType)

		elseif entry.SellTower then
			SellTowerRetry(entry.SellTower)
		end
	end
end

--------------------------------------------------------------------------------
local initDelay = 2
task.wait(initDelay)
runSanMacro()
