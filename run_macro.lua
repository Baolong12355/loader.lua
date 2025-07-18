-- 📦 TDX Runner & Rebuilder (Full Script - Executor Compatible + Full Skip/Be Logic + SellAll + Priority Rebuild)

local HttpService = game:GetService("HttpService") local ReplicatedStorage = game:GetService("ReplicatedStorage") local Players = game:GetService("Players") local player = Players.LocalPlayer local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash") local Remotes = ReplicatedStorage:WaitForChild("Remotes")

getgenv().TDX_Config = getgenv().TDX_Config or { ["Macro Name"] = "event", ["PlaceMode"] = "rewrite", ["ForceRebuildEvenIfSold"] = false, ["MaxRebuildRetry"] = nil }

local function SafeRequire(path, timeout) timeout = timeout or 5 local t0 = os.clock() while os.clock() - t0 < timeout do local success, result = pcall(function() return require(path) end) if success then return result end task.wait() end return nil end

local function LoadTowerClass() local ps = player:WaitForChild("PlayerScripts") local client = ps:WaitForChild("Client") local gameClass = client:WaitForChild("GameClass") local towerModule = gameClass:WaitForChild("TowerClass") return SafeRequire(towerModule) end

TowerClass = TowerClass or LoadTowerClass() if not TowerClass then return end

local function GetTowerByAxis(axisX) for _, tower in pairs(TowerClass.GetTowers()) do local success, pos = pcall(function() local model = tower.Character:GetCharacterModel() local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) return root and root.Position end) if success and pos and pos.X == axisX then local hp = tower.HealthHandler and tower.HealthHandler:GetHealth() if hp and hp > 0 then return tower end end end return nil end

local function GetCurrentUpgradeCost(tower, path) if not tower or not tower.LevelHandler then return nil end local maxLvl = tower.LevelHandler:GetMaxLevel() local curLvl = tower.LevelHandler:GetLevelOnPath(path) if curLvl >= maxLvl then return nil end local ok, baseCost = pcall(function() return tower.LevelHandler:GetLevelUpgradeCost(path, 1) end) if not ok then return nil end local disc = 0 local ok2, d = pcall(function() return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end) if ok2 and typeof(d) == "number" then disc = d end return math.floor(baseCost * (1 - disc)) end

local function WaitForCash(amount) while cashStat.Value < amount do task.wait() end end

local function PlaceTowerRetry(args, axisValue) while true do Remotes.PlaceTower:InvokeServer(unpack(args)) local t0 = tick() repeat task.wait(0.1) until tick() - t0 > 2 or GetTowerByAxis(axisValue) if GetTowerByAxis(axisValue) then return end end end

local function UpgradeTowerRetry(axisValue, path) while true do local tower = GetTowerByAxis(axisValue) if not tower then task.wait() continue end local before = tower.LevelHandler:GetLevelOnPath(path) local cost = GetCurrentUpgradeCost(tower, path) if not cost then return end WaitForCash(cost) Remotes.TowerUpgradeRequest:FireServer(tower.Hash, path, 1) local t0 = tick() repeat task.wait(0.1) local t = GetTowerByAxis(axisValue) if t and t.LevelHandler:GetLevelOnPath(path) > before then return end until tick() - t0 > 2 end end

local function ChangeTargetRetry(axisValue, targetType) while true do local tower = GetTowerByAxis(axisValue) if tower then Remotes.ChangeQueryType:FireServer(tower.Hash, targetType) return end task.wait() end end

local function SellTowerRetry(axisValue) while true do local tower = GetTowerByAxis(axisValue) if tower then Remotes.SellTower:FireServer(tower.Hash) task.wait(0.1) if not GetTowerByAxis(axisValue) then return true end end task.wait() end end

local function SellAllTowers(skipList) local skipMap = {} for _, name in ipairs(skipList or {}) do skipMap[name] = true end for hash, tower in pairs(TowerClass.GetTowers()) do local model = tower.Character and tower.Character:GetCharacterModel() local root = model and model.PrimaryPart if root and not skipMap[root.Name] then Remotes.SellTower:FireServer(hash) task.wait(0.1) end end end

local config = getgenv().TDX_Config local macroName = config["Macro Name"] or "event" local macroPath = "tdx/macros/" .. macroName .. ".json" local globalPlaceMode = config["PlaceMode"] or "ashed"

if not isfile(macroPath) then return end local ok, macro = pcall(function() return HttpService:JSONDecode(readfile(macroPath)) end) if not ok or type(macro) ~= "table" then return end

local towerRecords = {} local priorityOrder = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"} local function getPriority(name) for i, n in ipairs(priorityOrder) do if name == n then return i end end return #priorityOrder + 1 end

for _, entry in ipairs(macro) do if entry.SuperFunction == "sell_all" then SellAllTowers(entry.Skip) continue end

if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
    local vecTab = entry.TowerVector:split(", ")
    local pos = Vector3.new(unpack(vecTab))
    local args = {
        tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0)
    }
    WaitForCash(entry.TowerPlaceCost)
    PlaceTowerRetry(args, pos.X)
    towerRecords[pos.X] = towerRecords[pos.X] or {}
    table.insert(towerRecords[pos.X], entry)

elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
    local axis = tonumber(entry.TowerUpgraded)
    UpgradeTowerRetry(axis, entry.UpgradePath)
    towerRecords[axis] = towerRecords[axis] or {}
    table.insert(towerRecords[axis], entry)

elseif entry.ChangeTarget and entry.TargetType then
    local axis = tonumber(entry.ChangeTarget)
    ChangeTargetRetry(axis, entry.TargetType)
    towerRecords[axis] = towerRecords[axis] or {}
    table.insert(towerRecords[axis], entry)
end

end

task.spawn(function() while true do for x, records in pairs(towerRecords) do local t = GetTowerByAxis(x) if not t then table.sort(records, function(a, b) local na = a.TowerPlaced or "" local nb = b.TowerPlaced or "" return getPriority(na) < getPriority(nb) end) for _, entry in ipairs(records) do if entry.TowerPlaced then local vecTab = entry.TowerVector:split(", ") local pos = Vector3.new(unpack(vecTab)) local args = { tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0) } WaitForCash(entry.TowerPlaceCost) PlaceTowerRetry(args, pos.X) elseif entry.TowerUpgraded then UpgradeTowerRetry(tonumber(entry.TowerUpgraded), entry.UpgradePath) elseif entry.ChangeTarget then ChangeTargetRetry(tonumber(entry.ChangeTarget), entry.TargetType) end task.wait(0.1) end end end task.wait(0.24) end end)
