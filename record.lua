-- SCR Recorder Ultimate - Fixed InvokeServer Error
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Đảm bảo load TowerClass
local TowerClass = require(Players.LocalPlayer.PlayerScripts.Client.GameClass.TowerClass)

-- Cấu hình
local SAVE_PATH = "tdx/macros/recording.json"
local AUTO_SAVE_INTERVAL = 5

-- Khởi tạo thư mục
if not isfolder("tdx") then makefolder("tdx") end
if not isfolder("tdx/macros") then makefolder("tdx/macros") end

-- Biến toàn cục
local recorded = {}
local dirty = false

-- CÁC HÀM CỦA BẠN - GIỮ NGUYÊN --
local function formatPosition(pos)
    return string.format("%.2f, %.2f, %.2f", pos.X, pos.Y, pos.Z) -- Giảm độ chính xác để dễ đọc
end

local function GetTowerXFromHash(hash)
    local tower = TowerClass:GetTower(hash)
    if not tower or not tower.Character then return nil end
    
    local model = tower.Character:GetCharacterModel()
    local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
    return root and tonumber(string.format("%.2f", root.Position.X))
end

local function GetTowerCostFromUI(name)
    local towersBar = PlayerGui.Interface.BottomBar.TowersBar
    for _, btn in ipairs(towersBar:GetChildren()) do
        if btn:IsA("ImageButton") and btn.Name == name then
            local costText = btn:FindFirstChild("CostFrame") and btn.CostFrame:FindFirstChild("CostText")
            if costText then
                return tonumber(costText.Text:gsub("[^%d]", ""))
            end
        end
    end
    return 0
end
-- KẾT THÚC PHẦN GIỮ NGUYÊN --

-- Hệ thống hook mới đã fix lỗi
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PlaceTowerRemote = Remotes:WaitForChild("PlaceTower")

-- Fix lỗi "InvokeServer is not a valid member"
if not PlaceTowerRemote then
    error("Không tìm thấy RemoteFunction PlaceTower")
elseif PlaceTowerRemote.ClassName ~= "RemoteFunction" then
    error("PlaceTower phải là RemoteFunction nhưng tìm thấy: "..PlaceTowerRemote.ClassName)
end

-- Hook PlaceTower với xử lý args chính xác
local originalPlaceTower = PlaceTowerRemote.InvokeServer
PlaceTowerRemote.InvokeServer = function(self, ...)
    local args = {...}
    
    -- Debug in ra args nhận được
    print("[DEBUG] PlaceTower args:", HttpService:JSONEncode(args))
    
    if #args >= 4 then
        local a1, towerName, position, rotation = args[1], args[2], args[3], args[4]
        
        table.insert(recorded, {
            _type = "PlaceTower",
            TowerPlaceCost = GetTowerCostFromUI(towerName),
            TowerPlaced = towerName,
            TowerVector = formatPosition(position),
            Rotation = rotation,
            RawA1 = a1,
            Timestamp = os.time(),
            _argsDebug = args -- Lưu cả args gốc để debug
        })
        dirty = true
    end
    
    -- Gọi hàm gốc với args không thay đổi
    return originalPlaceTower(self, ...)
end

-- Hệ thống tự động lưu (giữ nguyên)
task.spawn(function()
    while true do
        task.wait(AUTO_SAVE_INTERVAL)
        if dirty then
            pcall(function()
                writefile(SAVE_PATH, HttpService:JSONEncode(recorded))
                dirty = false
                print("🔄 Đã lưu recording vào", SAVE_PATH)
            end)
        end
    end
end)

print("====================================")
print("✅ SCR Recorder ULTIMATE - ĐÃ FIX LỖI INVOKESERVER")
print("📂 Output:", SAVE_PATH)
print("🔹 Cấu trúc args PlaceTower:")
print("1. Số (A1):", "953.54... (vị trí X hoặc ID)")
print("2. Tên tower:", "Cryo Blaster")
print("3. Vị trí:", "Vector3")
print("4. Rotation:", "0")
print("====================================")
