-- 📜 Trình ghi macro Tower Defense (Full)
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- 1. KHỞI TẠO REMOTES AN TOÀN
local function GetRemoteSafe(remoteName, expectedType)
    local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
    local remote = remotesFolder:FindFirstChild(remoteName)
    
    if not remote then
        warn("⚠️ Không tìm thấy remote: "..remoteName)
        return nil
    end
    
    if remote.ClassName ~= expectedType then
        warn("⚠️ Sai loại remote ("..remoteName.."): "..remote.ClassName..", mong đợi: "..expectedType)
        return nil
    end
    
    return remote
end

-- 2. LẤY TẤT CẢ REMOTES CẦN THIẾT
local remotes = {
    PlaceTower = GetRemoteSafe("PlaceTower", "RemoteFunction"),
    TowerUpgradeRequest = GetRemoteSafe("TowerUpgradeRequest", "RemoteEvent"),
    SellTower = GetRemoteSafe("SellTower", "RemoteEvent"),
    ChangeQueryType = GetRemoteSafe("ChangeQueryType", "RemoteEvent")
}

-- 3. KIỂM TRA REMOTES
for name, remote in pairs(remotes) do
    if not remote then
        error("❌ Không thể khởi tạo remote: "..name)
    end
end

-- 4. LẤY TOWERCLASS
local TowerClass
local success, err = pcall(function()
    TowerClass = require(LocalPlayer.PlayerScripts.Client.GameClass.TowerClass)
end)
if not success then
    error("❌ Không thể tải TowerClass: "..tostring(err))
end

-- 5. CẤU HÌNH LƯU TRỮ
local recorded = {}
local SAVE_PATH = "tdx/macros/recorded.json"

-- Tạo thư mục nếu chưa có
if not isfolder("tdx/macros") then
    makefolder("tdx/macros")
end

-- 6. HÀM LƯU DỮ LIỆU
local function SaveRecordedData()
    writefile(SAVE_PATH, HttpService:JSONEncode(recorded))
end

-- 7. HÀM LẤY VỊ TRÍ TOWER (X COORDINATE)
local function GetTowerXPosition(hash)
    local success, xPos = pcall(function()
        local tower = TowerClass:GetTower(hash)
        if not tower then return nil end
        
        -- Ưu tiên lấy từ model
        if tower.Character then
            local model = tower.Character:GetCharacterModel()
            local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
            if root then return tonumber(string.format("%.15f", root.Position.X)) end
        end
        
        -- Phương án dự phòng
        if tower.GetPosition then
            local pos = tower:GetPosition()
            return tonumber(string.format("%.15f", pos.X))
        end
        
        return nil
    end)
    
    return success and xPos or nil
end

-- 8. HỆ THỐNG HOOK REMOTES
-- Hook PlaceTower
local originalPlace = remotes.PlaceTower.InvokeServer
remotes.PlaceTower.InvokeServer = newcclosure(function(self, a1, towerName, pos, rot, ...)
    local record = {
        TowerPlaceCost = "N/A", -- Có thể thêm cách lấy giá sau
        TowerPlaced = towerName,
        TowerVector = string.format("%.15f, %.15f, %.15f", pos.X, pos.Y, pos.Z),
        Rotation = rot,
        TowerA1 = a1,
        _type = "PlaceTower",
        _time = os.time()
    }
    table.insert(recorded, record)
    SaveRecordedData()
    return originalPlace(self, a1, towerName, pos, rot, ...)
end)

-- Hook TowerUpgradeRequest
local originalUpgrade = remotes.TowerUpgradeRequest.FireServer
remotes.TowerUpgradeRequest.FireServer = newcclosure(function(self, hash, path, ...)
    local xPos = GetTowerXPosition(hash)
    if xPos then
        local record = {
            UpgradeCost = "N/A", -- Có thể thêm cách lấy giá sau
            TowerUpgraded = xPos,
            UpgradePath = path,
            _type = "Upgrade",
            _time = os.time()
        }
        table.insert(recorded, record)
        SaveRecordedData()
    end
    return originalUpgrade(self, hash, path, ...)
end)

-- Hook SellTower (ĐÃ THÊM)
local originalSell = remotes.SellTower.FireServer
remotes.SellTower.FireServer = newcclosure(function(self, hash, ...)
    local xPos = GetTowerXPosition(hash)
    if xPos then
        local record = {
            SellTower = xPos,
            _type = "Sell",
            _time = os.time()
        }
        table.insert(recorded, record)
        SaveRecordedData()
    end
    return originalSell(self, hash, ...)
end)

-- Hook ChangeQueryType (ĐÃ THÊM)
local originalTarget = remotes.ChangeQueryType.FireServer
remotes.ChangeQueryType.FireServer = newcclosure(function(self, hash, target, ...)
    local xPos = GetTowerXPosition(hash)
    if xPos then
        local record = {
            TowerTargetChange = xPos,
            TargetWanted = target,
            _type = "ChangeTarget",
            _time = os.time()
        }
        table.insert(recorded, record)
        SaveRecordedData()
    end
    return originalTarget(self, hash, target, ...)
end)

-- 9. KHỞI ĐỘNG
print("✅ Trình ghi macro đã sẵn sàng!")
print("📌 Đang ghi vào: "..SAVE_PATH)
print("📝 Các tính năng đã bao gồm:")
print("- PlaceTower")
print("- TowerUpgrade")
print("- SellTower (ĐÃ THÊM)")
print("- ChangeTarget (ĐÃ THÊM)")
