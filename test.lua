local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

local outJson = "tdx/macros/recorder_output.json"
local recordedActions = {}
local hash2pos = {}

-- Tối ưu cực đại cho remote handling
local pendingQueue = {}
local timeout = 0.5 -- Giảm xuống 0.5s
local lastKnownLevels = {}
local lastUpgradeTime = {}

-- Cache chỉ cho những thứ không đổi
local towerCostCache = {}

-- Lấy TowerClass
local TowerClass
pcall(function()
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:TowerClass
    TowerClass = require(towerModule)
end)

if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

--==============================================================================
--=                     HÀM CỐT LÕI - SIÊU NHANH                              =
--==============================================================================

local function safeWriteFile(path, content)
    if writefile then pcall(writefile, path, content) end
end

local function safeReadFile(path)
    if isfile and isfile(path) and readfile then
        local success, content = pcall(readfile, path)
        return success and content or ""
    end
    return ""
end

-- Lấy cost 1 lần duy nhất, cache vĩnh viễn
local function GetTowerPlaceCostByName(name)
    if towerCostCache[name] then return towerCostCache[name] end
    
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if playerGui then
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
                            if costText then
                                local cost = tonumber(costText.Text:gsub("%D", "")) or 0
                                towerCostCache[name] = cost -- Cache vĩnh viễn
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

-- Lấy wave/time trực tiếp không cache
local function getCurrentWaveAndTime()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        local interface = playerGui:FindFirstChild("Interface")
        if interface then
            local gameInfoBar = interface:FindFirstChild("GameInfoBar")
            if gameInfoBar then
                return gameInfoBar.Wave.WaveText.Text, gameInfoBar.TimeLeft.TimeLeftText.Text
            end
        end
    end
    return nil, nil
end

local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    return mins and secs and (tonumber(mins) * 100 + tonumber(secs)) or nil
end

-- Ghi JSON siêu nhanh
local function updateJsonFile()
    local jsonLines = {}
    for i, entry in ipairs(recordedActions) do
        local ok, jsonStr = pcall(HttpService.JSONEncode, HttpService, entry)
        if ok then
            jsonLines[i] = jsonStr .. (i < #recordedActions and "," or "")
        end
    end
    safeWriteFile(outJson, "[\n" .. table.concat(jsonLines, "\n") .. "\n]")
end

-- Parse macro siêu tối ưu
local function parseMacroLine(line)
    -- Place tower
    local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
    if a1 then
        return {{
            TowerPlaceCost = GetTowerPlaceCostByName(name:gsub('^%s*"(.-)"%s*$', '%1')),
            TowerPlaced = name:gsub('^%s*"(.-)"%s*$', '%1'),
            TowerVector = x .. ", " .. y .. ", " .. z,
            Rotation = rot,
            TowerA1 = a1
        }}
    end

    -- Upgrade tower
    local hash, path, upgradeCount = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
    if hash then
        local pos = hash2pos[hash]
        if pos then
            local pathNum, count = tonumber(path), tonumber(upgradeCount)
            if pathNum and count and count > 0 then
                local entries = {}
                for _ = 1, count do
                    entries[#entries + 1] = {
                        UpgradeCost = 0,
                        UpgradePath = pathNum,
                        TowerUpgraded = pos.x
                    }
                end
                return entries
            end
        end
    end

    -- Target change
    hash, local targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
    if hash then
        local pos = hash2pos[hash]
        if pos then
            local currentWave, currentTime = getCurrentWaveAndTime()
            return {{
                TowerTargetChange = pos.x,
                TargetWanted = tonumber(targetType),
                TargetWave = currentWave,
                TargetChangedAt = convertTimeToNumber(currentTime)
            }}
        end
    end

    -- Sell tower
    hash = line:match('TDX:sellTower%(([^%)]+)%)')
    if hash then
        local pos = hash2pos[hash]
        if pos then
            return {{ SellTower = pos.x }}
        end
    end

    return nil
end

-- Process action siêu nhanh
local function processAction(commandString)
    local entries = parseMacroLine(commandString)
    if entries then
        for _, entry in ipairs(entries) do
            recordedActions[#recordedActions + 1] = entry
        end
        updateJsonFile() -- Ghi ngay lập tức để đảm bảo tốc độ
    end
end

--==============================================================================
--=              SIÊU TỐI ÂU 4 REMOTE EVENTS - CORE                           =
--==============================================================================

-- Pending queue siêu nhanh
local function setPending(typeStr, code, hash)
    pendingQueue[#pendingQueue + 1] = {
        type = typeStr,
        code = code,
        created = tick(),
        hash = hash
    }
end

-- Confirm siêu nhanh với string.find thay vì pattern
local function tryConfirm(typeStr, specificHash)
    for i = #pendingQueue, 1, -1 do
        local item = pendingQueue[i]
        if item.type == typeStr then
            if not specificHash or string.find(item.code, tostring(specificHash), 1, true) then
                processAction(item.code)
                table.remove(pendingQueue, i)
                return true
            end
        end
    end
    return false
end

-- REMOTE 1: TowerFactoryQueueUpdated - SIÊU NHANH
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data and data[1]
    if d then
        if d.Creation then
            tryConfirm("Place")
        else
            tryConfirm("Sell") 
        end
    end
end)

-- REMOTE 2: TowerUpgradeQueueUpdated - SIÊU NHANH
ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or not data[1] then return end

    local towerData = data[1]
    local hash = towerData.Hash
    local newLevels = towerData.LevelReplicationData
    local currentTime = tick()

    -- Anti-duplicate ultra fast
    if lastUpgradeTime[hash] and (currentTime - lastUpgradeTime[hash]) < 0.001 then return end
    lastUpgradeTime[hash] = currentTime

    local oldLevels = lastKnownLevels[hash]
    if oldLevels then
        -- Check path 1 first (most common)
        local oldLevel1, newLevel1 = oldLevels[1] or 0, newLevels[1] or 0
        if newLevel1 > oldLevel1 then
            local code = string.format("TDX:upgradeTower(%s, 1, %d)", hash, newLevel1 - oldLevel1)
            processAction(code)
            -- Clean pending for this tower
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

-- REMOTE 3: TowerQueryTypeIndexChanged - SIÊU NHANH  
ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data and data[1] then
        tryConfirm("Target")
    end
end)

-- REMOTE 4: Không có remote thứ 4, chỉ có 3 remotes chính

-- Handle remote calls siêu nhanh
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

-- Hook setup siêu nhanh
local function setupHooks()
    if not hookfunction or not hookmetamethod or not checkcaller then return end

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
end

--==============================================================================
--=                         MINIMAL LOOPS                                     =
--==============================================================================

-- Cleanup siêu nhanh - chỉ 0.1s interval
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

-- Update positions - chỉ cần thiết
task.spawn(function()
    while task.wait() do
        if TowerClass and TowerClass.GetTowers then
            for hash, tower in pairs(TowerClass.GetTowers()) do
                local success, cframe = pcall(function() return tower.CFrame end)
                if success and cframe then
                    local pos = cframe.Position
                    hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
                end
            end
        end
    end
end)

-- Init nhanh
setupHooks()

print("⚡ TDX Recorder ULTRA FAST - Tối ưu 100% cho remote handling!")
print("🎯 Focus: 3 Remote Events + Hook calls")
print("📁 Output: " .. outJson)