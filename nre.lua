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

-- Biến theo dõi trạng thái từ script gốc
local pendingQueue = {}
local timeout = 2
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

-- Hàm serialize từ script gốc
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

-- Hàm từ script gốc
local function tryConfirm(typeStr, specificHash)
    for i, item in ipairs(pendingQueue) do
        if item.type == typeStr then
            if not specificHash or string.find(item.code, tostring(specificHash)) then
                -- Thay vì ghi vào file txt, ta convert trực tiếp
                local result = parseMacroLine(item.code)
                if result then
                    addLogEntries(result)
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

-- Hàm parse macro line để convert sang JSON
function parseMacroLine(line)
    local a1, name, x, y, z, rot = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*Vector3%.new%(([^,]+),%s*([^,]+),%s*([^%)]+)%)%s*,%s*([^%)]+)%)')
    if a1 and name and x and y and z and rot then
        name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
        local cost = GetTowerPlaceCostByName(name)
        local vector = string.format("%s, %s, %s", tostring(tonumber(x) or x), tostring(tonumber(y) or y), tostring(tonumber(z) or z))
        return {{
            TowerPlaceCost = tonumber(cost) or 0,
            TowerPlaced = name,
            TowerVector = vector,
            Rotation = rot,
            TowerA1 = tostring(a1)
        }}
    end

    local hash, path, upgradeCount = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),%s*([^%)]+)%)')
    if hash and path and upgradeCount then
        local pos = hash2pos[tostring(hash)]
        local pathNum = tonumber(path)
        local count = tonumber(upgradeCount)
        if pos and pathNum and count and count > 0 then
            local entries = {}
            for _ = 1, count do
                table.insert(entries, {
                    UpgradeCost = 0,
                    UpgradePath = pathNum,
                    TowerUpgraded = pos.x
                })
            end
            return entries
        end
    end

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

            return {targetEntry}
        end
    end

    local hash = line:match('TDX:sellTower%(([^%)]+)%)')
    if hash then
        local pos = hash2pos[tostring(hash)]
        if pos then
            return {{
                SellTower = pos.x
            }}
        end
    end

    return nil
end

-- Xử lý TowerFactoryQueueUpdated (place/sell towers) - GIỮ NGUYÊN LOGIC CŨ
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data[1]
    if not d then return end

    if d.Creation then
        tryConfirm("Place")
    else
        tryConfirm("Sell")
    end
end)

-- Xử lý TowerUpgradeQueueUpdated - GIỮ NGUYÊN LOGIC CŨ
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

    -- Nếu tìm thấy path được nâng cấp
    if upgradedPath and upgradeCount > 0 then
        local code = string.format("TDX:upgradeTower(%s, %d, %d)", tostring(hash), upgradedPath, upgradeCount)
        -- Convert trực tiếp thay vì ghi file
        local result = parseMacroLine(code)
        if result then
            addLogEntries(result)
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

-- Xử lý TowerQueryTypeIndexChanged - GIỮ NGUYÊN LOGIC CŨ
ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data[1] then
        tryConfirm("Target")
    end
end)

-- Task cleanup pending queue - GIỮ NGUYÊN
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

-- Xử lý các remote calls - GIỮ NGUYÊN LOGIC CŨ
local function handleRemote(name, args)
    if name == "TowerUpgradeRequest" then
        local hash, path, count = unpack(args)
        if typeof(hash) == "number" and typeof(path) == "number" and typeof(count) == "number" then
            if path >= 0 and path <= 2 and count > 0 and count <= 5 then
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

-- Hàm hook an toàn - GIỮ NGUYÊN
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

-- Hook FireServer - GIỮ NGUYÊN CÁCH GỌI LẠI SERVER
local oldFireServer = safeHookFunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local name = self.Name
    local args = {...}
    handleRemote(name, args)
    return oldFireServer(self, ...)  -- GỌI LẠI SERVER ĐỂ TRÁNH LỖI GAME
end)

-- Hook InvokeServer - GIỮ NGUYÊN CÁCH GỌI LẠI SERVER
local oldInvokeServer = safeHookFunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local name = self.Name
    local args = {...}
    handleRemote(name, args)
    return oldInvokeServer(self, ...)  -- GỌI LẠI SERVER ĐỂ TRÁNH LỖI GAME
end)

-- Hook namecall metamethod - GIỮ NGUYÊN CÁCH GỌI LẠI SERVER
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

    return oldNamecall(self, ...)  -- GỌI LẠI SERVER ĐỂ TRÁNH LỖI GAME
end)

print("✅ TDX Direct JSON Recorder đã khởi động!")
print("📁 Ghi trực tiếp vào file: " .. outJson)
print("🔄 Đã load " .. #macroLogs .. " logs từ file hiện có")