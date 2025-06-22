-- Tower Defense Macro Recorder (Phiên bản hoàn chỉnh)
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local player = Players.LocalPlayer
local macroData = {}
local recording = false

-- Cấu hình
local config = getgenv().TDX_Config or {}
local macroName = config["Macro Name"] or "macro_"..os.time()

-- Kết nối các Remote
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlaceTowerRemote = Remotes:WaitForChild("PlaceTower")
local UpgradeRemote = Remotes:WaitForChild("TowerUpgradeRequest")
local TargetRemote = Remotes:WaitForChild("ChangeQueryType")
local SellRemote = Remotes:WaitForChild("SellTower")

-- Hàm require an toàn với thời gian chờ
local function SafeRequire(path, timeout)
    timeout = timeout or 5
    local startTime = os.clock()
    local module
    
    while os.clock() - startTime < timeout do
        local success, result = pcall(function()
            return require(path)
        end)
        
        if success then
            module = result
            break
        end
        task.wait(0.1)
    end
    
    return module
end

-- Lấy TowerClass
local TowerClass
local function LoadTowerClass()
    local clientFolder = player.PlayerScripts:FindFirstChild("Client")
    if not clientFolder then return nil end

    local gameClass = clientFolder:FindFirstChild("GameClass")
    if not gameClass then return nil end

    local towerClassModule = gameClass:FindFirstChild("TowerClass")
    if not towerClassModule then return nil end

    return SafeRequire(towerClassModule)
end

TowerClass = LoadTowerClass()

-- Hàm lấy vị trí X của tháp từ model
local function GetTowerX(tower)
    if not tower then return nil end
    
    -- Ưu tiên lấy từ Character model
    if tower.Character and tower.Character.GetTorso then
        local torso = tower.Character:GetTorso()
        if torso then return torso.Position.X end
    end
    
    -- Fallback: lấy từ phương thức GetPosition nếu có
    if tower.GetPosition then
        local pos = tower:GetPosition()
        return pos and pos.X
    end
    
    return nil
end

-- Hàm lưu macro
local function SaveMacro()
    if not recording then return end
    recording = false
    
    if not isfolder("tdx/macros") then
        makefolder("tdx")
        makefolder("tdx/macros")
    end
    
    local fileName = macroName:match("%.json$") and macroName or macroName..".json"
    local macroPath = "tdx/macros/"..fileName
    
    writefile(macroPath, HttpService:JSONEncode(macroData))
    print("💾 Đã lưu macro vào:", macroPath)
    print("Tổng số hành động:", #macroData)
end

-- Bắt đầu ghi macro
local function StartRecording()
    macroData = {}
    recording = true
    print("🔴 Bắt đầu ghi macro... (Tên:", macroName..")")
    print("📢 Gõ 'stop' trong chat để dừng")

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
        
        -- Lấy thông tin tháp từ hash
        local tower = TowerClass and TowerClass.GetTowers()[hash]
        local towerX = tower and GetTowerX(tower)
        
        if towerX then
            local entry = {
                UpgradeCost = player.leaderstats.Cash.Value,
                UpgradePath = path,
                TowerUpgraded = towerX
            }
            
            table.insert(macroData, entry)
            print("📝 Đã ghi: Nâng cấp tháp tại X = "..towerX)
        end
    end)
    
    -- Kết nối sự kiện thay đổi target
    local targetConnection = TargetRemote.OnClientEvent:Connect(function(hash, queryType)
        if not recording then return end
        
        -- Lấy thông tin tháp từ hash
        local tower = TowerClass and TowerClass.GetTowers()[hash]
        local towerX = tower and GetTowerX(tower)
        
        if towerX then
            local entry = {
                TowerTargetChange = towerX,
                TargetWanted = queryType,
                TargetChangedAt = os.time()
            }
            
            table.insert(macroData, entry)
            print("📝 Đã ghi: Thay đổi target tháp tại X = "..towerX)
        end
    end)
    
    -- Kết nối sự kiện bán tháp
    local sellConnection = SellRemote.OnClientEvent:Connect(function(hash)
        if not recording then return end
        
        -- Lấy thông tin tháp từ hash
        local tower = TowerClass and TowerClass.GetTowers()[hash]
        local towerX = tower and GetTowerX(tower)
        
        if towerX then
            local entry = {
                SellTower = towerX,
                SellTime = os.time()
            }
            
            table.insert(macroData, entry)
            print("📝 Đã ghi: Bán tháp tại X = "..towerX)
        end
    end)
    
    -- Kết nối sự kiện chat
    local chatConnection
    if TextChatService then
        chatConnection = TextChatService.OnIncomingMessage:Connect(function(message)
            if message.TextSource and message.TextSource.UserId == player.UserId then
                if string.lower(message.Text) == "stop" then
                    SaveMacro()
                end
            end
        end)
    end
    
    -- Dọn dẹp khi dừng
    getgenv().StopMacroRecording = function()
        SaveMacro()
        placeConnection:Disconnect()
        upgradeConnection:Disconnect()
        targetConnection:Disconnect()
        sellConnection:Disconnect()
        if chatConnection then chatConnection:Disconnect() end
    end
end

-- Tự động bắt đầu nếu ở chế độ record
if getgenv().TDX_Config["Macros"] == "record" then
    StartRecording()
else
    print("✅ Macro Recorder sẵn sàng (Gõ StartRecording() để bắt đầu ghi)")
endend
