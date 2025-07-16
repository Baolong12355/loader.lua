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
        if success and pos and pos.X == axisX then
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
            if hash then return true end
        until tick() - t0 > 2
        warn("[RETRY] Đặt tower thất bại, thử lại:", towerName, "X =", axisValue)
    end
end

-- Nâng cấp tower
local function UpgradeTowerRetry(axisValue, upgradePath)
    local hash, tower = GetTowerByAxis(axisValue)
    if not hash or not tower then return false end

    local before = tower.LevelHandler:GetLevelOnPath(upgradePath)
    local cost = GetCurrentUpgradeCost(tower, upgradePath)
    if not cost then return false end

    WaitForCash(cost)
    Remotes.TowerUpgradeRequest:FireServer(hash, upgradePath, 1)

    local t0 = tick()
    repeat
        task.wait(0.1)
        local _, t = GetTowerByAxis(axisValue)
        if t and t.LevelHandler then
            local after = t.LevelHandler:GetLevelOnPath(upgradePath)
            if after > before then return true end
        end
    until tick() - t0 > 2
    return false
end

-- Đổi target
local function ChangeTargetRetry(axisValue, targetType)
    local hash = GetTowerByAxis(axisValue)
    if hash then
        Remotes.ChangeQueryType:FireServer(hash, targetType)
        return true
    end
    return false
end

-- Bán tower
local function SellTowerRetry(axisValue)
    local hash = GetTowerByAxis(axisValue)
    if hash then
        Remotes.SellTower:FireServer(hash)
        return not GetTowerByAxis(axisValue)
    end
    return false
end

-- Thêm bảng ưu tiên tower
local TOWER_PRIORITY = {
    ["Medic"] = 1,
    ["Mobster"] = 2,
    ["Golden Mobster"] = 3,
    ["Commander"] = 4,
    ["DJ Booth"] = 5
}

-- Lấy độ ưu tiên của tower
local function GetTowerPriority(towerName)
    for name, priority in pairs(TOWER_PRIORITY) do
        if string.find(towerName, name) then
            return priority
        end
    end
    return 6 -- Mức ưu tiên thấp nhất
end

-- Tìm tất cả tower đã chết
local function FindDeadTowers()
    local deadTowers = {}
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local hp = tower.HealthHandler and tower.HealthHandler:GetHealth()
        if hp and hp <= 0 then
            local model = tower.Character:GetCharacterModel()
            local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
            if root then
                table.insert(deadTowers, {
                    hash = hash,
                    name = tower.Name,
                    position = root.Position,
                    priority = GetTowerPriority(tower.Name)
                })
            end
        end
    end
    table.sort(deadTowers, function(a, b) return a.priority < b.priority end)
    return deadTowers
end

-- Chờ tower biến mất
local function WaitForTowerToDisappear(position)
    while true do
        local found = false
        for hash, tower in pairs(TowerClass.GetTowers()) do
            local model = tower.Character:GetCharacterModel()
            local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
            if root and (root.Position - position).Magnitude < 5 then
                found = true
                break
            end
        end
        if not found then return true end
        task.wait(0.5)
    end
end

-- Lưu trữ các entry đã thực hiện
local executedMacroEntries = {}

-- Hàm rebuild tower
local function RebuildTower(deadTower)
    local maxRetries = 3
    local success = false
    
    for retry = 1, maxRetries do
        -- Tìm các entry liên quan đã thực hiện
        local relevantEntries = {}
        for _, entry in ipairs(executedMacroEntries) do
            if entry.type == "place" and entry.data.TowerPlaced == deadTower.name and 
               (Vector3.new(unpack(entry.data.TowerVector:split(", "))) - deadTower.position).Magnitude < 5 then
                table.insert(relevantEntries, entry)
            elseif entry.type == "upgrade" and tostring(deadTower.position.X) == entry.data.TowerUpgraded then
                table.insert(relevantEntries, entry)
            elseif entry.type == "changetarget" and tostring(deadTower.position.X) == entry.data.ChangeTarget then
                table.insert(relevantEntries, entry)
            end
        end
        
        -- Sắp xếp theo thứ tự đúng
        table.sort(relevantEntries, function(a, b)
            if a.type == "place" then return true end
            if b.type == "place" then return false end
            if a.type == "upgrade" then return true end
            return false
        end)
        
        -- Thực hiện rebuild
        success = true
        for _, entry in ipairs(relevantEntries) do
            local executed = false
            
            if entry.type == "place" then
                local data = entry.data
                local vecTab = data.TowerVector:split(", ")
                local pos = Vector3.new(unpack(vecTab))
                local args = {
                    tonumber(data.TowerA1),
                    data.TowerPlaced,
                    pos,
                    tonumber(data.Rotation or 0)
                }
                if cashStat.Value >= data.TowerPlaceCost then
                    executed = PlaceTowerRetry(args, pos.X, data.TowerPlaced)
                else
                    success = false
                end
                
            elseif entry.type == "upgrade" then
                executed = UpgradeTowerRetry(deadTower.position.X, entry.data.UpgradePath)
                
            elseif entry.type == "changetarget" then
                executed = ChangeTargetRetry(deadTower.position.X, entry.data.TargetType)
            end
            
            if not executed then
                success = false
                break
            end
            task.wait(0.2)
        end
        
        -- Kiểm tra kết quả
        if success then
            local _, tower = GetTowerByAxis(deadTower.position.X)
            if tower and tower.HealthHandler:GetHealth() > 0 then
                print(`✅ Đã tái tạo thành công {deadTower.name} (lần {retry})`)
                return true
            end
        end
        
        if retry < maxRetries then
            print(`🔄 Thử lại tái tạo {deadTower.name} (lần {retry + 1})`)
            task.wait(1)
        end
    end
    
    print(`❌ Không thể tái tạo {deadTower.name} sau {maxRetries} lần thử`)
    return false
end

-- Hàm kiểm tra và rebuild
local function CheckAndRebuildDeadTowers()
    local deadTowers = FindDeadTowers()
    for _, deadTower in ipairs(deadTowers) do
        print(`⚠️ Phát hiện {deadTower.name} đã chết tại {deadTower.position}`)
        WaitForTowerToDisappear(deadTower.position)
        RebuildTower(deadTower)
    end
end

-- Load macro
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "event"
local macroPath = "tdx/macros/" .. macroName .. ".json"
globalPlaceMode = config["PlaceMode"] or "normal"

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

-- Chạy macro chính và lưu lại các entry đã thực hiện
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
        if PlaceTowerRetry(args, pos.X, entry.TowerPlaced) then
            table.insert(executedMacroEntries, {
                type = "place",
                data = table.clone(entry)
            })
        end

    elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then
        local axisValue = tonumber(entry.TowerUpgraded)
        if UpgradeTowerRetry(axisValue, entry.UpgradePath) then
            table.insert(executedMacroEntries, {
                type = "upgrade",
                data = table.clone(entry)
            })
        end

    elseif entry.ChangeTarget and entry.TargetType then
        local axisValue = tonumber(entry.ChangeTarget)
        if ChangeTargetRetry(axisValue, entry.TargetType) then
            table.insert(executedMacroEntries, {
                type = "changetarget",
                data = table.clone(entry)
            })
        end

    elseif entry.SellTower then
        local axisValue = tonumber(entry.SellTower)
        SellTowerRetry(axisValue)
    end
end

print("✅ Macro chạy hoàn tất.")

-- Bật chế độ tự động rebuild
local rebuildInterval = 1 -- giây
while task.wait(rebuildInterval) do
    pcall(CheckAndRebuildDeadTowers)
end
