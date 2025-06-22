-- Tower Defense Macro Recorder (Fixed Version)
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer
local macroData = {}
local recording = false

-- Kiểm tra và lấy cấu hình từ getgenv()
if not getgenv().TDX_Config then
    getgenv().TDX_Config = {}
end
local config = getgenv().TDX_Config
local macroName = config["Macro Name"] or "macro_"..os.time()

-- Kết nối các RemoteEvent với xử lý lỗi
local function GetRemote(name)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        warn("Không tìm thấy thư mục Remotes")
        return nil
    end
    return remotes:FindFirstChild(name)
end

local PlaceTowerRemote = GetRemote("PlaceTower")
local UpgradeRemote = GetRemote("TowerUpgradeRequest")
local TargetRemote = GetRemote("ChangeQueryType")
local SellRemote = GetRemote("SellTower")

if not (PlaceTowerRemote and UpgradeRemote and TargetRemote and SellRemote) then
    warn("Không tìm thấy một hoặc nhiều RemoteEvents cần thiết")
    return
end

-- Hàm lưu file với kiểm tra thư mục
local function SaveMacro()
    if not recording then return end
    recording = false
    
    -- Đảm bảo thư mục tồn tại
    if not makefolder then
        warn("Hàm makefolder không khả dụng")
        return
    end
    
    if not writefile then
        warn("Hàm writefile không khả dụng")
        return
    end
    
    if not isfolder then
        warn("Hàm isfolder không khả dụng")
        return
    end
    
    if not isfolder("tdx/macros") then
        pcall(function()
            makefolder("tdx")
            makefolder("tdx/macros")
        end)
    end
    
    -- Tạo tên file (đảm bảo có đuôi .json)
    local fileName = macroName
    if not fileName:match("%.json$") then
        fileName = fileName..".json"
    end
    local macroPath = "tdx/macros/"..fileName
    
    -- Lưu file với xử lý lỗi
    local success, err = pcall(function()
        writefile(macroPath, HttpService:JSONEncode(macroData))
    end)
    
    if success then
        print("💾 Đã lưu macro vào:", macroPath)
        print("Tổng số hành động đã ghi:", #macroData)
    else
        warn("Lỗi khi lưu macro:", err)
    end
end

-- Bắt đầu ghi macro với xử lý lỗi
local function StartRecording()
    macroData = {}
    recording = true
    print("🔴 Đã bắt đầu ghi macro... (Tên macro: "..macroName..")")
    print("📢 Cách dừng ghi:")
    print("1. Gõ 'stop' trong chat")
    print("2. Thoát game")
    print("3. Gọi StopMacroRecording() từ console")
    
    -- Kiểm tra leaderstats trước khi sử dụng
    if not player:FindFirstChild("leaderstats") or not player.leaderstats:FindFirstChild("Cash") then
        warn("Không tìm thấy leaderstats/Cash")
        return
    end

    -- Kết nối sự kiện đặt tháp với xử lý nil
    local placeConnection
    if PlaceTowerRemote then
        placeConnection = PlaceTowerRemote.OnClientEvent:Connect(function(time, towerType, position, rotation)
            if not recording then return end
            
            local entry = {
                TowerPlaceCost = player.leaderstats.Cash.Value,
                TowerPlaced = towerType,
                TowerVector = string.format("%.15g, %.15g, %.15g", position.X, position.Y, position.Z),
                Rotation = rotation,
                TowerA1 = tostring(time)
            }
            
            table.insert(macroData, entry)
            print("📝 Đã ghi: Đặt tháp "..towerType)
        end)
    else
        warn("PlaceTowerRemote không tồn tại")
    end
    
    -- Kết nối sự kiện nâng cấp tháp
    local upgradeConnection
    if UpgradeRemote then
        upgradeConnection = UpgradeRemote.OnClientEvent:Connect(function(hash, path, _)
            if not recording then return end
            
            local entry = {
                UpgradeCost = player.leaderstats.Cash.Value,
                UpgradePath = path,
                TowerUpgraded = tostring(hash) -- Sử dụng hash trực tiếp nếu không có TowerClass
            }
            
            table.insert(macroData, entry)
            print("📝 Đã ghi: Nâng cấp tháp")
        end)
    else
        warn("UpgradeRemote không tồn tại")
    end
    
    -- Kết nối sự kiện chat
    local chatConnection
    if TextChatService then
        chatConnection = TextChatService.OnIncomingMessage:Connect(function(message)
            if not recording then return end
            if message.TextSource and message.TextSource.UserId == player.UserId then
                if string.lower(message.Text) == "stop" then
                    SaveMacro()
                    print("⏹️ Đã dừng ghi macro theo yêu cầu từ chat")
                end
            end
        end)
    end
    
    -- Kết nối sự kiện thoát game
    local leavingConnection = game:GetService("Players").PlayerRemoving:Connect(function(leavingPlayer)
        if leavingPlayer == player and recording then
            SaveMacro()
            print("⏹️ Đã dừng ghi macro do người chơi thoát game")
        end
    end)
    
    -- Lưu hàm dừng vào global
    getgenv().StopMacroRecording = function()
        SaveMacro()
        if placeConnection then placeConnection:Disconnect() end
        if upgradeConnection then upgradeConnection:Disconnect() end
        if chatConnection then chatConnection:Disconnect() end
        if leavingConnection then leavingConnection:Disconnect() end
        print("⏹️ Đã dừng ghi macro theo yêu cầu thủ công")
    end
end

-- Tự động bắt đầu ghi nếu ở chế độ record
if type(getgenv().TDX_Config["Macros"]) == "string" and getgenv().TDX_Config["Macros"] == "record" then
    local success, err = pcall(StartRecording)
    if not success then
        warn("Lỗi khi bắt đầu ghi macro:", err)
    end
else
    print("⏩ Macro Recorder đã tải (Không tự động ghi vì không ở chế độ record)")
end
