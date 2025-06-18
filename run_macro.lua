local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TowersFolder = Workspace:WaitForChild("Game"):WaitForChild("Towers")

local config = getgenv().TDX_Config or {}
local mode = config["Macros"] or "run"
local macroName = config["Macro Name"] or "y"
local macroPath = "tdx/macros/" .. macroName .. ".json"

-- 🏦 Hàm chờ đủ tiền với delay tối ưu
local function waitUntilCashEnough(amount)
    while cashStat.Value < amount do
        task.wait(0.1) -- Delay kiểm tra tiền
    end
end

-- 🗼 Tìm tower theo index
local function findTowerByIndex(index)
    for _, tower in ipairs(TowersFolder:GetChildren()) do
        if tower.Name == tostring(index) or tower.Name:match("^"..index.."%.") then
            return tower
        end
    end
end

-- ▶️ CHẠY MACROS
if mode == "run" then
    if not isfile(macroPath) then
        error("❌ Không tìm thấy file macro: " .. macroPath)
    end
    
    local success, macro = pcall(function()
        return HttpService:JSONDecode(readfile(macroPath))
    end)
    
    if not success then
        error("❌ Lỗi khi đọc file macro: " .. macro)
    end

    for _, entry in ipairs(macro) do
        if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
            -- 🏗️ Xử lý đặt tower
            local x, y, z = entry.TowerVector:match("([^,]+), ([^,]+), ([^,]+)")
            local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
            local args = {
                tonumber(entry.TowerA1),
                entry.TowerPlaced,
                pos,
                tonumber(entry.Rotation) or 0
            }

            waitUntilCashEnough(entry.TowerPlaceCost)
            Remotes.PlaceTower:InvokeServer(unpack(args))
            task.wait(0.1) -- Delay sau khi đặt tower

        elseif entry.TowerIndex and entry.UpgradePath and entry.UpgradeCost then
            -- ⬆️ Xử lý nâng cấp tower (đảm bảo không miss)
            waitUntilCashEnough(entry.UpgradeCost)
            local tower = findTowerByIndex(entry.TowerIndex)
            if tower then
                local attempts = 0
                local maxAttempts = 5 -- Thử tối đa 5 lần
                local upgraded = false
                
                while not upgraded and attempts < maxAttempts do
                    local beforeCash = cashStat.Value
                    Remotes.TowerUpgradeRequest:FireServer(entry.TowerIndex, entry.UpgradePath, 1)
                    task.wait(0.1) -- Delay giữa các lần thử nâng cấp
                    
                    -- Kiểm tra xem đã nâng cấp thành công chưa
                    if cashStat.Value < beforeCash then
                        upgraded = true
                    end
                    attempts = attempts + 1
                end
            end
            task.wait(0.1) -- Delay sau khi hoàn thành nâng cấp

        elseif entry.ChangeTarget and entry.TargetType then
            -- 🎯 Xử lý thay đổi mục tiêu
            Remotes.ChangeQueryType:FireServer(entry.ChangeTarget, entry.TargetType)
            task.wait(0.1)

        elseif entry.SellTower then
            -- 💰 Xử lý bán tower
            Remotes.SellTower:FireServer(entry.SellTower)
            task.wait(0.1)
        end
    end

    print("✅ Đã hoàn thành macro!")
else
    print("ℹ️ Chế độ macro hiện tại:", mode)
end
