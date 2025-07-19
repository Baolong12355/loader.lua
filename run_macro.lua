-- TDX Macro Runner - Compatible với Executor và GitHub
-- Tương thích với mọi executor phổ biến

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Compatibility layer cho các executor khác nhau
local function getGlobalEnv()
    return getgenv and getgenv() or _G
end

local function safeRequire(module)
    local success, result = pcall(function() return require(module) end)
    return success and result or nil
end

local function safeReadFile(path)
    if readfile then
        return readfile(path)
    else
        warn("readfile không khả dụng - vui lòng sử dụng executor hỗ trợ file system")
        return nil
    end
end

local function safeIsFile(path)
    if isfile then
        return isfile(path)
    else
        return false
    end
end

-- Cấu hình mặc định
local defaultConfig = {
    ["Macro Name"] = "event",
    ["PlaceMode"] = "Ashed",
    ["ForceRebuildEvenIfSold"] = true,
    ["MaxRebuildRetry"] = nil, -- nil = infinite
    ["SellAllDelay"] = 0.1,
    ["PriorityRebuildOrder"] = {"EDJ", "Medic", "Commander", "Mobster", "Golden Mobster"},
    ["TargetChangeCheckDelay"] = 0.1,
    ["CheDoDebug"] = false,
    ["RebuildPriority"] = true,
    ["RebuildCheckInterval"] = 0.05,
    ["MacroStepDelay"] = 0.1
}

-- Khởi tạo config với compatibility
local globalEnv = getGlobalEnv()
globalEnv.TDX_Config = globalEnv.TDX_Config or {}

-- Merge với config mặc định
for key, value in pairs(defaultConfig) do
    if globalEnv.TDX_Config[key] == nil then
        globalEnv.TDX_Config[key] = value
    end
end

local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        local success, result = pcall(function() return require(path) end)
        if success then return result end
        task.wait()
    end
    return nil
end

local function LoadTowerClass()
    local ps = player:FindFirstChild("PlayerScripts")
    if not ps then 
        warn("PlayerScripts không tìm thấy")
        return nil 
    end
    
    local client = ps:FindFirstChild("Client")
    if not client then 
        warn("Client không tìm thấy") 
        return nil 
    end
    
    local gameClass = client:FindFirstChild("GameClass")
    if not gameClass then 
        warn("GameClass không tìm thấy") 
        return nil 
    end
    
    local towerModule = gameClass:FindFirstChild("TowerClass")
    if not towerModule then 
        warn("TowerClass module không tìm thấy") 
        return nil 
    end
    
    return SafeRequire(towerModule)
end

-- Tải TowerClass với error handling
local TowerClass = LoadTowerClass()
if not TowerClass then 
    error("Không thể load TowerClass - vui lòng đảm bảo bạn đang trong game TDX")
end

-- Hàm lấy UI elements
local function getGameUI()
    local attempts = 0
    while attempts < 30 do -- Tối đa 30 giây
        local interface = PlayerGui:FindFirstChild("Interface")
        if interface then
            local gameInfoBar = interface:FindFirstChild("GameInfoBar")
            if gameInfoBar then
                local waveFrame = gameInfoBar:FindFirstChild("Wave")
                local timeFrame = gameInfoBar:FindFirstChild("TimeLeft")
                
                if waveFrame and timeFrame then
                    local waveText = waveFrame:FindFirstChild("WaveText")
                    local timeText = timeFrame:FindFirstChild("TimeLeftText")
                    
                    if waveText and timeText then
                        return {
                            waveText = waveText,
                            timeText = timeText
                        }
                    end
                end
            end
        end
        attempts = attempts + 1
        task.wait(1)
    end
    error("Không thể tìm thấy Game UI - đảm bảo bạn đang trong trận đấu")
end

-- Chuyển số thành chuỗi thời gian
local function convertToTimeFormat(number)
    local mins = math.floor(number / 100)
    local secs = number % 100
    return string.format("%02d:%02d", mins, secs)
end

-- Hàm xác định độ ưu tiên
local function GetTowerPriority(towerName)
    for priority, name in ipairs(globalEnv.TDX_Config.PriorityRebuildOrder or {}) do
        if towerName == name then
            return priority
        end
    end
    return math.huge
end

-- Hàm SellAll
local function SellAllTowers(skipList)
    local skipMap = {}
    if skipList then
        for _, name in ipairs(skipList) do
            skipMap[name] = true
        end
    end

    for hash, tower in pairs(TowerClass.GetTowers()) do
        local success, model = pcall(function()
            return tower.Character and tower.Character:GetCharacterModel()
        end)
        
        if success and model then
            local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
            if root and not skipMap[root.Name] then
                pcall(function()
                    Remotes.SellTower:FireServer(hash)
                end)
                task.wait(globalEnv.TDX_Config.SellAllDelay or 0.1)
            end
        end
    end
end

local function GetTowerByAxis(axisX)
    for hash, tower in pairs(TowerClass.GetTowers()) do
        local success, pos, name = pcall(function()
            local model = tower.Character:GetCharacterModel()
            local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
            return root and root.Position, model and (root and root.Name or model.Name)
        end)
        if success and pos and math.abs(pos.X - axisX) < 0.1 then -- Sử dụng tolerance để tránh floating point issues
            local hp = 1 -- Mặc định là 1 nếu không có HealthHandler
            pcall(function()
                hp = tower.HealthHandler and tower.HealthHandler:GetHealth() or 1
            end)
            if hp and hp > 0 then
                return hash, tower, name or "(NoName)"
            end
        end
    end
    return nil, nil, nil
end

local function GetCurrentUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return nil end
    local maxLvl = tower.LevelHandler:GetMaxLevel()
    local curLvl = tower.LevelHandler:GetLevelOnPath(path)
    if curLvl >= maxLvl then return nil end
    local ok, baseCost = pcall(function() return tower.LevelHandler:GetLevelUpgradeCost(path, 1) end)
    if not ok then return nil end
    local disc = 0
    local ok2, d = pcall(function() return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end)
    if ok2 and typeof(d) == "number" then disc = d end
    return math.floor(baseCost * (1 - disc))
end

local function WaitForCash(amount)
    while cashStat.Value < amount do task.wait(0.1) end
end

local function PlaceTowerRetry(args, axisValue, towerName)
    local maxAttempts = 10
    local attempts = 0
    
    while attempts < maxAttempts do
        local success = pcall(function()
            Remotes.PlaceTower:InvokeServer(unpack(args))
        end)
        
        if success then
            local t0 = tick()
            repeat 
                task.wait(0.05) 
            until tick() - t0 > 3 or GetTowerByAxis(axisValue)
            
            if GetTowerByAxis(axisValue) then 
                return 
            end
        end
        
        attempts = attempts + 1
        task.wait()
    end
    
    warn("Không thể đặt tower sau", maxAttempts, "lần thử")
end

local function UpgradeTowerRetry(axisValue, path)
    local maxAttempts = 10
    local attempts = 0
    
    while attempts < maxAttempts do
        local hash, tower = GetTowerByAxis(axisValue)
        if not hash then 
            task.wait(0.05) 
            attempts = attempts + 1
            continue 
        end

        local before = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        if not cost then return end

        WaitForCash(cost)
        
        local success = pcall(function()
            Remotes.TowerUpgradeRequest:FireServer(hash, path, 1)
        end)
        
        if success then
            local t0 = tick()
            repeat
                task.wait(0.1)
                local _, t = GetTowerByAxis(axisValue)
                if t and t.LevelHandler:GetLevelOnPath(path) > before then return end
            until tick() - t0 > 3
        end
        
        attempts = attempts + 1
        task.wait()
    end
end

local function ChangeTargetRetry(axisValue, targetType)
    local maxAttempts = 5
    local attempts = 0
    
    while attempts < maxAttempts do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            pcall(function()
                Remotes.ChangeQueryType:FireServer(hash, targetType)
            end)
            return
        end
        attempts = attempts + 1
        task.wait(0.1)
    end
end

local function SellTowerRetry(axisValue)
    local maxAttempts = 5
    local attempts = 0
    
    while attempts < maxAttempts do
        local hash = GetTowerByAxis(axisValue)
        if hash then
            pcall(function()
                Remotes.SellTower:FireServer(hash)
            end)
            task.wait(0.05)
            if not GetTowerByAxis(axisValue) then return true end
        end
        attempts = attempts + 1
        task.wait()
    end
    return false
end

-- Hàm kiểm tra điều kiện target change
local function shouldChangeTarget(entry, currentWave, currentTime)
    if entry.TargetWave and entry.TargetWave ~= currentWave then
        return false
    end
    
    if entry.TargetChangedAt then
        local targetTimeStr = convertToTimeFormat(entry.TargetChangedAt)
        if currentTime ~= targetTimeStr then
            return false
        end
    end
    
    return true
end

-- Hệ thống Target Change Monitor
local function StartTargetChangeMonitor(targetChangeEntries, gameUI)
    local processedEntries = {}
    
    task.spawn(function()
        while true do
            local success, currentWave, currentTime = pcall(function()
                return gameUI.waveText.Text, gameUI.timeText.Text
            end)
            
            if success then
                for i, entry in ipairs(targetChangeEntries) do
                    if not processedEntries[i] and shouldChangeTarget(entry, currentWave, currentTime) then
                        local axisValue = entry.TowerTargetChange
                        local targetType = entry.TargetWanted
                        
                        ChangeTargetRetry(axisValue, targetType)
                        processedEntries[i] = true
                    end
                end
            end
            
            task.wait(globalEnv.TDX_Config.TargetChangeCheckDelay)
        end
    end)
end

-- Hàm khởi tạo hệ thống Rebuild
local function StartRebuildSystem(rebuildEntry, towerRecords, skipTypesMap)
    local rebuildAttempts = {}
    local soldPositions = {}
    local config = globalEnv.TDX_Config
    
    task.spawn(function()
        while true do
            if next(towerRecords) then -- Chỉ chạy khi đã có tower records
                local rebuildFound = false
                
                -- Sắp xếp rebuild theo độ ưu tiên
                local rebuildQueue = {}
                
                for x, records in pairs(towerRecords) do
                    local hash, tower = GetTowerByAxis(x)
                    if not hash or not tower then -- Tower bị mất/chết
                        -- Tìm tower type từ records
                        local towerType = nil
                        local firstPlaceRecord = nil
                        
                        for _, record in ipairs(records) do
                            if record.entry.TowerPlaced then 
                                towerType = record.entry.TowerPlaced
                                firstPlaceRecord = record
                                break
                            end
                        end
                        
                        if not towerType then continue end
                        
                        -- Kiểm tra skip rules
                        local skipRule = skipTypesMap[towerType]
                        if skipRule then
                            if skipRule.beOnly and firstPlaceRecord.line < skipRule.fromLine then
                                continue
                            elseif not skipRule.beOnly then
                                continue
                            end
                        end
                        
                        -- Kiểm tra ForceRebuildEvenIfSold
                        if soldPositions[x] and not config.ForceRebuildEvenIfSold then
                            continue
                        end
                        
                        -- Kiểm tra MaxRebuildRetry
                        rebuildAttempts[x] = (rebuildAttempts[x] or 0) + 1
                        local maxRetry = config.MaxRebuildRetry
                        if maxRetry and rebuildAttempts[x] > maxRetry then
                            continue
                        end
                        
                        -- Thêm vào queue rebuild
                        local priority = GetTowerPriority(towerType)
                        table.insert(rebuildQueue, {
                            x = x,
                            records = records,
                            priority = priority,
                            towerType = towerType,
                            attempts = rebuildAttempts[x]
                        })
                    end
                end
                
                -- Sắp xếp theo độ ưu tiên (thấp hơn = ưu tiên cao hơn)
                table.sort(rebuildQueue, function(a, b)
                    if a.priority == b.priority then
                        return a.x < b.x -- Nếu cùng priority thì sắp xếp theo X
                    end
                    return a.priority < b.priority
                end)
                
                -- Rebuild tower có priority cao nhất
                for _, rebuildItem in ipairs(rebuildQueue) do
                    local x = rebuildItem.x
                    local records = rebuildItem.records
                    local towerType = rebuildItem.towerType
                    
                    -- Thực hiện tất cả các actions cho tower này
                    local rebuildSuccess = true
                    for _, record in ipairs(records) do
                        local action = record.entry
                        
                        if action.TowerPlaced then
                            local vecTab = {}
                            for coord in action.TowerVector:gmatch("[^,%s]+") do
                                table.insert(vecTab, tonumber(coord))
                            end
                            if #vecTab == 3 then
                                local pos = Vector3.new(vecTab[1], vecTab[2], vecTab[3])
                                local args = {
                                    tonumber(action.TowerA1), 
                                    action.TowerPlaced, 
                                    pos, 
                                    tonumber(action.Rotation or 0)
                                }
                                WaitForCash(action.TowerPlaceCost)
                                PlaceTowerRetry(args, pos.X, action.TowerPlaced)
                                
                                -- Kiểm tra placement thành công
                                local placedHash = GetTowerByAxis(pos.X)
                                if not placedHash then
                                    rebuildSuccess = false
                                    break
                                end
                            end
                            
                        elseif action.TowerUpgraded then
                            UpgradeTowerRetry(tonumber(action.TowerUpgraded), action.UpgradePath)
                            
                        elseif action.ChangeTarget then
                            ChangeTargetRetry(tonumber(action.ChangeTarget), action.TargetType)
                            
                        elseif action.SellTower then
                            local sellSuccess = SellTowerRetry(tonumber(action.SellTower))
                            if sellSuccess then
                                soldPositions[tonumber(action.SellTower)] = true
                            end
                        end
                        
                        task.wait(0.03) -- Delay ngắn giữa các actions
                    end
                    
                    if rebuildSuccess then
                        rebuildAttempts[x] = 0 -- Reset attempts khi thành công
                    end
                    
                    rebuildFound = true
                    break -- Chỉ rebuild một tower mỗi lần
                end
                
                if not rebuildFound then
                    -- Không có tower nào cần rebuild
                    task.wait(config.RebuildCheckInterval * 2)
                else
                    task.wait(config.RebuildCheckInterval)
                end
            else
                -- Chưa có tower records, wait
                task.wait(0.5)
            end
        end
    end)
end

-- Main execution function
local function RunMacroRunner()
    local config = globalEnv.TDX_Config
    local macroName = config["Macro Name"] or "event"
    local macroPath = "tdx/macros/" .. macroName .. ".json"

    -- Kiểm tra file macro
    if not safeIsFile(macroPath) then 
        warn("Không tìm thấy file macro:", macroPath)
        warn("Vui lòng đảm bảo file macro tồn tại hoặc executor hỗ trợ file system")
        return 
    end

    local macroContent = safeReadFile(macroPath)
    if not macroContent then
        warn("Không thể đọc file macro")
        return
    end

    local ok, macro = pcall(function() 
        return HttpService:JSONDecode(macroContent) 
    end)
    
    if not ok or type(macro) ~= "table" then 
        warn("Lỗi khi parse macro file:", ok and "Invalid JSON format" or macro)
        return 
    end

    -- Lấy UI elements
    local gameUI = getGameUI()

    local towerRecords = {}
    local skipTypesMap = {}
    local targetChangeEntries = {}
    local rebuildSystemActive = false

    -- Pre-scan macro để tìm target changes
    for i, entry in ipairs(macro) do
        if entry.TowerTargetChange then
            table.insert(targetChangeEntries, entry)
        end
    end

    -- Khởi động Target Monitor nếu cần
    if #targetChangeEntries > 0 then
        StartTargetChangeMonitor(targetChangeEntries, gameUI)
    end
    
    -- Main macro execution loop
    for i, entry in ipairs(macro) do
        if entry.SuperFunction == "sell_all" then
            SellAllTowers(entry.Skip)
            
        elseif entry.SuperFunction == "rebuild" then
            -- Kích hoạt hệ thống rebuild khi gặp dòng này
            if not rebuildSystemActive then
                -- Setup skip rules từ entry hiện tại
                for _, skip in ipairs(entry.Skip or {}) do
                    skipTypesMap[skip] = { beOnly = entry.Be == true, fromLine = i }
                end
                
                -- Khởi tạo hệ thống rebuild
                StartRebuildSystem(entry, towerRecords, skipTypesMap)
                rebuildSystemActive = true
                
                print("Hệ thống Rebuild đã được kích hoạt tại dòng", i)
            end
            
        elseif entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost th