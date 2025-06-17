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

-- 🪙 Hàm kiểm tra tiền tối ưu
local function waitUntilCashEnough(amount)
    while cashStat.Value < amount do
        task.wait(0.05) -- Giảm thời gian chờ
    end
end

-- 🔍 Tìm tower theo số thứ tự (nếu vẫn cần)
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

    -- Tối ưu: xử lý theo từng loại hành động
    for _, entry in ipairs(macro) do
        if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
            -- Xử lý đặt tower
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
            task.wait(0.05) -- Giảm thời gian chờ

        elseif entry.TowerIndex and entry.UpgradePath and entry.UpgradeCost then
            -- Xử lý nâng cấp tower
            waitUntilCashEnough(entry.UpgradeCost)
            local tower = findTowerByIndex(entry.TowerIndex)
            if tower then
                local before = cashStat.Value
                Remotes.TowerUpgradeRequest:FireServer(entry.TowerIndex, entry.UpgradePath, 1)
                task.wait(0.05)
            end

        elseif entry.ChangeTarget and entry.TargetType then
            -- Xử lý thay đổi mục tiêu
            Remotes.ChangeQueryType:FireServer(entry.ChangeTarget, entry.TargetType)
            task.wait(0.03)

        elseif entry.SellTower then
            -- Xử lý bán tower
            Remotes.SellTower:FireServer(entry.SellTower)
            task.wait(0.03)
        end
    end

    print("✅ Đã hoàn thành macro!")
else
    print("ℹ️ Chế độ macro hiện tại:", mode)
end
