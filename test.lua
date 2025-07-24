local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Kiểm tra file functions an toàn
local function safeFileOperation(operation, ...)
    local success, result = pcall(operation, ...)
    if not success then
        warn("File operation failed: " .. tostring(result))
        return false
    end
    return result
end

local fileName = "record.txt"
if isfile and safeFileOperation(isfile, fileName) then 
    safeFileOperation(delfile, fileName)
end 
if writefile then
    safeFileOperation(writefile, fileName, "")
end

local pendingQueue = {}
local timeout = 2
local lastKnownLevels = {} -- { [towerHash] = {path1Level, path2Level} }
local lastUpgradeTime = {} -- { [towerHash] = timestamp } để phát hiện upgrade sinh đôi

-- Hàm phụ trợ
local function serialize(v)
    if typeof(v) == "Vector3" then
        return "Vector3.new("..v.X..","..v.Y..","..v.Z..")"
    elseif typeof(v) == "Vector2int16" then
        return "Vector2int16.new("..v.X..","..v.Y..")"
    elseif type(v) == "table" then
        local out = {}
        for k, val in pairs(v) do
            out[#out+1] = "["..tostring(k).."]="..serialize(val)
        end
        return "{"..table.concat(out, ",").."}"
    else
        return tostring(v)
    end
end

local function serializeArgs(...)
    local args = {...}
    local out = {}
    for i, v in ipairs(args) do
        out[i] = serialize(v)
    end
    return table.concat(out, ", ")
end

local function tryConfirm(typeStr, specificHash)
    for i, item in ipairs(pendingQueue) do
        if item.type == typeStr then
            -- Nếu có hash cụ thể, kiểm tra xem có khớp không
            if not specificHash or string.find(item.code, tostring(specificHash)) then
                if appendfile then
                    safeFileOperation(appendfile, fileName, item.code.."\n")
                end
                table.remove(pendingQueue, i)
                return
            end
        end
    end
end

local function setPending(typeStr, code, hash)
    table.insert(pendingQueue, {
        type = typeStr,
        code = code,
        created = tick(),
        hash = hash
    })
end

-- Xử lý TowerFactoryQueueUpdated (place/sell towers)
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data[1]
    if not d then return end

    if d.Creation then
        tryConfirm("Place")
    else
        tryConfirm("Sell")
    end
end)

-- Xử lý TowerUpgradeQueueUpdated với tính toán số lượng upgrade chính xác
ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or not data[1] then return end

    local towerData = data[1]
    local hash = towerData.Hash
    local newLevels = towerData.LevelReplicationData
    local currentTime = tick()

    -- Kiểm tra upgrade sinh đôi (cách nhau dưới 0.0001 giây)
    if lastUpgradeTime[hash] and (currentTime - lastUpgradeTime[hash]) < 0.0001 then
        -- Đây là upgrade sinh đôi, bỏ qua
        return
    end
    
    lastUpgradeTime[hash] = currentTime

    -- Tìm path nào thực sự được nâng cấp và tính số lượng
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

    -- Nếu tìm thấy path được nâng cấp
    if upgradedPath and upgradeCount > 0 then
        local code = string.format("TDX:upgradeTower(%s, %d, %d)", tostring(hash), upgradedPath, upgradeCount)
        if appendfile then
            safeFileOperation(appendfile, fileName, code.."\n")
        end

        -- Xóa các yêu cầu đang chờ cho tower này
        for i = #pendingQueue, 1, -1 do
            if pendingQueue[i].type == "Upgrade" and pendingQueue[i].hash == hash then
                table.remove(pendingQueue, i)
            end
        end
    else
        -- Nếu không tìm thấy path cụ thể, thử confirm từ pending queue
        tryConfirm("Upgrade", hash)
    end

    -- Cập nhật trạng thái mới nhất
    lastKnownLevels[hash] = newLevels or {}
end)

-- Xử lý TowerQueryTypeIndexChanged (target change)
ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data[1] then
        tryConfirm("Target")
    end
end)

-- Task cleanup pending queue
task.spawn(function()
    while true do
        task.wait(0.05)
        local now = tick()
        for i = #pendingQueue, 1, -1 do
            if now - pendingQueue[i].created > timeout then
                warn("❌ Không xác thực được: " .. pendingQueue[i].type)
                table.remove(pendingQueue, i)
            end
        end
    end
end)

-- Xử lý các remote calls
local function handleRemote(name, args)
    if name == "TowerUpgradeRequest" then
        local hash, path, count = unpack(args)
        if typeof(hash) == "number" and typeof(path) == "number" and typeof(count) == "number" then
            if path >= 0 and path <= 2 and count > 0 and count <= 5 then
                -- Chỉ tạo 1 pending entry với số lượng chính xác
                setPending("Upgrade", string.format("TDX:upgradeTower(%s, %d, %d)", tostring(hash), path, count), hash)
            end
        end
    elseif name == "PlaceTower" then
        local a1, towerName, vec, rot = unpack(args)
        if typeof(a1) == "number" and typeof(towerName) == "string" and typeof(vec) == "Vector3" and typeof(rot) == "number" then
            local code = string.format('TDX:placeTower(%d, "%s", Vector3.new(%s, %s, %s), %d)', 
                a1, towerName, tostring(vec.X), tostring(vec.Y), tostring(vec.Z), rot)
            setPending("Place", code)
        end
    elseif name == "SellTower" then
        setPending("Sell", "TDX:sellTower("..serializeArgs(unpack(args))..")")
    elseif name == "ChangeQueryType" then
        setPending("Target", "TDX:changeQueryType("..serializeArgs(unpack(args))..")")
    end
end

-- Kiểm tra và tạo function an toàn cho các executor
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

print("✅ Complete TDX Recorder hoạt động: Tất cả hành động đã được hook")
print("📁 Ghi dữ liệu vào file: " .. fileName)






local txtFile = "record.txt"
local outJson = "tdx/macros/x.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local HttpService = game:GetService("HttpService")
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Track đã convert lần đầu chưa
local initialConverted = false
local lastProcessedContent = ""

-- Safe require tower module
local function SafeRequire(module)
    local success, result = pcall(require, module)
    return success and result or nil
end

local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = SafeRequire(towerModule)
end

local function GetTowerPosition(tower)
    if not TowerClass or not tower then return nil end

    -- Thử lấy vị trí từ CFrame trước (nếu có)
    local success, cframe = pcall(function()
        return tower.CFrame
    end)
    if success and cframe and typeof(cframe) == "CFrame" then
        return cframe.Position
    end

    -- Thử sử dụng GetPosition() từ TowerClass
    if tower.GetPosition and typeof(tower.GetPosition) == "function" then
        local success, position = pcall(tower.GetPosition, tower)
        if success and position and typeof(position) == "Vector3" then
            return position
        end
    end

    -- Thử sử dụng GetTorsoPosition() từ TowerClass
    if tower.GetTorsoPosition and typeof(tower.GetTorsoPosition) == "function" then
        local success, torsoPosition = pcall(tower.GetTorsoPosition, tower)
        if success and torsoPosition and typeof(torsoPosition) == "Vector3" then
            return torsoPosition
        end
    end

    -- Fallback cuối cùng - truy cập trực tiếp vào model
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

-- Hàm lấy wave và time hiện tại từ game UI
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

-- Chuyển time format từ "MM:SS" thành số (ví dụ: "02:35" -> 235)
local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- Modify the hash2pos task to check TowerClass first
task.spawn(function()
    while true do
        if TowerClass and type(TowerClass.GetTowers) == "function" then
            for hash, tower in pairs(TowerClass.GetTowers()) do
                local pos = GetTowerPosition(tower)
                if pos then
                    hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
                end
            end
        end
        task.wait()
    end
end)

-- Hàm parse một dòng macro thành entry
local function parseMacroLine(line)
    -- parser cho placeTower với Vector3.new(...)
    local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
    if a1 and name and x and y and z and rot then
        name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
        local cost = GetTowerPlaceCostByName(name)
        local vector = string.format("%s, %s, %s", tostring(tonumber(x) or x), tostring(tonumber(y) or y), tostring(tonumber(z) or z))
        return {
            TowerPlaceCost = tonumber(cost) or 0,
            TowerPlaced = name,
            TowerVector = vector,
            Rotation = rot,
            TowerA1 = tostring(a1)
        }
    end

    -- nâng cấp - đúng format có sẵn
    local hash, path, upgradeCount = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
    if hash and path and upgradeCount then
        local pos = hash2pos[tostring(hash)]
        local pathNum = tonumber(path)
        local count = tonumber(upgradeCount)
        if pos and pathNum and count and count > 0 then
            local entries = {}
            for _ = 1, count do
                table.insert(entries, {
                    TowerUpgraded = pos.x,
                    UpgradePath = pathNum,
                    UpgradeCost = 0
                })
            end
            return entries
        end
    end

    -- đổi target - đúng format có sẵn
    local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
    if hash and targetType then
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

            return targetEntry
        end
    end

    -- bán - đúng format có sẵn
    local hash = line:match('TDX:sellTower%(([^%)]+)%)')
    if hash then
        local pos = hash2pos[tostring(hash)]
        if pos then
            return {
                SellTower = pos.x
            }
        end
    end

    return nil
end

-- Hàm thêm entry mới vào JSON file
local function appendToJsonFile(newEntries)
    if not newEntries or #newEntries == 0 then return end

    local existingLogs = {}
    
    -- Đọc file hiện tại
    if isfile(outJson) then
        local content = readfile(outJson)
        content = content:gsub("^%[%s*", ""):gsub("%s*%]$", "")
        for line in content:gmatch("[^\r\n]+") do
            line = line:gsub(",$", "")
            if line:match("%S") then
                local ok, decoded = pcall(HttpService.JSONDecode, HttpService, line)
                if ok and decoded then
                    table.insert(existingLogs, decoded)
                end
            end
        end
    end

    -- Thêm entries mới
    for _, entry in ipairs(newEntries) do
        table.insert(existingLogs, entry)
    end

    -- Ghi lại file
    local jsonLines = {}
    for i, entry in ipairs(existingLogs) do
        local jsonStr = HttpService:JSONEncode(entry)
        if i < #existingLogs then
            jsonStr = jsonStr .. ","
        end
        table.insert(jsonLines, jsonStr)
    end

    local finalJson = "[\n" .. table.concat(jsonLines, "\n") .. "\n]"
    writefile(outJson, finalJson)
end

if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

while true do
    if isfile(txtFile) then
        local currentContent = readfile(txtFile)
        
        if not initialConverted then
            -- Lần đầu tiên - convert toàn bộ
            print("Initial conversion...")
            local logs = {}

            -- Giữ SuperFunction entries
            local preservedSuper = {}
            if isfile(outJson) then
                local content = readfile(outJson)
                content = content:gsub("^%[%s*", ""):gsub("%s*%]$", "")
                for line in content:gmatch("[^\r\n]+") do
                    line = line:gsub(",$", "")
                    if line:match("%S") then
                        local ok, decoded = pcall(HttpService.JSONDecode, HttpService, line)
                        if ok and decoded and decoded.SuperFunction then
                            table.insert(preservedSuper, decoded)
                        end
                    end
                end
            end

            for line in currentContent:gmatch("[^\r\n]+") do
                local result = parseMacroLine(line)
                if result then
                    if type(result) == "table" and result[1] then
                        -- Multiple entries (như upgrade multiple times)
                        for _, entry in ipairs(result) do
                            table.insert(logs, entry)
                        end
                    else
                        -- Single entry
                        table.insert(logs, result)
                    end
                end
            end

            -- Add preserved SuperFunction entries
            for _, entry in ipairs(preservedSuper) do
                table.insert(logs, entry)
            end

            -- Ghi file hoàn chỉnh
            local jsonLines = {}
            for i, entry in ipairs(logs) do
                local jsonStr = HttpService:JSONEncode(entry)
                if i < #logs then
                    jsonStr = jsonStr .. ","
                end
                table.insert(jsonLines, jsonStr)
            end

            local finalJson = "[\n" .. table.concat(jsonLines, "\n") .. "\n]"
            writefile(outJson, finalJson)
            
            lastProcessedContent = currentContent
            initialConverted = true
            print("Initial conversion completed!")
            
        elseif currentContent ~= lastProcessedContent then
            -- Chỉ xử lý phần mới thêm
            print("Processing new lines...")
            local newLines = {}
            local currentLines = {}
            local lastLines = {}
            
            for line in currentContent:gmatch("[^\r\n]+") do
                table.insert(currentLines, line)
            end
            
            for line in lastProcessedContent:gmatch("[^\r\n]+") do
                table.insert(lastLines, line)
            end
            
            -- Lấy những dòng mới
            for i = #lastLines + 1, #currentLines do
                table.insert(newLines, currentLines[i])
            end
            
            -- Xử lý và thêm entries mới
            local newEntries = {}
            for _, line in ipairs(newLines) do
                local result = parseMacroLine(line)
                if result then
                    if type(result) == "table" and result[1] then
                        for _, entry in ipairs(result) do
                            table.insert(newEntries, entry)
                        end
                    else
                        table.insert(newEntries, result)
                    end
                end
            end
            
            appendToJsonFile(newEntries)
            lastProcessedContent = currentContent
            print("Added " .. #newEntries .. " new entries")
        end
    end
    wait(0.1)
end