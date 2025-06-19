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

-- 🗼 Tìm tower theo index
local function findTowerByIndex(index)
    for _, tower in ipairs(TowersFolder:GetChildren()) do
        if tower.Name == tostring(index) or tower.Name:match("^"..index.."%.") then
            return tower
        end
    end
end

-- 🔄 Kiểm tra và nâng cấp path với xác nhận
local function upgradeTowerWithVerification(towerIndex, upgradePath)
    local maxRetries = 3
    local retryDelay = 0
    
    for attempt = 1, maxRetries do
        -- Lấy cấp độ hiện tại trước khi nâng cấp
        local currentLevel = getCurrentPathLevel(towerIndex, upgradePath)
        if not currentLevel then
            warn("Không thể kiểm tra cấp độ path "..upgradePath.." của tower "..towerIndex)
            return false
        end
        
        -- Thực hiện nâng cấp
        Remotes.TowerUpgradeRequest:FireServer(towerIndex, upgradePath, 1)
        task.wait(retryDelay)
        
        -- Kiểm tra cấp độ sau khi nâng cấp
        local newLevel = getCurrentPathLevel(towerIndex, upgradePath)
        
        if newLevel and newLevel > currentLevel then
            -- Nâng cấp thành công
            return true
        else
            -- Nâng cấp không thành công, thử lại
            warn("Thử lại nâng cấp tower "..towerIndex.." path "..upgradePath.." (lần "..attempt..")")
            task.wait(retryDelay)
        end
    end
    
    warn("Không thể nâng cấp tower "..towerIndex.." path "..upgradePath.." sau "..maxRetries.." lần thử")
    return false
end

-- 📊 Lấy cấp độ hiện tại của path
local function getCurrentPathLevel(towerIndex, path)
    local tower = findTowerByIndex(towerIndex)
    if not tower then return nil end
    
    local success, level = pcall(function()
        return require(tower:FindFirstChildWhichIsA("ModuleScript")).LevelHandler:GetLevelOnPath(path)
    end)
    
    return success and level or nil
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

            Remotes.PlaceTower:InvokeServer(unpack(args))
            task.wait(0.2)

        elseif entry.TowerIndex and entry.UpgradePath and entry.UpgradeCost then
            -- ⬆️ Xử lý nâng cấp tower với xác nhận
            upgradeTowerWithVerification(entry.TowerIndex, entry.UpgradePath)
            task.wait(0.2)

        elseif entry.ChangeTarget and entry.TargetType then
            -- 🎯 Xử lý thay đổi mục tiêu
            Remotes.ChangeQueryType:FireServer(entry.ChangeTarget, entry.TargetType)
            task.wait(0.2)

        elseif entry.SellTower then
            -- 💰 Xử lý bán tower
            Remotes.SellTower:FireServer(entry.SellTower)
            task.wait(0.2)
        end
    end

    print("✅ Đã hoàn thành macro!")
else
    print("ℹ️ Chế độ macro hiện tại:", mode)
end
