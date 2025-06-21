-- [TDX] Macro Runner - Enhanced Version with Position Verification
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

TowerClass = LoadTowerClass()

-- Utility functions
local function GetNumericHash(inputHash)
    return tonumber(tostring(inputHash):match("%d+"))
end

local function Vector3FromString(str)
    local x, y, z = str:match("([^,]+), ([^,]+), ([^,]+)")
    return Vector3.new(tonumber(x), tonumber(y), tonumber(z))
end

local function GetTowerAtPosition(position, radiusCheck)
    radiusCheck = radiusCheck or 5
    for hash, tower in pairs(TowerClass.GetTowers()) do
        if tower.Character and tower.Character:GetTorso() then
            local towerPos = tower.Character:GetTorso().Position
            if (towerPos - position).Magnitude <= radiusCheck then
                return tower
            end
        end
    end
    return nil
end

local function GetAliveTowerAtPosition(position, radiusCheck)
    local tower = GetTowerAtPosition(position, radiusCheck)
    if tower and tower.HealthHandler and tower.HealthHandler:GetHealth() > 0 then
        return tower
    end
    return nil
end

local function WaitForCash(requiredAmount)
    while cashStat.Value < requiredAmount do
        task.wait()
    end
end

local actionDone = {}

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

    for index, entry in ipairs(macro) do  
        if actionDone[index] then continue end  

        -- ▶️ Đặt tower (có retry + delay 0.2)  
        if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then  
            DebugPrint("Thao tác đặt tower:", entry.TowerPlaced)  

            -- Check if tower already exists at this position
            local position = Vector3FromString(entry.TowerVector)
            if GetTowerAtPosition(position) then
                DebugPrint("⚠️ Đã có tower tại vị trí này, bỏ qua")
                actionDone[index] = true
                continue
            end

            WaitForCash(entry.TowerPlaceCost)

            local args = {  
                tonumber(entry.TowerA1),  
                entry.TowerPlaced,  
                position,  
                tonumber(entry.Rotation) or 0  
            }  

            local placed = false  
            for attempt = 1, 3 do  
                Remotes.PlaceTower:InvokeServer(unpack(args))  
                task.wait(0.2)  

                if GetTowerAtPosition(position) then
                    placed = true
                    break
                end
                DebugPrint("⚠️ Thử lại đặt tower (lần", attempt, ")")  
            end  

            if placed then  
                DebugPrint("✅ Đặt tower thành công:", entry.TowerPlaced)  
            else  
                DebugPrint("❌ Không thể đặt tower sau 3 lần thử")  
            end  

            actionDone[index] = true  

        -- ▶️ Nâng cấp tower (có retry + delay 0.2)  
        elseif entry.TowerUpgraded and entry.UpgradePath and entry.UpgradeCost then  
            DebugPrint("Thao tác nâng cấp tower")  

            local position
            if type(entry.TowerUpgraded) == "string" then
                position = Vector3FromString(entry.TowerUpgraded)
            else
                position = Vector3.new(entry.TowerUpgraded, 0, 0) -- Handle numeric position format
            end

            local tower = GetAliveTowerAtPosition(position)
            if not tower then
                DebugPrint("⚠️ Không tìm thấy tower sống tại vị trí, bỏ qua")
                actionDone[index] = true
                continue
            end

            WaitForCash(entry.UpgradeCost)

            local beforeLevel = tower.LevelHandler and tower.LevelHandler:GetLevelOnPath(entry.UpgradePath) or -1  
            local upgraded = false  

            for attempt = 1, 3 do  
                Remotes.TowerUpgradeRequest:FireServer(tower.Hash, entry.UpgradePath, 1)  
                task.wait(0.2)  

                -- Refresh tower reference
                tower = GetAliveTowerAtPosition(position)
                if not tower then
                    DebugPrint("⚠️ Tower biến mất sau nâng cấp")
                    break
                end

                local afterLevel = tower.LevelHandler:GetLevelOnPath(entry.UpgradePath)
                if afterLevel > beforeLevel then  
                    DebugPrint("✅ Nâng cấp thành công (path:", entry.UpgradePath, "from", beforeLevel, "to", afterLevel, ")")  
                    upgraded = true  
                    break  
                else  
                    DebugPrint("⚠️ Cấp không tăng, thử lại lần", attempt)  
                end  
            end  

            if not upgraded then  
                DebugPrint("❌ Nâng cấp thất bại sau 3 lần thử")  
            end  

            actionDone[index] = true  

        -- ▶️ Đổi target (delay 0.2)  
        elseif entry.ChangeTarget and entry.TargetType then  
            DebugPrint("Thao tác đổi target")  

            local position = Vector3FromString(entry.ChangeTarget)
            local tower = GetAliveTowerAtPosition(position)
            if not tower then
                DebugPrint("⚠️ Không tìm thấy tower sống tại vị trí, bỏ qua")
                actionDone[index] = true
                continue
            end

            Remotes.ChangeQueryType:FireServer(tower.Hash, entry.TargetType)  
            task.wait(0.2)  
            actionDone[index] = true  

        -- ▶️ Bán tower (delay 0.2)  
        elseif entry.SellTower then  
            DebugPrint("Thao tác bán tower")  

            local position = Vector3FromString(entry.SellTower)
            local tower = GetTowerAtPosition(position)
            if not tower then
                DebugPrint("⚠️ Không tìm thấy tower tại vị trí, bỏ qua")
                actionDone[index] = true
                continue
            end

            Remotes.SellTower:FireServer(tower.Hash)  
            task.wait(0.2)  
            actionDone[index] = true  
        end  
    end  

    print("✅ Đã hoàn thành macro!")
else
    print("ℹ️ Chế độ macro hiện tại:", mode)
end
