-- TDX Recorder - Tương thích mọi executor & loadstring
-- Sử dụng: loadstring(game:HttpGet("your_url"))()

local success, ReplicatedStorage = pcall(game.GetService, game, "ReplicatedStorage")
if not success then warn("❌ Không thể truy cập ReplicatedStorage") return end

local success, Players = pcall(game.GetService, game, "Players")
if not success then warn("❌ Không thể truy cập Players") return end

local success, HttpService = pcall(game.GetService, game, "HttpService")
if not success then warn("❌ Không thể truy cập HttpService") return end

local player = Players.LocalPlayer
if not player then warn("❌ LocalPlayer không tồn tại") return end

local PlayerScripts = player:WaitForChild("PlayerScripts", 10)
if not PlayerScripts then warn("❌ PlayerScripts không tồn tại") return end

-- Kiểm tra môi trường executor
local EXECUTOR_SUPPORT = {
    writefile = writefile ~= nil,
    readfile = readfile ~= nil,
    isfile = isfile ~= nil,
    makefolder = makefolder ~= nil,
    hookfunction = hookfunction ~= nil,
    hookmetamethod = hookmetamethod ~= nil,
    checkcaller = checkcaller ~= nil
}

print("🔍 Kiểm tra executor support:")
for func, supported in pairs(EXECUTOR_SUPPORT) do
    print(string.format("  %s: %s", func, supported and "✅" or "❌"))
end

-- Cấu hình
local outJson = "tdx/macros/recorder_output.json"
local recordedActions = {}
local hash2pos = {}
local pendingQueue = {}
local timeout = 0.5
local lastKnownLevels = {}
local lastUpgradeTime = {}
local towerCostCache = {}

-- Lấy TowerClass an toàn
local TowerClass = nil
pcall(function()
    local client = PlayerScripts:FindFirstChild("Client")
    if client then
        local gameClass = client:FindFirstChild("GameClass")
        if gameClass then
            local towerModule = gameClass:FindFirstChild("TowerClass")
            if towerModule then
                TowerClass = require(towerModule)
                print("✅ TowerClass loaded")
            end
        end
    end
end)

-- Tạo thư mục an toàn
if EXECUTOR_SUPPORT.makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
    print("📁 Folders created")
end

--==============================================================================
--=                     HÀM CỐT LÕI - AN TOÀN                                 =
--==============================================================================

local function safeWriteFile(path, content)
    if EXECUTOR_SUPPORT.writefile then
        local success, err = pcall(writefile, path, content)
        if not success then
            warn("❌ Lỗi ghi file: " .. tostring(err))
        end
        return success
    else
        warn("❌ writefile không được hỗ trợ")
        return false
    end
end

local function safeReadFile(path)
    if EXECUTOR_SUPPORT.isfile and EXECUTOR_SUPPORT.readfile then
        if isfile(path) then
            local success, content = pcall(readfile, path)
            if success then
                return content
            else
                warn("❌ Lỗi đọc file: " .. tostring(content))
            end
        end
    end
    return ""
end

-- Lấy cost tower
local function GetTowerPlaceCostByName(name)
    if towerCostCache[name] then return towerCostCache[name] end
    
    local success, playerGui = pcall(function()
        return player:FindFirstChildOfClass("PlayerGui")
    end)
    
    if success and playerGui then
        local interface = playerGui:FindFirstChild("Interface")
        if interface then
            local bottomBar = interface:FindFirstChild("BottomBar")
            if bottomBar then
                local towersBar = bottomBar:FindFirstChild("TowersBar")
                if towersBar then
                    local towerButton = towersBar:FindFirstChild(name)
                    if towerButton then
                        local costFrame = towerButton:FindFirstChild("CostFrame")
                        if costFrame then
                            local costText = costFrame:FindFirstChild("CostText")
                            if costText and costText.Text then
                                local cost = tonumber(string.gsub(tostring(costText.Text), "%D", "")) or 0
                                towerCostCache[name] = cost
                                return cost
                            end
                        end
                    end
                end
            end
        end
    end
    
    towerCostCache[name] = 0
    return 0
end

-- Lấy wave và time
local function getCurrentWaveAndTime()
    local success, playerGui = pcall(function()
        return player:FindFirstChildOfClass("PlayerGui")
    end)
    
    if success and playerGui then
        local interface = playerGui:FindFirstChild("Interface")
        if interface then
            local gameInfoBar = interface:FindFirstChild("GameInfoBar")
            if gameInfoBar then
                local wave = gameInfoBar:FindFirstChild("Wave")
                local timeLeft = gameInfoBar:FindFirstChild("TimeLeft")
                if wave and timeLeft then
                    local waveText = wave:FindFirstChild("WaveText")
                    local timeText = timeLeft:FindFirstChild("TimeLeftText")
                    if waveText and timeText then
                        return tostring(waveText.Text), tostring(timeText.Text)
                    end
                end
            end
        end
    end
    return nil, nil
end

local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = string.match(timeStr, "(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- Ghi JSON an toàn
local function updateJsonFile()
    if not EXECUTOR_SUPPORT.writefile then return false end
    
    local success, jsonLines = pcall(function()
        local lines = {}
        for i, entry in ipairs(recordedActions) do
            local ok, jsonStr = pcall(HttpService.JSONEncode, HttpService, entry)
            if ok then
                table.insert(lines, jsonStr .. (i < #recordedActions and "," or ""))
            end
        end
        return lines
    end)
    
    if success then
        local finalJson = "[\n" .. table.concat(jsonLines, "\n") .. "\n]"
        return safeWriteFile(outJson, finalJson)
    else
        warn("❌ Lỗi tạo JSON: " .. tostring(jsonLines))
        return false
    end
end

-- Parse macro line
local function parseMacroLine(line)
    -- Place tower
    local a1, name, x, y, z, rot = string.match(line, 'TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
    if a1 then
        local cleanName = string.gsub(name, '^%s*"(.-)"%s*$', '%1')
        return {{
            TowerPlaceCost = GetTowerPlaceCostByName(cleanName),
            TowerPlaced = cleanName,
            TowerVector = x .. ", " .. y .. ", " .. z,
            Rotation = rot,
            TowerA1 = a1
        }}
    end

    -- Upgrade tower
    local hash, path, upgradeCount = string.match(line, 'TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
    if hash then
        local pos = hash2pos[hash]
        if pos then
            local pathNum, count = tonumber(path), tonumber(upgradeCount)
            if pathNum and count and count > 0 then
                local entries = {}
                for i = 1, count do
                    table.insert(entries, {
                        UpgradeCost = 0,
                        UpgradePath = pathNum,
                        TowerUpgraded = pos.x
                    })
                end
                return entries
            end
        end
    end

    -- Target change
    local hash, targetType = string.match(line, 'TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
    if hash then
        local pos = hash2pos[hash]
        if pos then
            local currentWave, currentTime = getCurrentWaveAndTime()
            return {{
                TowerTargetChange = pos.x,
                TargetWanted = tonumber(targetType),
                TowerWave = currentWave,
                TargetChangedAt = convertTimeToNumber(currentTime)
            }}
        end
    end

    -- Sell tower
    local hash = string.match(line, 'TDX:sellTower%(([^%)]+)%)')
    if hash then
        local pos = hash2pos[hash]
        if pos then
            return {{ SellTower = pos.x }}
        end
    end

    return nil
end

-- Process action
local function processAction(commandString)
    local success, entries = pcall(parseMacroLine, commandString)
    if success and entries then
        for _, entry in ipairs(entries) do
            table.insert(recordedActions, entry)
        end
        updateJsonFile()
        return true
    end
    return false
end

--==============================================================================
--=                  REMOTE HANDLING - AN TOÀN                               =
--==============================================================================

local function setPending(typeStr, code, hash)
    table.insert(pendingQueue, {
        type = typeStr,
        code = code,
        created = tick(),
        hash = hash
    })
end

local function tryConfirm(typeStr, specificHash)
    for i = #pendingQueue, 1, -1 do
        local item = pendingQueue[i]
        if item.type == typeStr then
            if not specificHash or string.find(item.code, tostring(specificHash), 1, true) then
                if processAction(item.code) then
                    table.remove(pendingQueue, i)
                    return true
                end
            end
        end
    end
    return false
end

-- Kết nối remotes an toàn
local function connectRemotes()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then 
        warn("❌ Không tìm thấy Remotes folder")
        return false
    end

    -- Remote 1: TowerFactoryQueueUpdated
    local towerFactory = remotes:FindFirstChild("TowerFactoryQueueUpdated")
    if towerFactory then
        towerFactory.OnClientEvent:Connect(function(data)
            local d = data and data[1]
            if d then
                if d.Creation then
                    tryConfirm("Place")
                else
                    tryConfirm("Sell")
                end
            end
        end)
        print("✅ TowerFactoryQueueUpdated connected")
    else
        warn("❌ TowerFactoryQueueUpdated không tìm thấy")
    end

    -- Remote 2: TowerUpgradeQueueUpdated
    local towerUpgrade = remotes:FindFirstChild("TowerUpgradeQueueUpdated")
    if towerUpgrade then
        towerUpgrade.OnClientEvent:Connect(function(data)
            if not data or not data[1] then return end

            local towerData = data[1]
            local hash = towerData.Hash
            local newLevels = towerData.LevelReplicationData
            local currentTime = tick()

            -- Anti-duplicate
            if lastUpgradeTime[hash] and (currentTime - lastUpgradeTime[hash]) < 0.001 then 
                return 
            end
            lastUpgradeTime[hash] = currentTime

            local oldLevels = lastKnownLevels[hash]
            if oldLevels then
                -- Check path 1
                local oldLevel1, newLevel1 = oldLevels[1] or 0, newLevels[1] or 0
                if newLevel1 > oldLevel1 then
                    local code = string.format("TDX:upgradeTower(%s, 1, %d)", hash, newLevel1 - oldLevel1)
                    processAction(code)
                    -- Clean pending
                    for i = #pendingQueue, 1, -1 do
                        if pendingQueue[i].hash == hash then
                            table.remove(pendingQueue, i)
                        end
                    end
                else
                    -- Check path 2
                    local oldLevel2, newLevel2 = oldLevels[2] or 0, newLevels[2] or 0
                    if newLevel2 > oldLevel2 then
                        local code = string.format("TDX:upgradeTower(%s, 2, %d)", hash, newLevel2 - oldLevel2)
                        processAction(code)
                        -- Clean pending
                        for i = #pendingQueue, 1, -1 do
                            if pendingQueue[i].hash == hash then
                                table.remove(pendingQueue, i)
                            end
                        end
                    else
                        tryConfirm("Upgrade", hash)
                    end
                end
            else
                tryConfirm("Upgrade", hash)
            end

            lastKnownLevels[hash] = newLevels or {}
        end)
        print("✅ TowerUpgradeQueueUpdated connected")
    else
        warn("❌ TowerUpgradeQueueUpdated không tìm thấy")
    end

    -- Remote 3: TowerQueryTypeIndexChanged
    local queryType = remotes:FindFirstChild("TowerQueryTypeIndexChanged")
    if queryType then
        queryType.OnClientEvent:Connect(function(data)
            if data and data[1] then
                tryConfirm("Target")
            end
        end)
        print("✅ TowerQueryTypeIndexChanged connected")
    else
        warn("❌ TowerQueryTypeIndexChanged không tìm thấy")
    end

    return true
end

-- Handle remote calls
local function handleRemote(name, args)
    if name == "TowerUpgradeRequest" then
        local hash, path, count = args[1], args[2], args[3]
        if typeof(hash) == "number" and typeof(path) == "number" and typeof(count) == "number" then
            setPending("Upgrade", string.format("TDX:upgradeTower(%s, %d, %d)", hash, path, count), hash)
        end
    elseif name == "PlaceTower" then
        local a1, towerName, vec, rot = args[1], args[2], args[3], args[4]
        if typeof(vec) == "Vector3" then
            setPending("Place", string.format('TDX:placeTower(%s, "%s", Vector3.new(%s, %s, %s), %s)', 
                a1, towerName, vec.X, vec.Y, vec.Z, rot))
        end
    elseif name == "SellTower" then
        setPending("Sell", "TDX:sellTower("..tostring(args[1])..")")
    elseif name == "ChangeQueryType" then
        setPending("Target", string.format("TDX:changeQueryType(%s, %s)", args[1], args[2]))
    end
end

-- Setup hooks an toàn
local function setupHooks()
    if not (EXECUTOR_SUPPORT.hookfunction and EXECUTOR_SUPPORT.hookmetamethod and EXECUTOR_SUPPORT.checkcaller) then
        warn("❌ Executor không hỗ trợ hook functions")
        return false
    end

    local success = pcall(function()
        local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
            handleRemote(self.Name, {...})
            return oldFireServer(self, ...)
        end)

        local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
            handleRemote(self.Name, {...})
            return oldInvokeServer(self, ...)
        end)

        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            if checkcaller() then return oldNamecall(self, ...) end
            local method = getnamecallmethod()
            if method == "FireServer" or method == "InvokeServer" then
                handleRemote(self.Name, {...})
            end
            return oldNamecall(self, ...)
        end)
    end)

    if success then
        print("✅ Hooks setup thành công")
        return true
    else
        warn("❌ Lỗi setup hooks")
        return false
    end
end

--==============================================================================
--=                         VÒNG LẶP & KHỞI TẠO                               =
--==============================================================================

-- Cleanup loop
task.spawn(function()
    while task.wait(0.1) do
        local now = tick()
        for i = #pendingQueue, 1, -1 do
            if now - pendingQueue[i].created > timeout then
                table.remove(pendingQueue, i)
            end
        end
    end
end)

-- Update tower positions
task.spawn(function()
    while task.wait(0.5) do
        if TowerClass and TowerClass.GetTowers then
            local success, towers = pcall(TowerClass.GetTowers, TowerClass)
            if success then
                for hash, tower in pairs(towers) do
                    local ok, cframe = pcall(function() return tower.CFrame end)
                    if ok and typeof(cframe) == "CFrame" then
                        local pos = cframe.Position
                        hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
                    end
                end
            end
        end
    end
end)

-- Khởi tạo
local function initialize()
    print("🚀 Khởi tạo TDX Recorder...")
    
    -- Đọc dữ liệu cũ
    if EXECUTOR_SUPPORT.readfile then
        local content = safeReadFile(outJson)
        if content ~= "" then
            local success = pcall(function()
                content = string.gsub(content, "^%[%s*", "")
                content = string.gsub(content, "%s*%]$", "")
                for line in string.gmatch(content, "[^\r\n]+") do
                    line = string.gsub(line, ",$", "")
                    if string.match(line, "%S") then
                        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, line)
                        if ok and decoded and decoded.SuperFunction then
                            table.insert(recordedActions, decoded)
                        end
                    end
                end
            end)
            if success then
                print("📖 Đã load " .. #recordedActions .. " actions từ file cũ")
            end
        end
    end
    
    -- Connect remotes
    if not connectRemotes() then
        warn("❌ Không thể kết nối remotes")
        return false
    end
    
    -- Setup hooks
    if not setupHooks() then
        warn("❌ Không thể setup hooks")
        return false
    end
    
    print("✅ TDX Recorder đã khởi tạo thành công!")
    print("📁 Output file: " .. outJson)
    print("🎯 Đang theo dõi 3 remote events...")
    return true
end

-- Chạy khởi tạo
if not initialize() then
    warn("❌ Khởi tạo thất bại!")
else
    print("🎉 Script đã sẵn sàng!")
end