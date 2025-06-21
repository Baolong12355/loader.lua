-- Tower Defense Macro Recorder (Auto-Start Version)
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer
local macroData = {}
local recording = false

-- Kiểm tra và lấy cấu hình từ getgenv()
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "macro_"..os.time()

-- Kết nối các RemoteEvent
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlaceTowerRemote = Remotes:WaitForChild("PlaceTower")
local UpgradeRemote = Remotes:WaitForChild("TowerUpgradeRequest")
local TargetRemote = Remotes:WaitForChild("ChangeQueryType")
local SellRemote = Remotes:WaitForChild("SellTower")

-- Tải TowerClass
local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local t0 = os.clock()
    while os.clock() - t0 < timeout do
        local success, result = pcall(function()
            return require(path)
        end)
        if success then return result end
        task.wait()
    end
    return nil
end

local TowerClass = SafeRequire(player.PlayerScripts.Client.GameClass.TowerClass)
if not TowerClass then warn("Không thể tải TowerClass - Một số tính năng có thể không hoạt động") end

-- Lấy vị trí X của tháp từ hash
local function GetTowerX(hash)
    if not TowerClass then return nil end
    local tower = TowerClass.GetTowers()[hash]
    if not tower then return nil end
    
    local success, pos = pcall(function()
        local model = tower.Character:GetCharacterModel()
        local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
        return root and root.Position
    end)
    
    return success and pos and pos.X or nil
end

-- Hàm dừng ghi và lưu file
local function SaveMacro()
    if not recording then return end
    recording = false
    
    -- Đảm bảo thư mục tồn tại
    if not isfolder("tdx/macros") then
        makefolder("tdx")
        makefolder("tdx/macros")
    end
    
    -- Tạo tên file (đảm bảo có đuôi .json)
    local fileName = macroName
    if not fileName:match("%.json$") then
        fileName = fileName..".json"
    end
    local macroPath = "tdx/macros/"..fileName
    
    -- Lưu file
    writefile(macroPath, HttpService:JSONEncode(macroData))
    print("💾 Đã lưu macro vào:", macroPath)
    print("Tổng số hành động đã ghi:", #macroData)
    
    return macroPath
end

-- Bắt đầu ghi macro
local function StartRecording()
    macroData = {}
    recording = true
    print("🔴 Đã tự động bắt đầu ghi macro... (Tên macro: "..macroName..")")
    print("📢 Cách dừng ghi:")
    print("1. Gõ 'stop' trong chat")
    print("2. Thoát game")
    print("3. Gọi StopMacroRecording() từ console")
    
    -- Kết nối sự kiện đặt tháp
    local placeConnection = PlaceTowerRemote.OnClientEvent:Connect(function(time, towerType, position, rotation)
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
    
    -- Kết nối sự kiện nâng cấp tháp
    local upgradeConnection = UpgradeRemote.OnClientEvent:Connect(function(hash, path, _)
        if not recording then return end
        
        local towerX = GetTowerX(hash)
        if not towerX then return end
        
        local entry = {
            UpgradeCost = player.leaderstats.Cash.Value,
            UpgradePath = path,
            TowerUpgraded = towerX
        }
        
        table.insert(macroData, entry)
        print("📝 Đã ghi: Nâng cấp tháp")
    end)
    
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
        placeConnection:Disconnect()
        upgradeConnection:Disconnect()
        if chatConnection then chatConnection:Disconnect() end
        leavingConnection:Disconnect()
        print("⏹️ Đã dừng ghi macro theo yêu cầu thủ công")
    end
end

-- Tự động bắt đầu ghi nếu ở chế độ record
if getgenv().TDX_Config["Macros"] == "record" then
    StartRecording()
else
    print("⏩ Macro Recorder đã tải (Không tự động ghi vì không ở chế độ record)")
end
