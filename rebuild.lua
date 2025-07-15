local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local cash = player:WaitForChild("leaderstats"):WaitForChild("Cash")

local function SafeRequire(path)
	local ok, result = pcall(function() return require(path) end)
	return ok and result or nil
end

local TowerClass
do
	local client = player:WaitForChild("PlayerScripts"):WaitForChild("Client")
	local towerModule = client:WaitForChild("GameClass"):WaitForChild("TowerClass")
	TowerClass = SafeRequire(towerModule)
	if not TowerClass then return end
end

local function GetTowerByAxis(axisX)
	for hash, tower in pairs(TowerClass.GetTowers()) do
		local ok, pos = pcall(function()
			local model = tower.Character:GetCharacterModel()
			local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
			return root and root.Position
		end)
		if ok and pos and math.abs(pos.X - axisX) <= 1 then
			local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
			if hp and hp > 0 then return hash, tower end
		end
	end
	return nil, nil
end

local function WaitCash(amount)
	while cash.Value < amount do task.wait() end
end

local function GetCurrentUpgradeCost(tower, path)
	local ok, cost = pcall(function()
		return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
	end)
	return ok and cost or 0
end

local function PlaceTower(args, x, name)
	while true do
		Remotes.PlaceTower:InvokeServer(unpack(args))
		for _ = 1, 20 do
			task.wait(0.1)
			local h = GetTowerByAxis(x)
			if h then return end
		end
		warn("Retry place:", name)
	end
end

local function UpgradeTower(x, path)
	for _ = 1, 3 do
		local hash, tower = GetTowerByAxis(x)
		if not tower then task.wait(0.1) continue end
		local before = tower.LevelHandler:GetLevelOnPath(path)
		local cost = GetCurrentUpgradeCost(tower, path)
		if cost <= 0 then return end
		WaitCash(cost)
		Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
		for _ = 1, 10 do
			task.wait(0.1)
			local _, t = GetTowerByAxis(x)
			if t and t.LevelHandler:GetLevelOnPath(path) > before then return end
		end
	end
end

local function SellTower(x)
	while true do
		local hash = GetTowerByAxis(x)
		if hash then
			Remotes.SellTower:FireServer(hash)
			task.wait(0.1)
			if not GetTowerByAxis(x) then return end
		end
		task.wait()
	end
end

local function ChangeTarget(x, type)
	while true do
		local hash = GetTowerByAxis(x)
		if hash then
			Remotes.ChangeQueryType:FireServer(hash, type)
			return
		end
		task.wait()
	end
end

-- ✳ rebuild logic
local team = {} -- vị trí x -> {placed, rotation, a1, cost, upgrades={...}}
local skipNames = {}
local skipOnlyBefore = false
local trackedX = {}
local macroPath = "tdx/macros/x.json"

if not isfile(macroPath) then error("Không có macro file.") end
local macro = HttpService:JSONDecode(readfile(macroPath))

-- lưu team hiện tại vào biến team
local function SaveTeam()
	for _, t in pairs(team) do trackedX[t.x] = true end
end

-- rebuild theo ưu tiên
local function RebuildTeam()
	local priority = {"Medic", "Golden Mobster", "Mobster", "DJ", "Commander"}
	local function prio(t)
		for i, v in ipairs(priority) do if v == t.name then return i end end
		return #priority + 1
	end
	local sorted = {}
	for _, t in pairs(team) do table.insert(sorted, t) end
	table.sort(sorted, function(a, b) return prio(a) < prio(b) end)
	for _, t in ipairs(sorted) do
		if not trackedX[t.x] then
			if not skipNames[t.name] then
				WaitCash(t.cost)
				PlaceTower({tonumber(t.a1), t.name, Vector3.new(t.vec[1], t.vec[2], t.vec[3]), tonumber(t.rot)}, t.x, t.name)
				task.wait(0.1)
				for _, u in ipairs(t.upgrades) do
					UpgradeTower(t.x, u)
					task.wait(0.1)
				end
				trackedX[t.x] = true
				task.wait(2)
			end
		end
	end
end

-- phát hiện tower chết
task.spawn(function()
	while true do
		for _, t in pairs(team) do
			if not skipNames[t.name] and not trackedX[t.x] then
				local _, tower = GetTowerByAxis(t.x)
				if not tower then
					task.wait(0.1)
					local _, tower2 = GetTowerByAxis(t.x)
					if not tower2 then
						warn("[REBUILD]", t.name)
						RebuildTeam()
					end
				end
			end
		end
		task.wait(1)
	end
end)

-- chạy macro
for _, e in ipairs(macro) do
	if e.SuperFunction == "rebuild" then
		skipOnlyBefore = e.Be or false
		for _, name in ipairs(e.Skip or {}) do skipNames[name] = true end
		SaveTeam()
	elseif e.TowerPlaced then
		local vecTab = e.TowerVector:split(", ")
		local pos = Vector3.new(unpack(vecTab))
		WaitCash(e.TowerPlaceCost)
		PlaceTower({tonumber(e.TowerA1), e.TowerPlaced, pos, tonumber(e.Rotation)}, pos.X, e.TowerPlaced)
		table.insert(team, {
			name = e.TowerPlaced,
			x = pos.X,
			vec = {pos.X, pos.Y, pos.Z},
			a1 = e.TowerA1,
			rot = e.Rotation,
			cost = e.TowerPlaceCost,
			upgrades = {}
		})
	elseif e.UpgradePath then
		UpgradeTower(e.TowerUpgraded, e.UpgradePath)
		for _, t in pairs(team) do
			if math.abs(t.x - e.TowerUpgraded) <= 1 then
				table.insert(t.upgrades, e.UpgradePath)
			end
		end
	elseif e.ChangeTarget then
		ChangeTarget(e.ChangeTarget, e.TargetType)
	elseif e.SellTower then
		SellTower(e.SellTower)
		trackedX[e.SellTower] = true
	end
end

print("✅ Đã chạy toàn bộ macro")
