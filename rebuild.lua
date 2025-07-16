-- TDX Macro Runner - Rebuild (Fixed & Loadstring-Compatible)

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function SafeRequire(path)
    local ok, result = pcall(require, path)
    return ok and result or nil
end

local function LoadTowerClass()
    local ps = player:WaitForChild("PlayerScripts")
    local client = ps:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    return SafeRequire(towerModule)
end

local TowerClass = LoadTowerClass()
if not TowerClass then
    error("Không thể tải TowerClass")
end

local function GetTowerByAxis(x)
    print("[DEBUG] GetTowerByAxis tìm kiếm X:", x)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local ok, pos = pcall(function()
            local model = tower.Character:GetCharacterModel()
            return model and model.PrimaryPart.Position.X
        end)

        if ok and pos then
            print("[DEBUG] Tìm thấy tower tại X:", pos, "Hash:", hash)
            if pos == x then
                local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
                print("[DEBUG] Tower X:", x, "HP:", hp)
                if hp and hp > 0 then
                    return hash, tower
                else
                    print("[DEBUG] Tower X:", x, "đã chết hoặc không có HP")
                end
            end
        else
            print("[DEBUG] Không thể lấy position của tower hash:", hash)
        end
    end
    print("[DEBUG] Không tìm thấy tower tại X:", x)
    return nil, nil
end

local function WaitForCash(amount)
    print("[DEBUG] WaitForCash cần:", amount, "hiện tại:", cashStat.Value)
    while cashStat.Value < amount do
        print("[DEBUG] Chờ tiền... Cần:", amount, "Có:", cashStat.Value)
        task.wait()
    end
    print("[DEBUG] Đủ tiền! Cần:", amount, "Có:", cashStat.Value)
end

local function PlaceTowerRetry(args, x, name)
    print("[DEBUG] PlaceTowerRetry bắt đầu:", name, "X:", x)
    print("[DEBUG] Args:", unpack(args))
    
    while true do
        print("[DEBUG] Gọi PlaceTower với args:", unpack(args))
        Remotes.PlaceTower:InvokeServer(unpack(args))
        task.wait(0.1)

        local hash = GetTowerByAxis(x)
        if hash then
            print("[REBUILD] Đặt thành công:", name, "X:", x, "Hash:", hash)
            return
        end

        warn("[RETRY] Đặt thất bại:", name, x, "- thử lại...")
    end
end

local function UpgradeTowerRetry(x, path)
    print("[DEBUG] UpgradeTowerRetry bắt đầu X:", x, "path:", path)
    
    while true do
        local hash, tower = GetTowerByAxis(x)
        if not tower then
            print("[DEBUG] Không tìm thấy tower X:", x, "- chờ...")
            task.wait()
            continue
        end

        print("[DEBUG] Tìm thấy tower X:", x, "Hash:", hash)
        
        local lvlBefore = tower.LevelHandler:GetLevelOnPath(path)
        local max = tower.LevelHandler:GetMaxLevel()
        
        print("[DEBUG] Level hiện tại:", lvlBefore, "Max level:", max, "Path:", path)

        if lvlBefore >= max then
            print("[DEBUG] Đã đạt max level, bỏ qua upgrade")
            return
        end

        local ok, cost = pcall(function()
            return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
        end)

        if not ok or not cost then
            print("[DEBUG] Không thể lấy cost upgrade, ok:", ok, "cost:", cost)
            return
        end

        print("[DEBUG] Cost upgrade:", cost, "Current cash:", cashStat.Value)
        WaitForCash(cost)
        
        print("[DEBUG] Gọi TowerUpgradeRequest hash:", hash, "path:", path)
        Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        task.wait(0.1)

        local lvlAfter = tower.LevelHandler:GetLevelOnPath(path)
        print("[DEBUG] Level sau upgrade:", lvlAfter, "trước:", lvlBefore)
        
        if lvlAfter > lvlBefore then
            print("[REBUILD] Upgrade thành công tại X:", x, "path:", path, "level:", lvlAfter)
            return
        end

        warn("[RETRY] Upgrade thất bại tại X:", x, "path:", path, "- thử lại...")
    end
end

local function SellTowerRetry(x)
    print("[DEBUG] SellTowerRetry X:", x)
    local hash = GetTowerByAxis(x)
    if hash then
        print("[DEBUG] Gọi SellTower hash:", hash)
        Remotes.SellTower:FireServer(hash)
        print("[SUPER] Sell:", x)
    else
        print("[DEBUG] Không tìm thấy tower để sell X:", x)
    end
end

local function ChangeTargetRetry(x, t)
    print("[DEBUG] ChangeTargetRetry X:", x, "type:", t)
    local hash = GetTowerByAxis(x)
    if hash then
        print("[DEBUG] Gọi ChangeQueryType hash:", hash, "type:", t)
        Remotes.ChangeQueryType:FireServer(hash, t)
        print("[REBUILD] Đổi target X:", x, "type:", t)
    else
        print("[DEBUG] Không tìm thấy tower để đổi target X:", x)
    end
end

-- Load macro config
local cfg = _G.TDX_Config or {}
local macroPath = "tdx/macros/" .. (cfg["Macro Name"] or "event") .. ".json"
print("[DEBUG] Loading macro từ:", macroPath)
local macro = HttpService:JSONDecode(readfile(macroPath))
print("[DEBUG] Macro loaded, tổng cộng", #macro, "bước")

-- Main
local rebuildActive = false
local skipSet, rebuildTime = {}, 0
local macroRun = {}
local placedTowers = {}

for i, line in ipairs(macro) do
    print("[DEBUG] Xử lý bước", i, ":", line.SuperFunction or line.TowerPlaced or line.TowerUpgraded or line.SellTower or line.ChangeTarget or "Unknown")
    
    if line.SuperFunction == "SellAll" then
        print("[DEBUG] Thực hiện SellAll")
        local skip = {}
        for _, name in ipairs(line.Skip or {}) do
            skip[name] = true
            print("[DEBUG] Skip sell:", name)
        end

        for hash, tower in pairs(TowerClass.GetTowers()) do
            local model = tower.Character:GetCharacterModel()
            if model and not skip[model.Name] then
                print("[DEBUG] Selling tower:", model.Name, "hash:", hash)
                Remotes.SellTower:FireServer(hash)
                print("[SUPER] Sell:", model.Name)
            end
        end

    elseif line.SuperFunction == "rebuild" then
        print("[DEBUG] Kích hoạt rebuild mode")
        rebuildActive = true
        for _, name in ipairs(line.Skip or {}) do
            skipSet[name] = true
            print("[DEBUG] Skip rebuild:", name)
        end
        rebuildTime = i
        print("[DEBUG] Rebuild time set to:", rebuildTime)

        task.spawn(function()
            print("[DEBUG] Rebuild task bắt đầu")
            while rebuildActive do
                print("[DEBUG] Kiểm tra rebuild, placedTowers count:", #placedTowers)
                for x, _ in pairs(placedTowers) do
                    print("[DEBUG] Kiểm tra tower X:", x)
                    local _, t = GetTowerByAxis(x)
                    if not t then
                        print("[DETECT] Tower mất tại X:", x)
                        placedTowers[x] = nil

                        local actionsToApply = {}
                        print("[DEBUG] Tìm kiếm actions để rebuild từ bước 1 đến", rebuildTime)
                        
                        for j = 1, rebuildTime do
                            local step = macro[j]
                            print("[DEBUG] Bước", j, ":", step.TowerVector and "Place" or step.TowerUpgraded and "Upgrade" or step.ChangeTarget and "Target" or "Other")
                            
                            if step.TowerVector then
                                local v = step.TowerVector:split(", ")
                                local vx = tonumber(v[1])
                                print("[DEBUG] TowerVector X:", vx, "cần rebuild X:", x, "skip:", skipSet[step.TowerPlaced])
                                
                                if vx == x and not skipSet[step.TowerPlaced] then
                                    print("[DEBUG] Thêm place action cho X:", vx, "tower:", step.TowerPlaced)
                                    table.insert(actionsToApply, { type = "place", data = step, x = vx })
                                end
                            elseif step.TowerUpgraded then
                                local upgradeX = tonumber(step.TowerUpgraded)
                                print("[DEBUG] TowerUpgraded X:", upgradeX, "cần rebuild X:", x)
                                
                                if upgradeX == x then
                                    print("[DEBUG] Thêm upgrade action cho X:", x, "path:", step.UpgradePath)
                                    table.insert(actionsToApply, { type = "upgrade", data = step, x = x })
                                end
                            elseif step.ChangeTarget then
                                local targetX = tonumber(step.ChangeTarget)
                                print("[DEBUG] ChangeTarget X:", targetX, "cần rebuild X:", x)
                                
                                if targetX == x then
                                    print("[DEBUG] Thêm target action cho X:", x, "target:", step.TargetType)
                                    table.insert(actionsToApply, { type = "target", data = step, x = x })
                                end
                            end
                        end

                        print("[DEBUG] Tổng cộng", #actionsToApply, "actions cần thực hiện")
                        
                        for _, action in ipairs(actionsToApply) do
                            print("[DEBUG] Thực hiện action:", action.type, "X:", action.x)
                            
                            if action.type == "place" then
                                local step = action.data
                                local v = step.TowerVector:split(", ")
                                local args = {
                                    tonumber(step.TowerA1),
                                    step.TowerPlaced,
                                    Vector3.new(unpack(v)),
                                    tonumber(step.Rotation or 0)
                                }
                                
                                print("[DEBUG] Place cost:", step.TowerPlaceCost or 0)
                                WaitForCash(step.TowerPlaceCost or 0)
                                PlaceTowerRetry(args, action.x, step.TowerPlaced)
                                placedTowers[action.x] = true
                                print("[DEBUG] Đã đặt tower X:", action.x)
                                
                            elseif action.type == "upgrade" then
                                print("[DEBUG] Upgrade X:", action.x, "path:", action.data.UpgradePath)
                                UpgradeTowerRetry(action.x, action.data.UpgradePath)
                                
                            elseif action.type == "target" then
                                print("[DEBUG] Change target X:", action.x, "type:", action.data.TargetType)
                                ChangeTargetRetry(action.x, action.data.TargetType)
                            end
                        end
                        
                        print("[DEBUG] Hoàn thành rebuild tower X:", x)
                    end
                end
                task.wait(1)
            end
            print("[DEBUG] Rebuild task kết thúc")
        end)

    else
        print("[DEBUG] Thêm vào macroRun:", i)
        table.insert(macroRun, line)
        if line.TowerPlaced and line.TowerVector then
            print("[DEBUG] Đặt tower:", line.TowerPlaced, "vector:", line.TowerVector, "cost:", line.TowerPlaceCost)
            local vec = line.TowerVector:split(", ")
            local pos = Vector3.new(unpack(vec))
            local args = {
                tonumber(line.TowerA1),
                line.TowerPlaced,
                pos,
                tonumber(line.Rotation or 0)
            }
            WaitForCash(line.TowerPlaceCost or 0)
            PlaceTowerRetry(args, pos.X, line.TowerPlaced)
            placedTowers[pos.X] = true
            print("[DEBUG] Đã thêm vào placedTowers X:", pos.X)
        elseif line.TowerUpgraded then
            print("[DEBUG] Upgrade tower X:", line.TowerUpgraded, "path:", line.UpgradePath)
            UpgradeTowerRetry(tonumber(line.TowerUpgraded), line.UpgradePath)
        elseif line.SellTower then
            print("[DEBUG] Sell tower:", line.SellTower)
            SellTowerRetry(line.SellTower)
        elseif line.ChangeTarget then
            print("[DEBUG] Change target X:", line.ChangeTarget, "type:", line.TargetType)
            ChangeTargetRetry(tonumber(line.ChangeTarget), line.TargetType)
        end
    end
end

print("✅ Macro hoàn tất")
