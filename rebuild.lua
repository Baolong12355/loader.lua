-- 📦 TDX Runner & Rebuilder (Full Script - Executor Compatible)

warn("📦 TDX Runner khởi động...")

local HttpService = game:GetService("HttpService") local ReplicatedStorage = game:GetService("ReplicatedStorage") local Players = game:GetService("Players") local player = Players.LocalPlayer local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash") local Remotes = ReplicatedStorage:WaitForChild("Remotes")

getgenv().TDX_Config = getgenv().TDX_Config or { ["Macro Name"] = "event", ["PlaceMode"] = "rewrite" }

local function SafeRequire(path, timeout) timeout = timeout or 5 local t0 = os.clock() while os.clock() - t0 < timeout do local success, result = pcall(function() return require(path) end) if success then return result end task.wait() end return nil end

local function LoadTowerClass() local ps = player:WaitForChild("PlayerScripts") local client = ps:WaitForChild("Client") local gameClass = client:WaitForChild("GameClass") local towerModule = gameClass:WaitForChild("TowerClass") return SafeRequire(towerModule) end

TowerClass = TowerClass or LoadTowerClass() if not TowerClass then error("TowerClass load failed") end

local debugLines = {} local function LogDebug(...) local msg = "[" .. os.date("%X") .. "] " .. table.concat({...}, " ") print(msg) table.insert(debugLines, msg) end

local function SaveDebugLog() local content = table.concat(debugLines, "\n") pcall(function() writefile("log_rebuild.txt", content) end) end

local function GetTowerByAxis(axisX) for hash, tower in pairs(TowerClass.GetTowers()) do local success, pos, name = pcall(function() local model = tower.Character:GetCharacterModel() local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) return root and root.Position, model and (root and root.Name or model.Name) end) if success and pos and pos.X == axisX then local hp = tower.HealthHandler and tower.HealthHandler:GetHealth() if hp and hp > 0 then return hash, tower, name or "(NoName)" else LogDebug("HP0", axisX) end end end LogDebug("MISSING", axisX) return nil, nil, nil end

local function GetCurrentUpgradeCost(tower, path) if not tower or not tower.LevelHandler then return nil end local maxLvl = tower.LevelHandler:GetMaxLevel() local curLvl = tower.LevelHandler:GetLevelOnPath(path) if curLvl >= maxLvl then return nil end local ok, baseCost = pcall(function() return tower.LevelHandler:GetLevelUpgradeCost(path, 1) end) if not ok then return nil end local disc = 0 local ok2, d = pcall(function() return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end) if ok2 and typeof(d) == "number" then disc = d end return math.floor(baseCost * (1 - disc)) end

local function WaitForCash(amount) while cashStat.Value < amount do task.wait() end end

local function PlaceTowerRetry(args, axisValue, towerName) while true do Remotes.PlaceTower:InvokeServer(unpack(args)) local t0 = tick() repeat task.wait(0.1) until tick() - t0 > 2 or GetTowerByAxis(axisValue) if GetTowerByAxis(axisValue) then LogDebug("PLACED", towerName, axisValue) SaveDebugLog() return end LogDebug("RETRY PLACE", towerName, axisValue) SaveDebugLog() end end

local function UpgradeTowerRetry(axisValue, path) local tries = 0 while true do local hash, tower = GetTowerByAxis(axisValue) if not hash then tries += 1 task.wait() continue end local before = tower.LevelHandler:GetLevelOnPath(path) local cost = GetCurrentUpgradeCost(tower, path) if not cost then return end WaitForCash(cost) Remotes.TowerUpgradeRequest:FireServer(hash, path, 1) local t0 = tick() repeat task.wait(0.1) local _, t = GetTowerByAxis(axisValue) if t and t.LevelHandler:GetLevelOnPath(path) > before then LogDebug("UPGRADED", axisValue, path) SaveDebugLog() return end until tick() - t0 > 2 tries += 1 task.wait() end end

local function ChangeTargetRetry(axisValue, targetType) while true do local hash = GetTowerByAxis(axisValue) if hash then Remotes.ChangeQueryType:FireServer(hash, targetType) LogDebug("TARGET", axisValue, targetType) SaveDebugLog() return end task.wait() end end

local function SellTowerRetry(axisValue) while true do local hash = GetTowerByAxis(axisValue) if hash then Remotes.SellTower:FireServer(hash) task.wait(0.1) if not GetTowerByAxis(axisValue) then LogDebug("SOLD", axisValue) SaveDebugLog() return end end task.wait() end end

local config = getgenv().TDX_Config or {} local macroName = config["Macro Name"] or "event" local macroPath = "tdx/macros/" .. macroName .. ".json" globalPlaceMode = config["PlaceMode"] or "normal" if globalPlaceMode == "unsure" then globalPlaceMode = "rewrite" end if globalPlaceMode == "normal" then globalPlaceMode = "ashed" end

if not isfile(macroPath) then error("❌ Không tìm thấy macro: " .. macroPath) end

local success, macro = pcall(function() return HttpService:JSONDecode(readfile(macroPath)) end) if not success or type(macro) ~= "table" then error("❌ Lỗi khi đọc macro hoặc macro rỗng") end

warn("📄 Macro tải thành công. Tổng dòng:", #macro)

local towerRecords = {} local skipTypes = {} local skipBeOnly = false local watcherStarted = false

for i, entry in ipairs(macro) do if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then local vecTab = entry.TowerVector:split(", ") local pos = Vector3.new(unpack(vecTab)) local args = { tonumber(entry.TowerA1), entry.TowerPlaced, pos, tonumber(entry.Rotation or 0) } WaitForCash(entry.TowerPlaceCost) PlaceTowerRetry(args, pos.X, entry.TowerPlaced) towerRecords[pos.X] = towerRecords[pos.X] or {} table.insert(towerRecords[pos.X], entry)

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

elseif entry.SellTower then
    local axis = tonumber(entry.SellTower)
    SellTowerRetry(axis)
    towerRecords[axis] = towerRecords[axis] or {}
    table.insert(towerRecords[axis], entry)

elseif entry.SuperFunction == "rebuild" then
    warn("🛠️ Phát hiện dòng rebuild tại dòng:", i)
    skipBeOnly = entry.Be == true
    skipTypes = entry.Skip or {}

    if not watcherStarted then
        watcherStarted = true
        task.spawn(function()
            while true do
                for x, records in pairs(towerRecords) do
                    local _, t = GetTowerByAxis(x)
                    if not t then
                        local type = nil
                        for _, e in ipairs(records) do
                            type = e.TowerPlaced or type
                        end
                        local shouldSkip = false
                        for _, skip in ipairs(skipTypes) do
                            if skip == type then
                                shouldSkip = true
                                break
                            end
                        end
                        if shouldSkip then continue end
                        LogDebug("REBUILDING", type or "Unknown", x)
                        for _, e in ipairs(records) do
                            if e.TowerPlaced then
                                local vecTab = e.TowerVector:split(", ")
                                local pos = Vector3.new(unpack(vecTab))
                                local args = {
                                    tonumber(e.TowerA1), e.TowerPlaced, pos, tonumber(e.Rotation or 0)
                                }
                                WaitForCash(e.TowerPlaceCost)
                                PlaceTowerRetry(args, pos.X, e.TowerPlaced)
                            elseif e.TowerUpgraded then
                                UpgradeTowerRetry(tonumber(e.TowerUpgraded), e.UpgradePath)
                            elseif e.ChangeTarget then
                                ChangeTargetRetry(tonumber(e.ChangeTarget), e.TargetType)
                            elseif e.SellTower then
                                SellTowerRetry(tonumber(e.SellTower))
                            end
                        end
                        SaveDebugLog()
                    end
                end
                task.wait(2)
            end
        end)
    end
end

end

