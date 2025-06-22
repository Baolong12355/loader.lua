local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Load TowerClass
local TowerClass
local success, result = pcall(function()
    return require(player.PlayerScripts.Client.GameClass.TowerClass)
end)
if success then
    TowerClass = result
else
    warn("⚠️ Không thể load TowerClass.")
end

-- Cấu hình
local debugMode = true
local recording = false
local macroData = {}
local oldNamecall
local config = {
    ["Macro Name"] = "macro_" .. os.time(),
    ["Save Path"] = "tdx/macros/"
}

-- 💰 Tính giá
local function GetTowerCost(towerType, path, level)
    if not TowerClass then return 0 end
    local towerConfig
    pcall(function()
        towerConfig = TowerClass.GetTowerConfig(towerType)
    end)
    if not towerConfig then return 0 end
    if path and level then
        local upgradePath = towerConfig.UpgradePathData[path]
        if upgradePath and upgradePath[level] then
            return upgradePath[level].Cost or 0
        end
    else
        return towerConfig.UpgradePathData.BaseLevelData.Cost or 0
    end
    return 0
end

-- 📈 Lấy level path an toàn
local function GetCurrentPathLevelSafe(tower, path)
    if tower and tower.LevelHandler then
        local handler = tower.LevelHandler
        if typeof(handler.GetPathLevel) == "function" then
            return handler:GetPathLevel(path)
        elseif typeof(handler[path]) == "number" then
            return handler[path]
        end
    end
    return 0
end

-- 💾 Lưu macro
local function SaveMacro()
    if not isfolder("tdx") then makefolder("tdx") end
    if not isfolder("tdx/macros") then makefolder("tdx/macros") end
    local fileName = config["Macro Name"]:gsub("%.json$", "") .. ".json"
    local filePath = config["Save Path"] .. fileName
    writefile(filePath, HttpService:JSONEncode(macroData))
    if debugMode then print("💾 Macro saved to:", filePath) end
end

-- ⛔ Dừng ghi
local function StopRecording()
    if not recording then return end
    recording = false
    SaveMacro()
    if debugMode then print("⏹️ Đã dừng ghi macro") end
    if oldNamecall then
        hookmetamethod(game, "__namecall", oldNamecall)
    end
end

-- 🛑 Chat "stop"
local function ListenForStopCommand()
    player.Chatted:Connect(function(msg)
        if msg:lower() == "stop" and recording then
            print("🛑 Phát hiện 'stop', dừng ghi.")
            StopRecording()
        end
    end)
end

-- 🧲 Hook namecall
local function HookRemoteCalls()
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local args = {...}
        local method = getnamecallmethod()
        if not checkcaller() and recording and (method == "FireServer" or method == "InvokeServer") then
            local name = self.Name

            -- Đặt tháp
            if name == "PlaceTower" then
                local towerType = args[2]
                local vec = args[3]
                local cost = GetTowerCost(towerType)
                table.insert(macroData, {
                    Action = "Place",
                    TowerPlaced = towerType,
                    TowerPlaceCost = cost,
                    TowerVector = string.format("%.15g, %.15g, %.15g", vec.X, vec.Y, vec.Z),
                    Rotation = args[4],
                    Timestamp = os.time()
                })
                if debugMode then print("🏗️ Đặt tháp:", towerType, "| Cost:", cost) end

            -- Nâng cấp
            elseif name == "TowerUpgradeRequest" and TowerClass then
                local tower = TowerClass.GetTowers()[args[1]]
                if tower then
                    local path = args[2]
                    local towerType = tower.Type
                    local level = GetCurrentPathLevelSafe(tower, path)
                    local cost = GetTowerCost(towerType, path, level + 1)
                    table.insert(macroData, {
                        Action = "Upgrade",
                        UpgradePath = path,
                        UpgradeCost = cost,
                        TowerUpgraded = tower:GetPosition().X,
                        Timestamp = os.time()
                    })
                    if debugMode then print("⬆️ Nâng cấp:", towerType, "| Path:", path, "| Lvl:", level + 1, "| Cost:", cost) end
                end

            -- Thay đổi mục tiêu
            elseif name == "ChangeQueryType" and TowerClass then
                local tower = TowerClass.GetTowers()[args[1]]
                if tower then
                    table.insert(macroData, {
                        Action = "TargetChange",
                        TowerTargetChange = tower:GetPosition().X,
                        TargetWanted = args[2],
                        Timestamp = os.time()
                    })
                    if debugMode then print("🎯 Thay đổi mục tiêu:", args[2]) end
                end

            -- Bán tháp
            elseif name == "SellTowerRequest" and TowerClass then
                local tower = TowerClass.GetTowers()[args[1]]
                if tower then
                    table.insert(macroData, {
                        Action = "Sell",
                        TowerSold = tower:GetPosition().X,
                        Timestamp = os.time()
                    })
                    if debugMode then print("💸 Bán tháp tại:", tower:GetPosition().X) end
                end
            end
        end
        return oldNamecall(self, table.unpack(args))
    end)
end

-- ▶️ Bắt đầu
local function StartRecording()
    if recording then return end
    macroData = {}
    recording = true
    HookRemoteCalls()
    ListenForStopCommand()
    print("🔴 Bắt đầu ghi macro... Gõ 'stop' để dừng.")
end

-- 🌍 Gán global
getgenv().StartMacroRecording = StartRecording
getgenv().StopMacroRecording = StopRecording

print("✅ Macro Recorder (full version) sẵn sàng")
