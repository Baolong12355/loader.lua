-- Tower Defense Macro Recorder (Ultimate Robust Version)
local function SafeWaitForChild(parent, childName, timeout)
    timeout = timeout or 5
    local startTime = os.time()
    local child
    
    while os.time() - startTime < timeout do
        child = parent:FindFirstChild(childName)
        if child then return child end
        wait(0.1)
    end
    
    warn("Không tìm thấy "..childName.." sau "..timeout.." giây")
    return nil
end

local function Initialize()
    -- Khởi tạo các service cần thiết
    local success, services = pcall(function()
        return {
            HttpService = game:GetService("HttpService"),
            ReplicatedStorage = game:GetService("ReplicatedStorage"),
            Players = game:GetService("Players"),
            TextChatService = game:GetService("TextChatService")
        }
    end)
    
    if not success then
        warn("Không thể khởi tạo services:", services)
        return nil
    end
    
    -- Kiểm tra người chơi
    local player = services.Players.LocalPlayer
    if not player then
        warn("Không tìm thấy LocalPlayer")
        return nil
    end
    
    -- Kiểm tra và khởi tạo cấu hình
    if not getgenv().TDX_Config then
        getgenv().TDX_Config = {
            ["Macro Name"] = "macro_"..os.time(),
            Macros = "idle"
        }
    end
    
    return {
        services = services,
        player = player,
        config = getgenv().TDX_Config
    }
end

local ctx = Initialize()
if not ctx then return end

-- Biến toàn cục
local macroData = {}
local recording = false
local connections = {}

-- Hàm tiện ích
local function SafeConnect(event, callback)
    if not event then return nil end
    local conn = event:Connect(callback)
    table.insert(connections, conn)
    return conn
end

local function SafeDisconnectAll()
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    connections = {}
end

-- Hàm lưu macro
local function SaveMacro()
    if not recording then return end
    recording = false
    
    -- Kiểmra hàm filesystem
    if not (writefile and makefolder and isfolder) then
        local fsAvailable = pcall(function()
            return writefile and makefolder and isfolder
        end)
        
        if not fsAvailable then
            warn("Hệ thống file không khả dụng")
            return
        end
    end
    
    -- Tạo thư mục
    if not pcall(function()
        if not isfolder("tdx") then makefolder("tdx") end
        if not isfolder("tdx/macros") then makefolder("tdx/macros") end
    end) then
        warn("Không thể tạo thư mục lưu macro")
        return
    end
    
    -- Lưu file
    local fileName = ctx.config["Macro Name"]:gsub("%.json$", "")..".json"
    local macroPath = "tdx/macros/"..fileName
    
    local jsonSuccess, jsonData = pcall(function()
        return ctx.services.HttpService:JSONEncode(macroData)
    end)
    
    if not jsonSuccess then
        warn("Lỗi khi chuyển đổi JSON:", jsonData)
        return
    end
    
    local writeSuccess, writeError = pcall(function()
        writefile(macroPath, jsonData)
    end)
    
    if writeSuccess then
        print("💾 Đã lưu macro thành công:", macroPath)
        print("📊 Tổng hành động:", #macroData)
    else
        warn("Lỗi khi lưu file:", writeError)
    end
end

-- Hàm ghi lại hành động
local function RecordAction(actionType, data)
    if not recording then return end
    
    local action = {
        type = actionType,
        time = os.time(),
        cash = ctx.player.leaderstats.Cash.Value
    }
    
    for k, v in pairs(data) do
        action[k] = v
    end
    
    table.insert(macroData, action)
    print("📝 Đã ghi:", actionType)
end

-- Hàm bắt đầu ghi
local function StartRecording()
    if recording then return end
    
    macroData = {}
    recording = true
    SafeDisconnectAll()
    
    print("🔴 Bắt đầu ghi macro...")
    print("🔧 Tên macro:", ctx.config["Macro Name"])
    print("🛑 Gõ 'stop' trong chat để dừng")
    
    -- Kiểm tra Remotes
    local remotes = SafeWaitForChild(ctx.services.ReplicatedStorage, "Remotes", 5)
    if not remotes then return end
    
    -- Kết nối sự kiện
    SafeConnect(SafeWaitForChild(remotes, "PlaceTower"), function(time, towerType, position)
        RecordAction("place", {
            towerType = towerType,
            position = {X = position.X, Y = position.Y, Z = position.Z},
            rotation = 0
        })
    end)
    
    SafeConnect(SafeWaitForChild(remotes, "TowerUpgradeRequest"), function(hash, path)
        RecordAction("upgrade", {
            towerHash = tostring(hash),
            path = path
        })
    end)
    
    SafeConnect(SafeWaitForChild(remotes, "ChangeQueryType"), function(hash, queryType)
        RecordAction("change_target", {
            towerHash = tostring(hash),
            queryType = queryType
        })
    end)
    
    SafeConnect(SafeWaitForChild(remotes, "SellTower"), function(hash)
        RecordAction("sell", {
            towerHash = tostring(hash)
        })
    end)
    
    -- Kết nối sự kiện chat
    if ctx.services.TextChatService then
        SafeConnect(ctx.services.TextChatService.OnIncomingMessage, function(message)
            if message.TextSource and message.TextSource.UserId == ctx.player.UserId then
                if message.Text:lower() == "stop" then
                    SaveMacro()
                end
            end
        end)
    end
    
    -- Kết nối sự kiện thoát game
    SafeConnect(ctx.services.Players.PlayerRemoving, function(leavingPlayer)
        if leavingPlayer == ctx.player then
            SaveMacro()
        end
    end)
end

-- Hàm dừng ghi
local function StopRecording()
    if not recording then return end
    SaveMacro()
    SafeDisconnectAll()
end

-- Gán hàm toàn cục
getgenv().StartMacroRecording = StartRecording
getgenv().StopMacroRecording = StopRecording

-- Tự động bắt đầu nếu ở chế độ record
if ctx.config.Macros == "record" then
    local success, err = pcall(StartRecording)
    if not success then
        warn("Không thể bắt đầu ghi macro:", err)
    end
else
    print("✅ Macro Recorder sẵn sàng")
    print("💡 Sử dụng StartMacroRecording() để bắt đầu")
end
