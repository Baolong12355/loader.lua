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

local DEBUG = false
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

-- â–¶ï¸ RUN MACRO
if mode == "run" then
    if not isfile(macroPath) then
        error("âŒ KhĂ´ng tĂ¬m tháº¥y file macro: " .. macroPath)
    end

    local success, macro = pcall(function()
        return HttpService:JSONDecode(readfile(macroPath))
    end)

    if not success then
        error("âŒ Lá»—i khi Ä‘á»c file macro: " .. macro)
    end

    DebugPrint("Báº¯t Ä‘áº§u cháº¡y macro vá»›i", #macro, "thao tĂ¡c")

    for _, entry in ipairs(macro) do
        -- Äáº·t tower
        if entry.TowerPlaced and entry.TowerVector and entry.TowerPlaceCost then
            DebugPrint("Thao tĂ¡c Ä‘áº·t tower")

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

            Remotes.PlaceTower:InvokeServer(unpack(args))
            task.wait(0.2)

            -- Kiá»ƒm tra tá»“n táº¡i tower
            local found = false
            for _, tower in pairs(TowerClass.GetTowers()) do
                if tower.DisplayName == entry.TowerPlaced then
                    found = true
                    break
                end
            end
            if found then
                DebugPrint("âœ… Äáº·t tower thĂ nh cĂ´ng:", entry.TowerPlaced)
            else
                DebugPrint("â ï¸ KHĂ”NG tĂ¬m tháº¥y tower sau khi Ä‘áº·t:", entry.TowerPlaced)
            end

        -- NĂ¢ng cáº¥p tower
        elseif entry.TowerHash and entry.UpgradePath and entry.UpgradeCost then
            DebugPrint("Thao tĂ¡c nĂ¢ng cáº¥p tower")

            local numericHash = GetNumericHash(entry.TowerHash)
            if not numericHash then
                DebugPrint("Hash khĂ´ng há»£p lá»‡:", entry.TowerHash)
                continue
            end

            local tower = GetAliveTowerByHash(numericHash)
            if not tower then
                DebugPrint("KhĂ´ng cĂ³ tower cĂ²n sá»‘ng vá»›i hash", numericHash, ", bá» qua nĂ¢ng cáº¥p")
                continue
            end

            while cashStat.Value < entry.UpgradeCost do
                task.wait()
            end

            local beforeLevel = tower.LevelHandler and tower.LevelHandler:GetLevelOnPath(entry.UpgradePath) or -1

            Remotes.TowerUpgradeRequest:FireServer(numericHash, entry.UpgradePath, 1)
            task.wait(0.2)

            local after = GetAliveTowerByHash(numericHash)
            if after then
                local afterLevel = after.LevelHandler and after.LevelHandler:GetLevelOnPath(entry.UpgradePath) or -1
                if afterLevel > beforeLevel then
                    DebugPrint("âœ… ÄĂ£ nĂ¢ng cáº¥p tower hash:", numericHash, "Path:", entry.UpgradePath, "Tá»« cáº¥p", beforeLevel, "â†’", afterLevel)
                else
                    DebugPrint("â ï¸ Tower hash:", numericHash, "khĂ´ng tÄƒng cáº¥p sau nĂ¢ng")
                end
            else
                DebugPrint("â ï¸ KhĂ´ng tĂ¬m tháº¥y láº¡i tower sau nĂ¢ng cáº¥p")
            end

        -- Äá»•i target
        elseif entry.ChangeTarget and entry.TargetType then
            DebugPrint("Thao tĂ¡c Ä‘á»•i target")

            local numericHash = GetNumericHash(entry.ChangeTarget)
            local tower = GetAliveTowerByHash(numericHash)
            if not tower then
                DebugPrint("Tower cháº¿t hoáº·c khĂ´ng tá»“n táº¡i, bá» qua Ä‘á»•i target")
                continue
            end

            Remotes.ChangeQueryType:FireServer(numericHash, entry.TargetType)
            task.wait(0.2)

        -- BĂ¡n tower
        elseif entry.SellTower then
            DebugPrint("Thao tĂ¡c bĂ¡n tower")

            local numericHash = GetNumericHash(entry.SellTower)
            Remotes.SellTower:FireServer(numericHash)
            task.wait(0.2)
        end
    end

    print("âœ… ÄĂ£ hoĂ n thĂ nh macro!")
else
    print("â„¹ï¸ Cháº¿ Ä‘á»™ macro hiá»‡n táº¡i:", mode)
end
