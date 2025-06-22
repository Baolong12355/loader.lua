local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local debugMode = true
local recording = false
local macroData = {}
local oldNamecall

local config = {
    ["Macro Name"] = "macro_" .. os.time(),
    ["Save Path"] = "tdx/macros/"
}

-- 🧠 Lấy tower từ workspace theo ID
local function FindTowerById(id)
    local towers = workspace:FindFirstChild("Towers")
    if not towers then return nil end

    for _, tower in ipairs(towers:GetChildren()) do
        if tower:GetAttribute("UniqueID") == id then
            return tower
        end
    end
    return nil
end

-- 💰 Lấy giá đặt tháp từ TowerConfig
local function GetPlaceCost(towerType)
    local TowerClass
    pcall(function()
        TowerClass = require(player.PlayerScripts.Client.GameClass.TowerClass)
    end)
    if not TowerClass then return 0 end

    local towerConfig = TowerClass.GetTowerConfig(towerType)
    return towerConfig and towerConfig.UpgradePathData.BaseLevelData.Cost or 0
end

-- 💰 Lấy giá nâng cấp
local function GetUpgradeCost(towerType, path, level)
    local TowerClass
    pcall(function()
        TowerClass = require(player.PlayerScripts.Client.GameClass.TowerClass)
    end)
    if not TowerClass then return 0 end

    local towerConfig = TowerClass.GetTowerConfig(towerType)
    local upgradePath = towerConfig and towerConfig.UpgradePathData[path]
    if upgradePath and upgradePath[level] then
        return upgradePath[level].Cost or 0
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

-- Chat 'stop'
local function ListenForStopCommand()
    player.Chatted:Connect(function(msg)
        if msg:lower() == "stop" and recording then
            print("🛑 Dừng ghi macro (chat 'stop')")
            StopRecording()
        end
    end)
end

-- Hook tất cả remote
local function HookRemoteCalls()
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local args = {...}
        local method = getnamecallmethod()
        if not checkcaller() and recording and (method == "FireServer" or method == "InvokeServer") then
            local name = self.Name

            -- 📌 Ghi đặt tháp
            if name == "PlaceTower" then
                local towerType = args[2]
                local vec = args[3]
                local cost = GetPlaceCost(towerType)

                table.insert(macroData, {
                    Action = "Place",
                    TowerPlaced = towerType,
                    TowerPlaceCost = cost,
                    TowerVector = string.format("%.15g, %.15g, %.15g", vec.X, vec.Y, vec.Z),
                    Rotation = args[4],
                    Timestamp = os.time()
                })

                if debugMode then print("🏗️ Đặt tháp:", towerType, "| Cost:", cost) end

            -- ⬆️ Ghi nâng cấp
            elseif name == "TowerUpgradeRequest" then
                local tower = FindTowerById(args[1])
                if tower then
                    local path = args[2]
                    local towerType = tower:GetAttribute("TowerType") or "Unknown"
                    local level = tonumber(tower:GetAttribute("Upgrade_" .. path)) or 0
                    local cost = GetUpgradeCost(towerType, path, level + 1)

                    table.insert(macroData, {
                        Action = "Upgrade",
                        UpgradePath = path,
                        UpgradeCost = cost,
                        TowerUpgraded = tower.Position.X,
                        Timestamp = os.time()
                    })

                    if debugMode then print("⬆️ Nâng cấp:", towerType, "| Path:", path, "| Lvl:", level + 1, "| Cost:", cost) end
                end

            -- 🎯 Ghi thay đổi mục tiêu
            elseif name == "ChangeQueryType" then
                local tower = FindTowerById(args[1])
                if tower then
                    table.insert(macroData, {
                        Action = "TargetChange",
                        TowerTargetChange = tower.Position.X,
                        TargetWanted = args[2],
                        Timestamp = os.time()
                    })
                    if debugMode then print("🎯 Đổi mục tiêu:", args[2]) end
                end

            -- 💸 Ghi bán tháp
            elseif name == "SellTowerRequest" then
                local tower = FindTowerById(args[1])
                if tower then
                    table.insert(macroData, {
                        Action = "Sell",
                        TowerSold = tower.Position.X,
                        Timestamp = os.time()
                    })
                    if debugMode then print("💸 Bán tháp tại:", tower.Position.X) end
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
    print("🔴 Ghi macro bắt đầu. Chat 'stop' để dừng.")
end

-- 🌐 Toàn cục
getgenv().StartMacroRecording = StartRecording
getgenv().StopMacroRecording = StopRecording

print("✅ Macro Recorder (full version) đã sẵn sàng.")
