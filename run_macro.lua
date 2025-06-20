local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local cashStat = player:WaitForChild("leaderstats"):WaitForChild("Cash")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local config = getgenv().TDX_Config or {}
local mode = config["Macros"] or "run"
local macroName = config["Macro Name"] or "y"
local macroPath = "tdx/macros/" .. macroName .. ".json"

local DEBUG = true
local function DebugPrint(...)
    if DEBUG then
        print("[DEBUG]", ...)
    end
end

-- Load TowerClass
local TowerClass
local function LoadTowerClass()
    local PlayerScripts = player:WaitForChild("PlayerScripts")
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    return require(towerModule)
end

local function GetNumericHash(inputHash)
    return tonumber(tostring(inputHash):match("%d+"))
end

local function GetAliveTowerByHash(numericHash)
    local towers = TowerClass.GetTowers()
    for hash, tower in pairs(towers) do
        if GetNumericHash(hash) == numericHash and tower.HealthHandler then
            if tower.HealthHandler:GetHealth() > 0 then
                return tower
            end
        end
    end
    return nil
end

TowerClass = LoadTowerClass()

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

    DebugPrint("Bắt đầu chạy macro với", #macro, "thao tác")

    for _, entry in ipairs(macro) do

        -- ▶️ Đặt tower (có retry + delay 0.2)
        if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
            DebugPrint("Thao tác đặt tower")

            while cashStat.Value < entry.TowerPlaceCost do
                task.wait()
            end

            local x, y, z = entry.TowerVector:match("([^,]+), ([^,]+), ([^,]+)")
            local pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z))
            local args = {
                tonumber(entry.TowerA1),
                entry.TowerPlaced,
                pos,
                tonumber(entry.Rotation) or 0
            }

            local placed = false
            for attempt = 1, 3 do
                Remotes.PlaceTower:InvokeServer(unpack(args))
                task.wait(0.2)

                for _, tower in pairs(TowerClass.GetTowers()) do
                    if tower.DisplayName == entry.TowerPlaced then
                        placed = true
                        break
                    end
                end

                if placed then break end
                DebugPrint("⚠️ Thử lại đặt tower (lần", attempt + 1, ")")
            end

            if placed then
                DebugPrint("✅ Đặt tower thành công:", entry.TowerPlaced)
            else
                DebugPrint("❌ Không thể đặt tower sau 3 lần thử:", entry.TowerPlaced)
            end

        -- ▶️ Nâng cấp tower (có retry + delay 0.2)
        elseif entry.TowerHash and entry.UpgradePath and entry.UpgradeCost then
            DebugPrint("Thao tác nâng cấp tower")

            local numericHash = GetNumericHash(entry.TowerHash)
            if not numericHash then
                DebugPrint("Hash không hợp lệ:", entry.TowerHash)
                continue
            end

            local function getTower()
                return GetAliveTowerByHash(numericHash)
            end

            local tower = getTower()
            if not tower then
                DebugPrint("Không có tower còn sống với hash", numericHash, ", bỏ qua nâng cấp")
                continue
            end

            while cashStat.Value < entry.UpgradeCost do
                task.wait()
            end

            local beforeLevel = tower.LevelHandler and tower.LevelHandler:GetLevelOnPath(entry.UpgradePath) or -1
            local upgraded = false

            for attempt = 1, 3 do
                Remotes.TowerUpgradeRequest:FireServer(numericHash, entry.UpgradePath, 1)
                task.wait(0.2)

                local after = getTower()
                if after then
                    local afterLevel = after.LevelHandler and after.LevelHandler:GetLevelOnPath(entry.UpgradePath) or -1
                    if afterLevel > beforeLevel then
                        DebugPrint("✅ Nâng cấp thành công (hash:", numericHash, ", path:", entry.UpgradePath, ")")
                        upgraded = true
                        break
                    else
                        DebugPrint("⚠️ Cấp không tăng, thử lại lần", attempt + 1)
                    end
                else
                    DebugPrint("⚠️ Tower biến mất sau nâng, thử lại lần", attempt + 1)
                end
            end

            if not upgraded then
                DebugPrint("❌ Nâng cấp thất bại sau 3 lần thử")
            end

        -- ▶️ Đổi target (delay 0.2)
        elseif entry.ChangeTarget and entry.TargetType then
            DebugPrint("Thao tác đổi target")

            local numericHash = GetNumericHash(entry.ChangeTarget)
            local tower = GetAliveTowerByHash(numericHash)
            if not tower then
                DebugPrint("Tower chết hoặc không tồn tại, bỏ qua target")
                continue
            end

            Remotes.ChangeQueryType:FireServer(numericHash, entry.TargetType)
            task.wait(0.2)

        -- ▶️ Bán tower (delay 0.2)
        elseif entry.SellTower then
            DebugPrint("Thao tác bán tower")

            local numericHash = GetNumericHash(entry.SellTower)
            Remotes.SellTower:FireServer(numericHash)
            task.wait(0.2)
        end
    end

    print("✅ Đã hoàn thành macro!")
else
    print("ℹ️ Chế độ macro hiện tại:", mode)
end
