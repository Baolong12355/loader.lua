-- TDX Macro Runner - Rebuild (Fixed & Discount Integrated, Debug Only on Rebuild, Full Logic)

local HttpService = game:GetService("HttpService") 
local ReplicatedStorage = game:GetService("ReplicatedStorage") 
local Players = game:GetService("Players") 
local player = Players.LocalPlayer 
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash") 
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function SafeRequire(path, timeout) 
    timeout = timeout or 5 
    local t0 = os.clock() 
    while os.clock() - t0 < timeout do 
        local success, result = pcall(function() 
            return require(path) 
        end) 
        if success then 
            return result 
        end 
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
if not TowerClass then 
    error("Không thể tải TowerClass") 
end

local function GetTowerByAxis(axisX) 
    for hash, tower in pairs(TowerClass.GetTowers()) do 
        local success, pos = pcall(function() 
            local model = tower.Character:GetCharacterModel() 
            local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) 
            return root and root.Position 
        end) 
        if success and pos and pos.X == axisX then 
            local hp = tower.HealthHandler and tower.HealthHandler:GetHealth() 
            if hp and hp > 0 then 
                return hash, tower 
            end 
        end 
    end 
    return nil, nil 
end

local function GetCurrentUpgradeCost(tower, path) 
    if not tower or not tower.LevelHandler then 
        return nil 
    end 
    local maxLvl = tower.LevelHandler:GetMaxLevel() 
    local curLvl = tower.LevelHandler:GetLevelOnPath(path) 
    if curLvl >= maxLvl then 
        return nil 
    end

    local ok, baseCost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
    end)
    if not ok or not baseCost then 
        return nil 
    end

    local discount = 0
    local ok2, disc = pcall(function()
        return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0
    end)
    if ok2 and typeof(disc) == "number" then
        discount = disc
    end

    return math.floor(baseCost * (1 - discount))
end

local function WaitForCash(amount) 
    while cashStat.Value < amount do 
        task.wait() 
    end 
end

local function PlaceTowerRetry(args, axisValue, towerName, fromRebuild) 
    fromRebuild = fromRebuild or false 
    while true do 
        Remotes.PlaceTower:InvokeServer(unpack(args)) 
        task.wait(0.1) 
        local hash = GetTowerByAxis(axisValue) 
        if hash then 
            if fromRebuild then 
                print("[REBUILD] Đặt thành công:", towerName, "X:", axisValue) 
            end 
            return 
        end 
        if fromRebuild then 
            warn("[RETRY] Đặt thất bại:", towerName, "X:", axisValue) 
        end 
    end 
end

local function UpgradeTowerRetry(axisValue, upgradePath, fromRebuild) 
    fromRebuild = fromRebuild or false 
    local mode = globalPlaceMode 
    local maxTries = mode == "rewrite" and math.huge or 3 
    local tries = 0

    while tries < maxTries do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash or not tower then
            if mode == "rewrite" then 
                tries += 1; 
                task.wait(); 
                continue 
            end
            if fromRebuild then 
                warn("[SKIP] Không thấy tower tại X =", axisValue) 
            end
            return
        end

        local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
        if not hp or hp <= 0 then
            if mode == "rewrite" then 
                tries += 1; 
                task.wait(); 
                continue 
            end
            if fromRebuild then 
                warn("[SKIP] Tower đã chết tại X =", axisValue) 
            end
            return
        end

        local before = tower.LevelHandler:GetLevelOnPath(upgradePath)
        local cost = GetCurrentUpgradeCost(tower, upgradePath)
        if not cost then 
            return 
        end

        WaitForCash(cost)
        if fromRebuild then 
            print("[REBUILD] Gửi upgrade X =", axisValue, "path =", upgradePath) 
        end
        Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)

        task.wait(0.1)
        local _, t = GetTowerByAxis(axisValue)
        if t and t.LevelHandler then
            local after = t.LevelHandler:GetLevelOnPath(upgradePath)
            if after > before then
                if fromRebuild then 
                    print("[REBUILD] Upgrade thành công X =", axisValue, "level:", after) 
                end
                return
            end
        end

        if fromRebuild then 
            warn("[RETRY] Upgrade thất bại X =", axisValue) 
        end
        tries += 1
        task.wait()
    end
end

local function ChangeTargetRetry(axisValue, targetType, fromRebuild) 
    fromRebuild = fromRebuild or false 
    local hash = GetTowerByAxis(axisValue) 
    if hash then 
        Remotes.ChangeQueryType:FireServer(hash, targetType) 
        if fromRebuild then 
            print("[REBUILD] Đổi target X =", axisValue, "type =", targetType) 
        end 
    end 
end

local function SellTowerRetry(axisValue, fromRebuild) 
    fromRebuild = fromRebuild or false 
    local hash = GetTowerByAxis(axisValue) 
    if hash then 
        Remotes.SellTower:FireServer(hash) 
        if fromRebuild then 
            print("[REBUILD] Bán tower X =", axisValue) 
        end 
    end 
end

-- Load macro from TDX_Config 
local config = getgenv().TDX_Config or {} 
local macroName = config["Macro Name"] or "default" 
local macroPath = "tdx/macros/" .. macroName .. ".json" 
globalPlaceMode = config["PlaceMode"] or "ashed"

if not isfile(macroPath) then 
    error("Không tìm thấy macro file: " .. macroPath) 
end

local success, macro = pcall(function() 
    return HttpService:JSONDecode(readfile(macroPath)) 
end) 
if not success then 
    error("Lỗi khi đọc macro") 
end

print("[INFO] Đã tải macro:", macroName)

-- Duyệt và chuẩn bị thông tin để rebuild 
local observed = {} 
local towerRecords = {}

for i, entry in ipairs(macro) do 
    if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then 
        local vecTab = entry.TowerVector:split(", ") 
        local pos = Vector3.new(unpack(vecTab)) 
        local axisX = pos.X 
        towerRecords[axisX] = towerRecords[axisX] or {} 
        table.insert(towerRecords[axisX], entry) 
        local _, tower = GetTowerByAxis(axisX) 
        if tower and tower.HealthHandler:GetHealth() <= 0 then 
            observed[axisX] = true 
        end 
    end 
end

-- Rebuild tower khi mất 
for axisX, wasDead in pairs(observed) do 
    if not GetTowerByAxis(axisX) then 
        print("[REBUILD] Tower biến mất tại X =", axisX) 
        for _, record in ipairs(towerRecords[axisX]) do 
            if record.TowerPlaced then 
                local vecTab = record.TowerVector:split(", ") 
                local pos = Vector3.new(unpack(vecTab)) 
                local args = { 
                    tonumber(record.TowerA1), 
                    record.TowerPlaced, 
                    pos, 
                    tonumber(record.Rotation or 0) 
                } 
                WaitForCash(record.TowerPlaceCost) 
                PlaceTowerRetry(args, axisX, record.TowerPlaced, true)
            elseif record.TowerUpgraded then
                UpgradeTowerRetry(axisX, record.UpgradePath, true)
            elseif record.ChangeTarget then
                ChangeTargetRetry(axisX, record.TargetType, true)
            elseif record.SellTower then
                SellTowerRetry(axisX, true)
            end
        end
    end
end
