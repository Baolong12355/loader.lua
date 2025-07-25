--[[
    Tập lệnh TDX Recorder và Converter đã được hợp nhất.
    Tác giả: Gemini (Hợp nhất và tối ưu hóa)
    Chức năng:
    - Hook các sự kiện trong game (đặt, bán, nâng cấp, đổi mục tiêu của tháp).
    - Loại bỏ việc ghi vào file .txt trung gian.
    - Chuyển đổi và ghi trực tiếp hành động đã xác thực ra file JSON.
]]

-- 1. KHỞI TẠO DỊCH VỤ VÀ BIẾN
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

-- Cấu hình
local outJson = "tdx/macros/x.json"
local timeout = 2 -- Thời gian chờ xác thực một hành động (giây)

-- Trạng thái
local allActions = {} -- Lưu trữ tất cả các hành động dưới dạng table để ghi ra JSON
local pendingQueue = {} -- { type, args, created, hash }
local lastKnownLevels = {} -- { [towerHash] = {path1Level, path2Level} }
local lastUpgradeTime = {} -- { [towerHash] = timestamp } để phát hiện upgrade sinh đôi
local hash2pos = {} -- Ánh xạ từ hash của tháp sang vị trí Vector3

-- 2. CÁC HÀM TIỆN ÍCH

-- Hàm thực thi các thao tác file một cách an toàn
local function safeFileOperation(operation, ...)
    local success, result = pcall(operation, ...)
    if not success then
        warn("Lỗi thao tác file: " .. tostring(result))
        return false
    end
    return result
end

-- Hàm require module an toàn
local function SafeRequire(module)
    local success, result = pcall(require, module)
    return success and result or nil
end

-- Lấy TowerClass từ game client
local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = SafeRequire(towerModule)
end

-- Các hàm lấy thông tin từ game
local function GetTowerPosition(tower)
    if not TowerClass or not tower then return nil end
    local success, cframe = pcall(function() return tower.CFrame end)
    if success and cframe and typeof(cframe) == "CFrame" then return cframe.Position end
    if tower.GetPosition then
        local posSuccess, position = pcall(tower.GetPosition, tower)
        if posSuccess and typeof(position) == "Vector3" then return position end
    end
    return nil
end

local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    local interface = playerGui and playerGui:FindFirstChild("Interface")
    local towersBar = interface and interface:FindFirstChild("BottomBar"):FindFirstChild("TowersBar")
    if not towersBar then return 0 end

    for _, towerButton in ipairs(towersBar:GetChildren()) do
        if towerButton.Name == name then
            local costText = towerButton:FindFirstDescendant("CostText")
            if costText then
                return tonumber(tostring(costText.Text):gsub("%D", "")) or 0
            end
        end
    end
    return 0
end

local function getCurrentWaveAndTime()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    local gameInfoBar = playerGui and playerGui:FindFirstChild("Interface"):FindFirstChild("GameInfoBar")
    if not gameInfoBar then return nil, nil end
    local wave = gameInfoBar.Wave.WaveText.Text
    local time = gameInfoBar.TimeLeft.TimeLeftText.Text
    return wave, time
end

local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    return (mins and secs) and (tonumber(mins) * 100 + tonumber(secs)) or nil
end

-- 3. XỬ LÝ VÀ GHI JSON

-- Hàm lưu toàn bộ hành động ra file JSON
local function saveAllActionsToJson()
    if not writefile then return end

    local finalLogs = {}
    
    -- Đọc và bảo toàn các "SuperFunction" đã có trong file JSON (nếu có)
    if isfile and safeFileOperation(isfile, outJson) then
        local content = safeFileOperation(readfile, outJson)
        if content then
            local success, decoded = pcall(HttpService.JSONDecode, HttpService, content)
            if success and type(decoded) == "table" then
                for _, entry in ipairs(decoded) do
                    if entry.SuperFunction then
                        table.insert(finalLogs, entry)
                    end
                end
            end
        end
    end
    
    -- Thêm các hành động mới đã được ghi lại
    for _, action in ipairs(allActions) do
        table.insert(finalLogs, action)
    end

    -- Chuyển đổi sang định dạng JSON đẹp mắt và ghi file
    local jsonString = HttpService:JSONEncode(finalLogs)
    -- Thêm định dạng cho dễ đọc
    jsonString = jsonString:gsub("},{", "},\n{"):gsub("%[", "[\n"):gsub("%]", "\n]")
    safeFileOperation(writefile, outJson, jsonString)
end

-- Hàm xử lý một hành động và thêm vào danh sách để ghi ra JSON
local function processAndAddAction(actionType, args)
    local entries = {}

    if actionType == "Place" then
        local a1, towerName, vec, rot = unpack(args)
        local cost = GetTowerPlaceCostByName(towerName)
        table.insert(entries, {
            TowerPlaceCost = tonumber(cost) or 0,
            TowerPlaced = towerName,
            TowerVector = string.format("%s, %s, %s", vec.X, vec.Y, vec.Z),
            Rotation = rot,
            TowerA1 = tostring(a1)
        })
    elseif actionType == "Upgrade" then
        local hash, path, count = unpack(args)
        local pos = hash2pos[tostring(hash)]
        if pos and count > 0 then
            for _ = 1, count do
                table.insert(entries, {
                    UpgradeCost = 0, -- Chi phí nâng cấp có thể cần logic phức tạp hơn để lấy
                    UpgradePath = path,
                    TowerUpgraded = pos.x
                })
            end
        end
    elseif actionType == "Sell" then
        local hash = unpack(args)
        local pos = hash2pos[tostring(hash)]
        if pos then
            table.insert(entries, { SellTower = pos.x })
        end
    elseif actionType == "Target" then
        local hash, targetType = unpack(args)
        local pos = hash2pos[tostring(hash)]
        if pos then
            local wave, time = getCurrentWaveAndTime()
            local timeNum = convertTimeToNumber(time)
            local entry = {
                TowerTargetChange = pos.x,
                TargetWanted = tonumber(targetType)
            }
            if wave then entry.TargetWave = wave end
            if timeNum then entry.TargetChangedAt = timeNum end
            table.insert(entries, entry)
        end
    end

    -- Thêm các entry đã xử lý vào danh sách chung và lưu lại file JSON
    if #entries > 0 then
        for _, entry in ipairs(entries) do
            table.insert(allActions, entry)
        end
        saveAllActionsToJson()
        print("✅ Đã ghi nhận hành động: " .. actionType)
    end
end

-- 4. CÁC TÁC VỤ NỀN

-- Cập nhật vị trí các tháp liên tục
task.spawn(function()
    while task.wait() do
        if TowerClass and TowerClass.GetTowers then
            for hash, tower in pairs(TowerClass.GetTowers()) do
                local pos = GetTowerPosition(tower)
                if pos then
                    hash2pos[tostring(hash)] = {x = pos.X, y = pos.Y, z = pos.Z}
                end
            end
        end
    end
end)

-- Dọn dẹp các yêu cầu đang chờ xử lý bị quá hạn
task.spawn(function()
    while task.wait(0.1) do
        local now = tick()
        for i = #pendingQueue, 1, -1 do
            if now - pendingQueue[i].created > timeout then
                warn("❌ Không xác thực được: " .. pendingQueue[i].type)
                table.remove(pendingQueue, i)
            end
        end
    end
end)


-- 5. LOGIC GHI NHẬN HÀNH ĐỘNG

-- Thêm một yêu cầu vào hàng đợi chờ xác thực
local function setPending(typeStr, args, hash)
    table.insert(pendingQueue, {
        type = typeStr,
        args = args,
        created = tick(),
        hash = hash
    })
end

-- Thử xác thực một hành động từ hàng đợi
local function tryConfirm(typeStr, specificHash)
    for i = #pendingQueue, 1, -1 do
        local item = pendingQueue[i]
        if item.type == typeStr then
            if not specificHash or tostring(item.hash) == tostring(specificHash) then
                table.remove(pendingQueue, i)
                processAndAddAction(item.type, item.args)
                return
            end
        end
    end
end

-- Xử lý các sự kiện từ server để xác thực
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or not data[1] then return end
    if data[1].Creation then
        tryConfirm("Place")
    else
        tryConfirm("Sell")
    end
end)

ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or not data[1] then return end

    local towerData = data[1]
    local hash = towerData.Hash
    local newLevels = towerData.LevelReplicationData
    local currentTime = tick()

    if lastUpgradeTime[hash] and (currentTime - lastUpgradeTime[hash]) < 0.0001 then
        return -- Bỏ qua upgrade sinh đôi
    end
    lastUpgradeTime[hash] = currentTime

    local upgradedPath, upgradeCount = nil, 0
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

    if upgradedPath and upgradeCount > 0 then
        -- Xóa các yêu cầu nâng cấp đang chờ cho tháp này
        for i = #pendingQueue, 1, -1 do
            if pendingQueue[i].type == "Upgrade" and pendingQueue[i].hash == hash then
                table.remove(pendingQueue, i)
            end
        end
        -- Xử lý trực tiếp hành động đã xác thực
        processAndAddAction("Upgrade", {hash, upgradedPath, upgradeCount})
    else
        -- Nếu không tính được, thử confirm từ hàng đợi
        tryConfirm("Upgrade", hash)
    end

    lastKnownLevels[hash] = newLevels or {}
end)

ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data and data[1] then
        tryConfirm("Target", data[1])
    end
end)

-- Hàm trung gian xử lý các remote call
local function handleRemote(name, args)
    if name == "TowerUpgradeRequest" then
        local hash, path, count = unpack(args)
        if typeof(hash) == "number" and typeof(path) == "number" and typeof(count) == "number" then
            setPending("Upgrade", {hash, path, count}, hash)
        end
    elseif name == "PlaceTower" then
        setPending("Place", args)
    elseif name == "SellTower" then
        setPending("Sell", args, args[1])
    elseif name == "ChangeQueryType" then
        setPending("Target", args, args[1])
    end
end


-- 6. HOOKING VÀO GAME

-- Các hàm hook an toàn
local function safeHookFunction(func, hook)
    return (hookfunction and hookfunction(func, hook)) or func
end
local function safeHookMetamethod(obj, method, hook)
    return (hookmetamethod and hookmetamethod(obj, method, hook)) or nil
end
local function safeCheckCaller()
    return (checkcaller and checkcaller()) or false
end

-- Hook FireServer
local oldFireServer = safeHookFunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    handleRemote(self.Name, {...})
    return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = safeHookFunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    handleRemote(self.Name, {...})
    return oldInvokeServer(self, ...)
end)

-- Hook namecall
local oldNamecall
oldNamecall = safeHookMetamethod(game, "__namecall", function(self, ...)
    if safeCheckCaller() then return oldNamecall(self, ...) end
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        handleRemote(self.Name, {...})
    end
    return oldNamecall(self, ...)
end)

-- 7. KHỞI ĐỘNG
if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

-- Xóa file JSON cũ khi script chạy để bắt đầu một bản ghi mới
if writefile then
    safeFileOperation(writefile, outJson, "[]")
end

print("✅ TDX Recorder Hợp nhất đã hoạt động!")
print("📁 Sẽ ghi dữ liệu trực tiếp vào file: " .. outJson)

