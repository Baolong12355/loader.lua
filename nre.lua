local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Khởi tạo file JSON output
local outJson = "tdx/macros/x.json"

-- Tạo thư mục nếu cần
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

-- Biến lưu trữ logs
local macroLogs = {}

-- Load existing logs từ file JSON (nếu có)
local function loadExistingLogs()
    if isfile and isfile(outJson) then
        local success, content = pcall(readfile, outJson)
        if success and content then
            content = content:gsub("^%[%s*", ""):gsub("%s*%]$", "")
            local logs = {}
            for line in content:gmatch("[^\r\n]+") do
                line = line:gsub(",$", "")
                if line:match("%S") then
                    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, line)
                    if ok and decoded then
                        table.insert(logs, decoded)
                    end
                end
            end
            return logs
        end
    end
    return {}
end

-- Load logs hiện có
macroLogs = loadExistingLogs()

-- Hàm lưu logs ra file JSON
local function saveLogs()
    local jsonLines = {}
    for i, entry in ipairs(macroLogs) do
        local jsonStr = HttpService:JSONEncode(entry)
        if i < #macroLogs then
            jsonStr = jsonStr .. ","
        end
        table.insert(jsonLines, jsonStr)
    end
    
    local finalJson = "[\n" .. table.concat(jsonLines, "\n") .. "\n]"
    if writefile then
        pcall(writefile, outJson, finalJson)
    end
end

-- Biến theo dõi trạng thái
local lastKnownLevels = {} -- { [towerHash] = {path1Level, path2Level} }
local lastUpgradeTime = {} -- { [towerHash] = timestamp } để phát hiện upgrade sinh đôi

-- Lấy TowerClass
local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    local success, result = pcall(require, towerModule)
    if success then
        TowerClass = result
    end
end

-- Hàm lấy vị trí tower
local function GetTowerPosition(tower)
    if not TowerClass or not tower then return nil end

    local success, cframe = pcall(function()
        return tower.CFrame
    end)
    if success and cframe and typeof(cframe) == "CFrame" then
        return cframe.Position
    end

    if tower.GetPosition and typeof(tower.GetPosition) == "function" then
        local success, position = pcall(tower.GetPosition, tower)
        if success and position and typeof(position) == "Vector3" then
            return position
        end
    end

    if tower.GetTorsoPosition and typeof(tower.GetTorsoPosition) == "function" then
        local success, torsoPosition = pcall(tower.GetTorsoPosition, tower)
        if success and torsoPosition and typeof(torsoPosition) == "Vector3" then
            return torsoPosition
        end
    end

    if tower.Character then
        local success, model = pcall(function()
            return tower.Character:GetCharacterModel()
        end)
        if success and model then
            local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
            if root then
                return root.Position
            end
        end
    end

    return nil
end

-- Hàm lấy cost của tower
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

    local wave = gameInfoBar.Wave.WaveText.Text
    local time = gameInfoBar.TimeLeft.TimeLeftText.Text
    return wave, time
end

-- Chuyển đổi time thành số
local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- Cache vị trí towers
local hash2pos = {}
task.spawn(function()
    while true do
        if TowerClass then
            for hash, tower in pairs(TowerClass.GetTowers() or {}) do
                local pos = GetTowerPosition(tower)
                if pos then
                    hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
                end
            end
        end
        task.wait()
    end
end)

-- Hàm thêm log trực tiếp
local function addLogEntry(entry)
    table.insert(macroLogs, entry)
    saveLogs()
end

-- Hàm thêm nhiều log entries
local function addLogEntries(entries)
    for _, entry in ipairs(entries) do
        table.insert(macroLogs, entry)
    end
    saveLogs()
end

-- Xử lý Place Tower
local function handlePlaceTower(a1, towerName, vec, rot)
    if typeof(a1) == "number" and typeof(towerName) == "string" and typeof(vec) == "Vector3" and typeof(rot) == "number" then
        local cost = GetTowerPlaceCostByName(towerName)
        local vector = string.format("%s, %s, %s", tostring(vec.X), tostring(vec.Y), tostring(vec.Z))
        
        addLogEntry({
            TowerPlaceCost = tonumber(cost) or 0,
            TowerPlaced = towerName,
            TowerVector = vector,
            Rotation = rot,
            TowerA1 = tostring(a1)
        })
    end
end

-- Xử lý Upgrade Tower
local function handleUpgradeTower(hash, path, count)
    local pos = hash2pos[tostring(hash)]
    local pathNum = tonumber(path)
    local upgradeCount = tonumber(count)
    
    if pos and pathNum and upgradeCount and upgradeCount > 0 then
        local entries = {}
        for _ = 1, upgradeCount do
            table.insert(entries, {
                UpgradeCost = 0,
                UpgradePath = pathNum,
                TowerUpgraded = pos.x
            })
        end
        addLogEntries(entries)
    end
end

-- Xử lý Change Target
local function handleChangeTarget(hash, targetType)
    local pos = hash2pos[tostring(hash)]
    if pos then
        local currentWave, currentTime = getCurrentWaveAndTime()
        local timeNumber = convertTimeToNumber(currentTime)

        local targetEntry = {
            TowerTargetChange = pos.x,
            TargetWanted = tonumber(targetType)
        }

        if currentWave then
            targetEntry.TargetWave = currentWave
        end

        if timeNumber then
            targetEntry.TargetChangedAt = timeNumber
        end

        addLogEntry(targetEntry)
    end
end

-- Xử lý Sell Tower
local function handleSellTower(hash)
    local pos = hash2pos[tostring(hash)]
    if pos then
        addLogEntry({
            SellTower = pos.x
        })
    end
end

-- Xử lý các events từ server
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    -- Không cần xử lý gì vì đã handle trực tiếp từ remote calls
end)

ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or not data[1] then return end

    local towerData = data[1]
    local hash = towerData.Hash
    local newLevels = towerData.LevelReplicationData
    local currentTime = tick()

    -- Kiểm tra upgrade sinh đôi
    if lastUpgradeTime[hash] and (currentTime - lastUpgradeTime[hash]) < 0.0001 then
        return
    end

    lastUpgradeTime[hash] = currentTime

    -- Tìm path được nâng cấp
    local upgradedPath = nil
    local upgradeCount = 0

    if lastKnownLevels[hash] then
        for path = 1, 2 do
            local oldLevel = lastKnownLevels[hash][path] or 0
            local newLevel = newLevels[path] or 0

            if newLevel > oldLevel then
                upgradedPath = path
                upgradeCount = newLevel - oldLevel
                break
            end
        end
    end

    -- Xử lý upgrade
    if upgradedPath and upgradeCount > 0 then
        handleUpgradeTower(hash, upgradedPath, upgradeCount)
    end

    -- Cập nhật trạng thái
    lastKnownLevels[hash] = newLevels or {}
end)

ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    -- Không cần xử lý gì vì đã handle trực tiếp từ remote calls
end)

-- Xử lý remote calls
local function handleRemote(name, args)
    if name == "TowerUpgradeRequest" then
        local hash, path, count = unpack(args)
        if typeof(hash) == "number" and typeof(path) == "number" and typeof(count) == "number" then
            if path >= 0 and path <= 2 and count > 0 and count <= 5 then
                -- Sẽ được xử lý khi TowerUpgradeQueueUpdated trigger
            end
        end
    elseif name == "PlaceTower" then
        local a1, towerName, vec, rot = unpack(args)
        handlePlaceTower(a1, towerName, vec, rot)
    elseif name == "SellTower" then
        local hash = unpack(args)
        handleSellTower(hash)
    elseif name == "ChangeQueryType" then
        local hash, targetType = unpack(args)
        handleChangeTarget(hash, targetType)
    end
end

-- Hàm hook an toàn
local function safeHookFunction(originalFunc, hookFunc)
    if hookfunction then
        return hookfunction(originalFunc, hookFunc)
    else
        warn("hookfunction không hỗ trợ trên executor này")
        return originalFunc
    end
end

local function safeHookMetamethod(object, method, hookFunc)
    if hookmetamethod then
        return hookmetamethod(object, method, hookFunc)
    else
        warn("hookmetamethod không hỗ trợ trên executor này")
        return nil
    end
end

local function safeCheckCaller()
    if checkcaller then
        return checkcaller()
    else
        return false
    end
end

-- Hook FireServer
local oldFireServer = safeHookFunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local name = self.Name
    local args = {...}
    handleRemote(name, args)
    return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = safeHookFunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local name = self.Name
    local args = {...}
    handleRemote(name, args)
    return oldInvokeServer(self, ...)
end)

-- Hook namecall metamethod
local oldNamecall
oldNamecall = safeHookMetamethod(game, "__namecall", function(self, ...)
    if safeCheckCaller() then return oldNamecall(self, ...) end

    local method = getnamecallmethod()
    if not method then return oldNamecall(self, ...) end

    local name = self.Name
    local args = {...}

    if method == "FireServer" or method == "InvokeServer" then
        handleRemote(name, args)
    end

    return oldNamecall(self, ...)
end)

print("✅ TDX Direct JSON Recorder đã khởi động!")
print("📁 Ghi trực tiếp vào file: " .. outJson)
print("🔄 Đã load " .. #macroLogs .. " logs từ file hiện có")