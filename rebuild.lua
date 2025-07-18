local HttpService = game:GetService("HttpService") local ReplicatedStorage = game:GetService("ReplicatedStorage") local Players = game:GetService("Players") local player = Players.LocalPlayer local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash") local Remotes = ReplicatedStorage:WaitForChild("Remotes")

 getgenv().TDX_Config = getgenv().TDX_Config or { ["Macro Name"] = "event", ["PlaceMode"] = "rewrite" }

local function SafeRequire(path, timeout) timeout = timeout or 5 local t0 = os.clock() while os.clock() - t0 < timeout do local success, result = pcall(function() return require(path) end) if success then return result end task.wait() end return nil end

local function LoadTowerClass() local ps = player:WaitForChild("PlayerScripts") local client = ps:WaitForChild("Client") local gameClass = client:WaitForChild("GameClass") local towerModule = gameClass:WaitForChild("TowerClass") return SafeRequire(towerModule) end

TowerClass = TowerClass or LoadTowerClass() if not TowerClass then error("TowerClass load failed") end

local debugLines = {} local function LogDebug(...) local msg = "[" .. os.date("%X") .. "] " .. table.concat({...}, " ") print(msg) table.insert(debugLines, msg) end

local function SaveDebugLog() local content = table.concat(debugLines, "\n") writefile("log_rebuild.txt", content) end

function GetTowerByAxis(axisX) for hash, tower in pairs(TowerClass.GetTowers()) do local success, pos, name = pcall(function() local model = tower.Character:GetCharacterModel() local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) return root and root.Position, model and (root and root.Name or model.Name) end) if success and pos and pos.X == axisX then local hp = tower.HealthHandler and tower.HealthHandler:GetHealth() if hp and hp > 0 then return hash, tower, name or "(NoName)" else LogDebug("HP0", axisX) end end end LogDebug("MISSING", axisX) return nil, nil, nil end

function GetCurrentUpgradeCost(tower, path) if not tower or not tower.LevelHandler then return nil end local maxLvl = tower.LevelHandler:GetMaxLevel() local curLvl = tower.LevelHandler:GetLevelOnPath(path) if curLvl >= maxLvl then return nil end local ok, baseCost = pcall(function() return tower.LevelHandler:GetLevelUpgradeCost(path, 1) end) if not ok then return nil end local disc = 0 local ok2, d = pcall(function() return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end) if ok2 and typeof(d) == "number" then disc = d end return math.floor(baseCost * (1 - disc)) end

function WaitForCash(amount) while cashStat.Value < amount do task.wait() end end

function PlaceTowerRetry(args, axisValue, towerName) while true do Remotes.PlaceTower:InvokeServer(unpack(args)) local t0 = tick() repeat task.wait(0.1) local hash = GetTowerByAxis(axisValue) if hash then LogDebug("PLACED", towerName, axisValue) return end until tick() - t0 > 2 LogDebug("RETRY PLACE", towerName, axisValue) end end

function UpgradeTowerRetry(axisValue, path) local tries = 0 while true do local hash, tower = GetTowerByAxis(axisValue) if not hash then tries += 1 task.wait() continue end local before = tower.LevelHandler:GetLevelOnPath(path) local cost = GetCurrentUpgradeCost(tower, path) if not cost then return end WaitForCash(cost) Remotes.TowerUpgradeRequest:FireServer(hash, path, 1) local t0 = tick() repeat task.wait(0.1) local _, t = GetTowerByAxis(axisValue) if t and t.LevelHandler:GetLevelOnPath(path) > before then LogDebug("UPGRADED", axisValue, path) return end until tick() - t0 > 2 tries += 1 task.wait() end end

function ChangeTargetRetry(axisValue, targetType) while true do local hash = GetTowerByAxis(axisValue) if hash then Remotes.ChangeQueryType:FireServer(hash, targetType) LogDebug("TARGET", axisValue, targetType) return end task.wait() end end

function SellTowerRetry(axisValue) while true do local hash = GetTowerByAxis(axisValue) if hash then Remotes.SellTower:FireServer(hash) task.wait(0.1) if not GetTowerByAxis(axisValue) then LogDebug("SOLD", axisValue) return end end task.wait() end end

