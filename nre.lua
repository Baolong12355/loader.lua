local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

local jsonFile = "tdx/macros/record.json"

-- Khởi tạo thư mục và file JSON
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

-- Khởi tạo JSON array rỗng
if not isfile(jsonFile) then
    writefile(jsonFile, "[]")
end

-- Load TowerClass với hàm SafeRequire từ runner
local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local startTime = tick()
    
    while tick() - startTime < timeout do
        local success, result = pcall(function() 
            return require(path) 
        end)
        if success and result then 
            return result 
        end
        RunService.Heartbeat:Wait()
    end
    return nil
end

local function LoadTowerClass()
    local ps = player:FindFirstChild("PlayerScripts")
    if not ps then return nil end
    
    local client = ps:FindFirstChild("Client")
    if not client then return nil end
    
    local gameClass = client:FindFirstChild("GameClass")
    if not gameClass then return nil end
    
    local towerModule = gameClass:FindFirstChild("TowerClass")
    if not towerModule then return nil end
    
    return SafeRequire(towerModule)
end

-- Load TowerClass
local TowerClass = LoadTowerClass()
if not TowerClass then 
    warn("Không thể load TowerClass - một số tính năng có thể không hoạt động")
end

-- Hàm lấy chi phí nâng cấp hiện tại từ runner
local function GetCurrentUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then return 0 end
    local maxLvl = tower.LevelHandler:GetMaxLevel()
    local curLvl = tower.LevelHandler:GetLevelOnPath(path)
    if curLvl >= maxLvl then return 0 end
    local ok, baseCost = pcall(function() return tower.LevelHandler:GetLevelUpgradeCost(path, 1) end)
    if not ok then return 0 end
    local disc = 0
    local ok2, d = pcall(function() return tower.BuffHandler and tower.BuffHandler:GetDiscount() or 0 end)
    if ok2 and typeof(d) == "number" then disc = d end
    return math.floor(baseCost * (1 - disc))
end

-- Hàm lấy tower position
local function GetTowerPosition(tower)
    if not tower or not tower.Character then return nil end
    local model = tower.Character:GetCharacterModel()
    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
    return root and root.Position or nil
end

-- Hàm lấy chi phí đặt tower
local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return 0 end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return 0 end
    local bottomBar = interface:FindFirstChild("BottomBar")
    if not bottomBar then return 0 end
    local towersBar = bottomBar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end
    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == name then
            local costFrame = tower:FindFirstChild("CostFrame")
            local costText = costFrame and costFrame:FindFirstChild("CostText")
            if costText then
                local raw = tostring(costText.Text):gsub("%D", "")
                return tonumber(raw) or 0
            end
        end
    end
    return 0
end

-- Hàm lấy wave và time hiện tại
local function getCurrentWaveAndTime()
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return nil, nil end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return nil, nil end
    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
    if not gameInfoBar then return nil, nil end

    local waveText = gameInfoBar:FindFirstChild("Wave") and gameInfoBar.Wave:FindFirstChild("WaveText")
    local timeText = gameInfoBar:FindFirstChild("TimeLeft") and gameInfoBar.TimeLeft:FindFirstChild("TimeLeftText")
    
    if waveText and timeText then
        return waveText.Text, timeText.Text
    end
    return nil, nil
end

-- Chuyển time format từ "MM:SS" thành số
local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- Ánh xạ hash -> position và level tracking
local hash2pos = {}
local towerLevels = {} -- Theo dõi cấp độ tower: hash -> {path1Level, path2Level, path3Level}

if TowerClass then
    task.spawn(function()
        while true do
            for hash, tower in pairs(TowerClass.GetTowers()) do
                local pos = GetTowerPosition(tower)
                if pos then
                    hash2pos[tostring(hash)] = pos
                    
                    -- Theo dõi cấp độ của từng path
                    if tower.LevelHandler then
                        local hashStr = tostring(hash)
                        towerLevels[hashStr] = towerLevels[hashStr] or {0, 0, 0}
                        
                        for path = 1, 3 do
                            local currentLevel = tower.LevelHandler:GetLevelOnPath(path)
                            towerLevels[hashStr][path] = currentLevel or 0
                        end
                    end
                end
            end
            task.wait(0.1)
        end
    end)
end

-- Hàm đọc JSON array hiện tại
local function readCurrentJSON()
    if not isfile(jsonFile) then return {} end
    local content = readfile(jsonFile)
    if not content or content == "" then return {} end
    
    local success, result = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    
    if success and type(result) == "table" then
        return result
    end
    return {}
end

-- Hàm thêm entry vào JSON
local function addJSONEntry(entry)
    local currentData = readCurrentJSON()
    table.insert(currentData, entry)
    
    local success = pcall(function()
        local jsonString = HttpService:JSONEncode(currentData)
        writefile(jsonFile, jsonString)
    end)
    
    if success then
        print("✅ Đã ghi: " .. (entry.TowerPlaced or entry.TowerUpgraded or entry.TowerTargetChange or entry.SellTower or "Unknown"))
    else
        warn("❌ Lỗi ghi JSON")
    end
end

-- Pending system với timeout (chỉ cho Place, Sell, Target)
local pending = nil
local timeout = 3

local function setPending(typeStr, entryData)
    pending = {
        type = typeStr,
        entry = entryData,
        created = tick()
    }
end

local function confirmPending()
    if pending then
        addJSONEntry(pending.entry)
        pending = nil
    end
end

local function tryConfirm(typeStr)
    if pending and pending.type == typeStr then
        confirmPending()
    end
end

-- Timeout check
task.spawn(function()
    while true do
        task.wait(0.1)
        if pending and tick() - pending.created > timeout then
            warn("❌ Timeout cho: " .. pending.type)
            pending = nil
        end
    end
end)

-- Event listeners (không có cho upgrade)
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data[1]
    if not d then return end
    if d.Creation then
        tryConfirm("Place")
    else
        tryConfirm("Sell")
    end
end)

ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data[1] then
        tryConfirm("Target")
    end
end)

-- Hàm kiểm tra upgrade thành công bằng cách theo dõi cấp độ
local function checkUpgradeSuccess(hash, path, expectedNewLevel)
    if not TowerClass then return false end
    
    local hashStr = tostring(hash)
    local startTime = tick()
    
    while tick() - startTime < 2 do -- Timeout 2 giây
        local tower = TowerClass.GetTowers()[hash]
        if tower and tower.LevelHandler then
            local currentLevel = tower.LevelHandler:GetLevelOnPath(path)
            if currentLevel >= expectedNewLevel then
                -- Cập nhật level tracking
                towerLevels[hashStr] = towerLevels[hashStr] or {0, 0, 0}
                towerLevels[hashStr][path] = currentLevel
                return true
            end
        end
        task.wait(0.05)
    end
    
    return false
end

-- Hook functions
local function hookPlaceTower(args)
    local towerA1, towerName, position, rotation = unpack(args)
    local cost = GetTowerPlaceCostByName(towerName)
    
    local entry = {
        TowerPlaceCost = cost,
        TowerPlaced = towerName,
        TowerVector = string.format("%.1f, %.1f, %.1f", position.X, position.Y, position.Z),
        Rotation = tostring(rotation or 0),
        TowerA1 = tostring(towerA1)
    }
    
    setPending("Place", entry)
end

local function hookUpgradeTower(args)
    local hash, path, count = unpack(args)
    
    if not TowerClass then
        local entry = {
            UpgradeCost = 0,
            UpgradePath = path,
            TowerUpgraded = 0
        }
        addJSONEntry(entry) -- Ghi ngay lập tức nếu không có TowerClass
        return
    end
    
    -- Tìm tower và lấy thông tin hiện tại
    local tower = TowerClass.GetTowers()[hash]
    local pos = tower and GetTowerPosition(tower)
    
    if pos and tower.LevelHandler then
        local currentLevel = tower.LevelHandler:GetLevelOnPath(path)
        local cost = GetCurrentUpgradeCost(tower, path)
        local expectedNewLevel = currentLevel + (count or 1)
        
        -- Spawn task để kiểm tra upgrade thành công
        task.spawn(function()
            if checkUpgradeSuccess(hash, path, expectedNewLevel) then
                local entry = {
                    UpgradeCost = cost,
                    UpgradePath = path,
                    TowerUpgraded = pos.X
                }
                addJSONEntry(entry)
            else
                warn("❌ Upgrade không thành công cho tower tại X=" .. pos.X)
            end
        end)
    end
end

local function hookChangeTarget(args)
    local hash, targetType = unpack(args)
    
    if not TowerClass then return end
    
    local pos = hash2pos[tostring(hash)]
    if not pos then
        -- Thử tìm trong TowerClass.GetTowers()
        local tower = TowerClass.GetTowers()[hash]
        pos = tower and GetTowerPosition(tower)
    end
    
    if pos then
        local currentWave, currentTime = getCurrentWaveAndTime()
        local timeNumber = convertTimeToNumber(currentTime)
        
        local entry = {
            TowerTargetChange = pos.X,
            TargetWanted = targetType
        }
        
        if currentWave then
            entry.TargetWave = currentWave
        end
        
        if timeNumber then
            entry.TargetChangedAt = timeNumber
        end
        
        setPending("Target", entry)
    end
end

local function hookSellTower(args)
    local hash = unpack(args)
    
    if not TowerClass then return end
    
    local pos = hash2pos[tostring(hash)]
    if not pos then
        local tower = TowerClass.GetTowers()[hash]
        pos = tower and GetTowerPosition(tower)
    end
    
    if pos then
        local entry = {
            SellTower = pos.X
        }
        setPending("Sell", entry)
        
        -- Xóa level tracking khi bán
        local hashStr = tostring(hash)
        towerLevels[hashStr] = nil
    end
end

-- Hook FireServer
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = {...}
    local name = self.Name

    if name == "PlaceTower" then
        hookPlaceTower(args)
    elseif name == "SellTower" then
        hookSellTower(args)
    elseif name == "TowerUpgradeRequest" then
        hookUpgradeTower(args)
    elseif name == "ChangeQueryType" then
        hookChangeTarget(args)
    end

    return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = {...}
    local name = self.Name
    
    if name == "PlaceTower" then
        hookPlaceTower(args)
    end
    
    return oldInvokeServer(self, ...)
end)

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        local args = {...}
        local name = self.Name

        if name == "PlaceTower" then
            hookPlaceTower(args)
        elseif name == "SellTower" then
            hookSellTower(args)
        elseif name == "TowerUpgradeRequest" then
            hookUpgradeTower(args)
        elseif name == "ChangeQueryType" then
            hookChangeTarget(args)
        end
    end
    return oldNamecall(self, ...)
end)

print("🎯 TDX Direct JSON Record đã khởi động!")
print("📁 File output: " .. jsonFile)
print("🔧 Upgrade detection: Level-based (không cần server confirmation)")

-- Thêm lệnh để xóa macro hiện tại (optional)
local function clearMacro()
    writefile(jsonFile, "[]")
    print("🗑️ Đã xóa macro record")
end

-- Thêm vào global để có thể gọi từ bên ngoài
_G.TDXRecord = {
    clear = clearMacro,
    getFile = function() return jsonFile end,
    getEntryCount = function() 
        local data = readCurrentJSON()
        return #data 
    end,
    getTowerLevels = function()
        return towerLevels
    end
}

print("🔧 Lệnh có sẵn: _G.TDXRecord.clear() để xóa macro")
print("🔧 Debug: _G.TDXRecord.getTowerLevels() để xem level tracking")