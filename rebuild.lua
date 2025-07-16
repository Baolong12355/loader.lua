-- TDX Macro Runner - Full Version with SuperFunction Integration + Fix for Upgrade Behavior (Retry Until Success) + Debug
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Debug function
local function DebugPrint(category, message)
    print(string.format("[DEBUG-%s] %s", category, tostring(message)))
end

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
        if success and pos and math.abs(pos.X - axisX) <= 1 then
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
    local curLvl = tower.LevelHandler:GetLevelOnPath(path)
    local maxLvl = tower.LevelHandler:GetMaxLevel()
    if curLvl >= maxLvl then
        return nil
    end
    local ok, cost = pcall(function()
        return tower.LevelHandler:GetLevelUpgradeCost(path, 1)
    end)
    return ok and cost or nil
end

local function WaitForCash(amount)
    while cashStat.Value < amount do
        task.wait()
    end
end

local function PlaceTowerRetry(args, axisValue, towerName)
    while true do
        Remotes.PlaceTower:InvokeServer(unpack(args))
        local t0 = tick()
        repeat
            task.wait(0.1)
            local hash = GetTowerByAxis(axisValue)
            if hash then
                return
            end
        until tick() - t0 > 2
        warn("[RETRY] Đặt tower thất bại, thử lại:", towerName, "X =", axisValue)
    end
end

local function UpgradeTowerRetry(axisValue, upgradePath)
    local maxTries = 10
    local tries = 0
    while tries < maxTries do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash or not tower then
            tries += 1
            warn("[RETRY] Không thấy tower tại X:", axisValue)
            task.wait(0.1)
            continue
        end
        local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
        if not hp or hp <= 0 then
            tries += 1
            warn("[RETRY] Tower chết tại X:", axisValue)
            task.wait(0.1)
            continue
        end
        local before = tower.LevelHandler:GetLevelOnPath(upgradePath)
        local cost = GetCurrentUpgradeCost(tower, upgradePath)
        if not cost then
            return
        end
        WaitForCash(cost)
        Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)
        local t0 = tick()
        repeat
            task.wait(0.25)
            local _, t = GetTowerByAxis(axisValue)
            if t and t.LevelHandler then
                local after = t.LevelHandler:GetLevelOnPath(upgradePath)
                if after > before then
                    return
                end
            end
        until tick() - t0 > 2
        tries += 1
        warn("[RETRY] Nâng cấp thất bại lần:", tries, "X:", axisValue, "Path:", upgradePath)
    end
end

local function ChangeTargetRetry(axisValue, targetType)
    while true do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            Remotes.ChangeQueryType:FireServer(hash, targetType)
            return
        end
        task.wait()
    end
end

local function SellTowerRetry(axisValue)
    while true do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            Remotes.SellTower:FireServer(hash)
            task.wait(0.1)
            if not GetTowerByAxis(axisValue) then
                return
            end
        end
        task.wait()
    end
end

-- Load macro + config
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "ooooo"
local macroPath = "tdx/macros/" .. macroName .. ".json"
globalPlaceMode = config["PlaceMode"] or "normal"

if globalPlaceMode == "unsure" then
    globalPlaceMode = "rewrite"
elseif globalPlaceMode == "normal" then
    globalPlaceMode = "ashed"
end

if not isfile(macroPath) then
    error("Không tìm thấy macro: " .. macroPath)
end

local success, macro = pcall(function()
    return HttpService:JSONDecode(readfile(macroPath))
end)
if not success then
    error("Lỗi khi đọc macro")
end

-- SuperFunction logic with extensive debug
local team, skipNames, skipOnlyBefore, trackedX = {}, {}, false, {}

local function SaveTeam()
    DebugPrint("REBUILD", "Bắt đầu SaveTeam()")
    team = {}
    local towerCount = 0
    
    for hash, tower in pairs(TowerClass.GetTowers()) do
        towerCount = towerCount + 1
        DebugPrint("REBUILD", "Đang xử lý tower #" .. towerCount .. ", hash: " .. tostring(hash))
        
        local success, result = pcall(function()
            local model = tower.Character:GetCharacterModel()
            DebugPrint("REBUILD", "Model: " .. tostring(model and model.Name or "nil"))
            
            local root = model and model.PrimaryPart
            if not root then
                root = model and model:FindFirstChild("HumanoidRootPart")
            end
            
            if root then
                DebugPrint("REBUILD", "Root position: " .. tostring(root.Position))
                return {
                    name = model.Name,
                    x = root.Position.X,
                    vec = {root.Position.X, root.Position.Y, root.Position.Z},
                    a1 = math.random(9999999),
                    rot = 0,
                    cost = 0,
                    upgrades = {}
                }
            else
                DebugPrint("REBUILD", "Không tìm thấy root part")
                return nil
            end
        end)
        
        if success and result then
            table.insert(team, result)
            DebugPrint("REBUILD", "Đã lưu tower: " .. result.name .. " tại X=" .. result.x)
        else
            DebugPrint("REBUILD", "Lỗi khi lưu tower: " .. tostring(result))
        end
    end
    
    DebugPrint("REBUILD", "SaveTeam hoàn thành. Tổng cộng: " .. #team .. " towers")
    
    -- Debug: In ra toàn bộ team
    for i, t in ipairs(team) do
        DebugPrint("REBUILD", string.format("Team[%d]: %s (X=%.2f)", i, t.name, t.x))
    end
end

local function RebuildTeam()
    DebugPrint("REBUILD", "Bắt đầu RebuildTeam()")
    DebugPrint("REBUILD", "Team size: " .. #team)
    
    -- Priority sorting with debug
    local priority = {Medic = 1, ["Golden Mobster"] = 2, Mobster = 2, DJ = 3, Commander = 4}
    
    DebugPrint("REBUILD", "Sắp xếp priority...")
    table.sort(team, function(a, b)
        local priorityA = priority[a.name] or 5
        local priorityB = priority[b.name] or 5
        DebugPrint("REBUILD", string.format("So sánh %s(pri=%d) vs %s(pri=%d)", a.name, priorityA, b.name, priorityB))
        return priorityA < priorityB
    end)
    
    DebugPrint("REBUILD", "Sau khi sắp xếp:")
    for i, t in ipairs(team) do
        DebugPrint("REBUILD", string.format("Team[%d]: %s (X=%.2f)", i, t.name, t.x))
    end
    
    -- Rebuild process
    for i, t in ipairs(team) do
        DebugPrint("REBUILD", string.format("Xử lý tower %d/%d: %s tại X=%.2f", i, #team, t.name, t.x))
        
        if trackedX[t.x] then
            DebugPrint("REBUILD", "Tower đã được tracked, bỏ qua")
            goto continue
        end
        
        if skipNames[t.name] then
            DebugPrint("REBUILD", "Tower bị skip theo tên: " .. t.name)
            goto continue
        end
        
        DebugPrint("REBUILD", "Kiểm tra cash hiện tại: " .. cashStat.Value .. ", cần: " .. (t.cost or 0))
        WaitForCash(t.cost or 0)
        
        DebugPrint("REBUILD", "Chuẩn bị đặt tower...")
        local args = {t.a1, t.name, Vector3.new(unpack(t.vec)), t.rot or 0}
        DebugPrint("REBUILD", string.format("Args: a1=%s, name=%s, pos=(%s), rot=%s", 
            tostring(t.a1), t.name, table.concat(t.vec, ","), tostring(t.rot)))
        
        local placeSuccess, placeError = pcall(function()
            PlaceTowerRetry(args, t.x, t.name)
        end)
        
        if not placeSuccess then
            DebugPrint("REBUILD", "Lỗi khi đặt tower: " .. tostring(placeError))
            goto continue
        end
        
        DebugPrint("REBUILD", "Đặt tower thành công, chờ 0.1s...")
        task.wait(0.1)
        
        -- Process upgrades
        DebugPrint("REBUILD", "Xử lý upgrades: " .. #(t.upgrades or {}))
        for j, upgrade in ipairs(t.upgrades or {}) do
            DebugPrint("REBUILD", string.format("Upgrade %d/%d: %s", j, #t.upgrades, upgrade))
            local upgradeSuccess, upgradeError = pcall(function()
                UpgradeTowerRetry(t.x, upgrade)
            end)
            
            if not upgradeSuccess then
                DebugPrint("REBUILD", "Lỗi khi upgrade: " .. tostring(upgradeError))
            else
                DebugPrint("REBUILD", "Upgrade thành công")
            end
            task.wait(0.1)
        end
        
        trackedX[t.x] = true
        DebugPrint("REBUILD", "Đã mark tower X=" .. t.x .. " là tracked")
        task.wait(2)
        
        ::continue::
    end
    
    DebugPrint("REBUILD", "RebuildTeam hoàn thành")
end

local function TrackDead()
    DebugPrint("REBUILD", "Bắt đầu TrackDead thread")
    
    while true do
        for i, t in ipairs(team) do
            if not trackedX[t.x] then
                DebugPrint("REBUILD", string.format("Kiểm tra tower %s tại X=%.2f", t.name, t.x))
                
                local _, tower = GetTowerByAxis(t.x)
                if not tower then
                    DebugPrint("REBUILD", "Tower chết! Bắt đầu rebuild...")
                    local rebuildSuccess, rebuildError = pcall(function()
                        RebuildTeam()
                    end)
                    
                    if not rebuildSuccess then
                        DebugPrint("REBUILD", "Lỗi trong RebuildTeam: " .. tostring(rebuildError))
                    end
                    return
                else
                    DebugPrint("REBUILD", "Tower vẫn còn sống")
                end
            end
        end
        task.wait(1)
    end
end

-- Main execution with debug
for entryIndex, entry in ipairs(macro) do
    DebugPrint("MAIN", "Xử lý entry #" .. entryIndex)
    
    if entry.SuperFunction == "SellAll" then
        DebugPrint("MAIN", "Thực hiện SellAll")
        local skipSet = {}
        for _, v in ipairs(entry.Skip or {}) do
            skipSet[v] = true
        end
        for hash, tower in pairs(TowerClass.GetTowers()) do
            local model = tower.Character:GetCharacterModel()
            if model and not skipSet[model.Name] then
                Remotes.SellTower:FireServer(hash)
                trackedX[model.PrimaryPart.Position.X] = true
                task.wait(0.1)
            end
        end

    elseif entry.SuperFunction == "rebuild" then
        DebugPrint("MAIN", "Thực hiện rebuild command")
        
        -- Process skip list
        DebugPrint("MAIN", "Skip list: " .. table.concat(entry.Skip or {}, ", "))
        for _, name in ipairs(entry.Skip or {}) do
            skipNames[name] = true
            DebugPrint("MAIN", "Đã thêm vào skip: " .. name)
        end
        
        skipOnlyBefore = entry.Be == true
        DebugPrint("MAIN", "skipOnlyBefore: " .. tostring(skipOnlyBefore))
        
        local saveSuccess, saveError = pcall(function()
            SaveTeam()
        end)
        
        if not saveSuccess then
            DebugPrint("MAIN", "Lỗi trong SaveTeam: " .. tostring(saveError))
        else
            DebugPrint("MAIN", "SaveTeam thành công")
            
            local trackSuccess, trackError = pcall(function()
                task.spawn(TrackDead)
            end)
            
            if not trackSuccess then
                DebugPrint("MAIN", "Lỗi khi spawn TrackDead: " .. tostring(trackError))
            else
                DebugPrint("MAIN", "TrackDead thread đã được spawn")
            end
        end

    elseif entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
        DebugPrint("MAIN", "Đặt tower: " .. entry.TowerPlaced)
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
        DebugPrint("MAIN", "Nâng cấp tower tại X=" .. entry.TowerUpgraded .. ", path=" .. entry.UpgradePath)
        local axisValue = tonumber(entry.TowerUpgraded)
        UpgradeTowerRetry(axisValue, entry.UpgradePath)
        if team then
            for _, t in ipairs(team) do
                if t.x == axisValue then
                    t.upgrades = t.upgrades or {}
                    table.insert(t.upgrades, entry.UpgradePath)
                    DebugPrint("MAIN", "Đã thêm upgrade vào team record: " .. entry.UpgradePath)
                end
            end
        end

    elseif entry.ChangeTarget and entry.TargetType then
        DebugPrint("MAIN", "Đổi target tại X=" .. entry.ChangeTarget .. " thành " .. entry.TargetType)
        ChangeTargetRetry(tonumber(entry.ChangeTarget), entry.TargetType)

    elseif entry.SellTower then
        DebugPrint("MAIN", "Bán tower tại X=" .. entry.SellTower)
        trackedX[tonumber(entry.SellTower)] = true
        SellTowerRetry(entry.SellTower)
    end
end

DebugPrint("MAIN", "✅ Macro hoàn tất")
print("✅ Macro hoàn tất")
