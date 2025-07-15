local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")

local teamFile = "team.json"
local teamData = {}

-- Safe require tower module
local function SafeRequire(module)
    local success, result = pcall(require, module)
    return success and result or nil
end

local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = SafeRequire(towerModule)
end

local function GetTowerPosition(tower)
    if not tower or not tower.Character then return nil end
    local model = tower.Character:GetCharacterModel()
    local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
    return root and root.Position or nil
end

-- Lưu đội hình: chỉ giữ thông tin cốt lõi
local function SaveTeam()
    local towers = TowerClass and TowerClass.GetTowers()
    if not towers then return end

    local team = {}
    for hash, tower in pairs(towers) do
        local pos = GetTowerPosition(tower)
        if pos then
            team[tostring(hash)] = {
                Name = tower.Name,
                Level = tower.LevelHandler and tower.LevelHandler:GetLevel() or 1,
                X = pos.X,
                Y = pos.Y,
                Z = pos.Z,
            }
        end
    end
    teamData = team
    writefile(teamFile, HttpService:JSONEncode(team))
    print("✅ Đã lưu đội hình vào " .. teamFile)
end

-- Chat command: rebuild()
Players.LocalPlayer.Chatted:Connect(function(msg)
    if msg:lower():find("rebuild%(%s*%)") then
        SaveTeam()
    end
end)

-- Xử lý chiết trừ khi Sell
local function RemoveTower(hash)
    if teamData[tostring(hash)] then
        teamData[tostring(hash)] = nil
        writefile(teamFile, HttpService:JSONEncode(teamData))
        print("🗑️ Đã xoá tower " .. tostring(hash) .. " khỏi đội hình")
    end
end

-- Xử lý thêm tower khi Place
local function AddTower(hash, name, pos, level)
    teamData[tostring(hash)] = {
        Name = name,
        Level = level or 1,
        X = pos.X,
        Y = pos.Y,
        Z = pos.Z,
    }
    writefile(teamFile, HttpService:JSONEncode(teamData))
    print("➕ Đã thêm tower " .. name .. " vào đội hình")
end

-- Xử lý upgrade
local function UpgradeTower(hash, newLevel)
    if teamData[tostring(hash)] then
        teamData[tostring(hash)].Level = newLevel
        writefile(teamFile, HttpService:JSONEncode(teamData))
        print("⬆️ Đã cập nhật cấp tower " .. tostring(hash) .. " lên " .. tostring(newLevel))
    end
end

-- Xác nhận từ server để cập nhật đội hình
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    for _, v in ipairs(data) do
        local info = v.Data[1]
        if typeof(info) == "table" and info.Creation then
            -- PLACE
            local hash = info[1]
            local name = info[2]
            local pos = info[4]
            AddTower(hash, name, pos, 1)
        elseif typeof(info) ~= "table" and not info.Creation then
            -- SELL
            local hash = info
            RemoveTower(hash)
        end
    end
end)

ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    for _, v in ipairs(data) do
        local info = v.Data[1]
        local hash = info[1]
        local newLevel = info[2]
        UpgradeTower(hash, newLevel)
    end
end)

print("📌 Script lưu đội hình đã bật. Dùng chat 'rebuild()' để lưu lại đội hình hiện tại.")
