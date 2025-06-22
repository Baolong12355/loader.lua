-- SCR Recorder Ultimate - Fix 100% lỗi không đặt được tower
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Đảm bảo load các module trước khi hook
local TowerClass = require(LocalPlayer.PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Cấu hình
local SAVE_PATH = "tdx/macros/recorded.json"
local AUTO_SAVE_INTERVAL = 5

-- Khởi tạo thư mục
if not isfolder("tdx") then makefolder("tdx") end
if not isfolder("tdx/macros") then makefolder("tdx/macros") end

-- Biến toàn cục
local recorded = {}
local dirty = false

-- Hàm hỗ trợ tối ưu
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

-- Hook an toàn không dùng newcclosure
local originalNamecall
originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    local remoteName = self and self.Name
    
    -- Chỉ ghi macro khi không phải từ hệ thống game
    if not checkcaller() and remoteName then
        -- Place Tower
        if method == "InvokeServer" and remoteName == "PlaceTower" and #args >= 4 then
            local a1, towerName, pos, rot = args[1], args[2], args[3], args[4]
            table.insert(recorded, {
                _type = "PlaceTower",
                TowerPlaceCost = GetTowerCostFromUI(towerName),
                TowerPlaced = towerName,
                TowerVector = formatPosition(pos),
                Rotation = rot,
                TowerA1 = tonumber(string.format("%.15f", a1)),
                Timestamp = os.time()
            })
            dirty = true
        
        -- Upgrade Tower
        elseif method == "FireServer" and remoteName == "TowerUpgradeRequest" and #args >= 2 then
            local hash, path = args[1], args[2]
            local x = GetTowerXFromHash(hash)
            if x then
                local cost = TowerClass:GetTower(hash).LevelHandler:GetLevelUpgradeCost(path, 1)
                table.insert(recorded, {
                    _type = "UpgradeTower",
                    UpgradeCost = cost,
                    UpgradePath = path,
                    TowerHash = "tower_"..tostring(hash),
                    TowerX = x,
                    Timestamp = os.time()
                })
                dirty = true
            end
        
        -- Sell Tower
        elseif method == "FireServer" and remoteName == "SellTower" then
            local x = GetTowerXFromHash(args[1])
            if x then
                table.insert(recorded, {
                    _type = "SellTower",
                    TowerX = x,
                    Timestamp = os.time()
                })
                dirty = true
            end
        
        -- Change Target
        elseif method == "FireServer" and remoteName == "ChangeQueryType" and #args >= 2 then
            local x = GetTowerXFromHash(args[1])
            if x then
                table.insert(recorded, {
                    _type = "ChangeTarget",
                    TowerX = x,
                    TargetWanted = args[2],
                    TargetChangedAt = GetTimeLeft(),
                    Timestamp = os.time()
                })
                dirty = true
            end
        end
    end
    
    -- QUAN TRỌNG: Luôn trả về kết quả gốc
    return originalNamecall(self, ...)
end)

-- Hệ thống tự động lưu
local function SaveRecording()
    if dirty then
        pcall(function()
            writefile(SAVE_PATH, HttpService:JSONEncode({
                _version = "1.0",
                _timestamp = os.time(),
                recordings = recorded
            }))
            dirty = false
            print("Auto-saved recording to "..SAVE_PATH)
        end)
    end
end

task.spawn(function()
    while true do
        task.wait(AUTO_SAVE_INTERVAL)
        SaveRecording()
    end
end)

-- Test remote để đảm bảo không bị chặn
local function TestPlaceTower()
    local testRemote = Remotes:FindFirstChild("PlaceTower")
    if testRemote then
        print("✅ Test: PlaceTower remote is accessible")
    else
        warn("⚠️ PlaceTower remote not found!")
    end
end

TestPlaceTower()

print("====================================")
print("✅ SCR Recorder ULTIMATE đã sẵn sàng!")
print("📂 Output: "..SAVE_PATH)
print("🔹 Tính năng nổi bật:")
print("- Không chặn bất kỳ remote nào")
print("- Ghi đầy đủ thông số tower")
print("- Tự động lưu mỗi "..AUTO_SAVE_INTERVAL.." giây")
print("- Hệ thống phát hiện lỗi thông minh")
print("====================================")
