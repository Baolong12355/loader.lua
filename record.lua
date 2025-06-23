-- SCR Recorder Ultimate - Phiên bản hoàn chỉnh
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
    return string.format("%.15f, %.15f, %.15f", pos.X, pos.Y, pos.Z)
end

local function GetTowerXFromHash(hash)
    local tower = TowerClass:GetTower(hash)
    if not tower or not tower.Character then return nil end
    
    local model = tower.Character:GetCharacterModel()
    local root = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
    return root and tonumber(string.format("%.15f", root.Position.X))
end

local function GetTowerCostFromUI(name)
    local towersBar = PlayerGui.Interface.BottomBar.TowersBar
    for _, btn in ipairs(towersBar:GetChildren()) do
        if btn:IsA("ImageButton") and btn.Name == name then
            local costText = btn:FindFirstChild("CostFrame") and btn.CostFrame:FindFirstChild("CostText")
            if costText then
                return tonumber(costText.Text:gsub("[$,]", ""))
            end
        end
    end
    return 0
end

local function GetTimeLeft()
    local timeText = PlayerGui.Interface.GameInfoBar.TimeLeft.TimeLeftText
    if timeText then
        local m, s = timeText.Text:match("(%d+):(%d+)")
        return m and (tonumber(m) * 60 + tonumber(s)) or 0
    end
    return 0
end
-- KẾT THÚC PHẦN GIỮ NGUYÊN --

-- Hook tất cả remote cần thiết
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- 1. Hook PlaceTower (đã tối ưu A1)
local originalPlaceTower = Remotes.PlaceTower.InvokeServer
Remotes.PlaceTower.InvokeServer = function(self, ...)
    local args = {...}
    if #args >= 4 then
        table.insert(recorded, {
            _type = "PlaceTower",
            TowerPlaceCost = GetTowerCostFromUI(args[2]),
            TowerPlaced = args[2],
            TowerVector = formatPosition(args[3]),
            Rotation = args[4],
            RawA1 = args[1], -- Giữ nguyên giá trị gốc
            Timestamp = os.time()
        })
        dirty = true
    end
    return originalPlaceTower(self, ...)
end

-- 2. Hook TowerUpgradeRequest
local originalUpgradeTower = Remotes.TowerUpgradeRequest.FireServer
Remotes.TowerUpgradeRequest.FireServer = function(self, ...)
    local args = {...}
    if #args >= 2 then
        local x = GetTowerXFromHash(args[1])
        if x then
            table.insert(recorded, {
                _type = "UpgradeTower",
                UpgradeCost = TowerClass:GetTower(args[1]).LevelHandler:GetLevelUpgradeCost(args[2], 1),
                UpgradePath = args[2],
                TowerHash = "tower_"..tostring(args[1]),
                TowerX = x,
                Timestamp = os.time()
            })
            dirty = true
        end
    end
    return originalUpgradeTower(self, ...)
end

-- 3. Hook SellTower
local originalSellTower = Remotes.SellTower.FireServer
Remotes.SellTower.FireServer = function(self, ...)
    local args = {...}
    local x = GetTowerXFromHash(args[1])
    if x then
        table.insert(recorded, {
            _type = "SellTower",
            TowerX = x,
            Timestamp = os.time()
        })
        dirty = true
    end
    return originalSellTower(self, ...)
end

-- 4. Hook ChangeQueryType
local originalChangeTarget = Remotes.ChangeQueryType.FireServer
Remotes.ChangeQueryType.FireServer = function(self, ...)
    local args = {...}
    local x = GetTowerXFromHash(args[1])
    if x and #args >= 2 then
        table.insert(recorded, {
            _type = "ChangeTarget",
            TowerX = x,
            TargetWanted = args[2],
            TargetChangedAt = GetTimeLeft(),
            Timestamp = os.time()
        })
        dirty = true
    end
    return originalChangeTarget(self, ...)
end

-- Hệ thống tự động lưu
task.spawn(function()
    while true do
        task.wait(AUTO_SAVE_INTERVAL)
        if dirty then
            pcall(function()
                writefile(SAVE_PATH, HttpService:JSONEncode(recorded))
                dirty = false
                print("🔄 Đã tự động lưu recording vào", SAVE_PATH)
            end)
        end
    end
end)

-- Test remote khi khởi động
local function TestRemotes()
    for _, remoteName in ipairs({"PlaceTower", "TowerUpgradeRequest", "SellTower", "ChangeQueryType"}) do
        if Remotes:FindFirstChild(remoteName) then
            print("✅ Remote sẵn sàng:", remoteName)
        else
            warn("⚠️ Không tìm thấy remote:", remoteName)
        end
    end
end

print("====================================")
print("✅ SCR Recorder ULTIMATE ĐÃ SẴN SÀNG!")
print("📂 Đang ghi vào:", SAVE_PATH)
print("🔹 Các remote đang theo dõi:")
print("- PlaceTower (InvokeServer)")
print("- TowerUpgradeRequest (FireServer)")
print("- SellTower (FireServer)")
print("- ChangeQueryType (FireServer)")
TestRemotes()
print("====================================")

-- API đơn giản
return {
    save = function()
        pcall(function()
            writefile(SAVE_PATH, HttpService:JSONEncode(recorded))
            print("💾 Đã lưu thủ công recording vào", SAVE_PATH)
        end)
    end,
    getRecordings = function() return recorded end,
    clear = function() recorded = {} end
}
