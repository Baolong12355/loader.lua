-- ✅ TDX Loader - Tải chức năng tuần tự
local config = getgenv().TDX_Config or {}

local function tryRun(name, enabled, func)
    if enabled then
        print("⏳ Đang khởi chạy:", name)
        local ok, result = pcall(func)
        if ok then
            print("✅ Thành công:", name)
        else
            warn("❌ Thất bại:", name, result)
        end
    else
        print("⏭️ Bỏ qua:", name)
    end
end

-- 🧩 Link RAW cho các module từ repo
local base = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/"
local links = {
    ["x1.5 Speed"]      = base .. "speed.lua",
    ["Auto Skill"]      = base .. "auto_skill.lua",
    ["Run Macro"]       = base .. "run_macro.lua",
    ["Join Map"]        = base .. "auto_join.lua",
    ["Auto Difficulty"] = base .. "difficulty.lua"
}

-- 🛠️ Các chức năng tích hợp
local function setupAutoTeleport()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local Players = game:GetService("Players")

    local player = Players.LocalPlayer
    if not player then return end

    local playerGui = player:WaitForChild("PlayerGui")
    local interface = playerGui and playerGui:WaitForChild("Interface")
    local gameOverScreen = interface and interface:WaitForChild("GameOverScreen")

    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local teleportRemote = remotes and remotes:FindFirstChild("RequestTeleportToLobby")

    if not teleportRemote or not (teleportRemote:IsA("RemoteEvent") or teleportRemote:IsA("RemoteFunction")) then
        warn("❌ Không tìm thấy RemoteEvent/Function hợp lệ")
        return
    end

    local function tryTeleport()
        local maxAttempts = 5
        for attempt = 1, maxAttempts do
            local success, response = pcall(function()
                if teleportRemote:IsA("RemoteEvent") then
                    teleportRemote:FireServer()
                else
                    return teleportRemote:InvokeServer()
                end
                return true
            end)
            
            if success then
                print("✅ Tự động về lobby thành công")
                return true
            else
                warn(`❌ Lỗi lần {attempt}:`, response)
                task.wait(1)
            end
        end
        return false
    end

    if gameOverScreen then
        if gameOverScreen.Visible then
            tryTeleport()
        end
        gameOverScreen:GetPropertyChangedSignal("Visible"):Connect(function()
            if gameOverScreen.Visible then
                tryTeleport()
            end
        end)
    end
end

local function setupTowerRenamer()
    repeat task.wait() until game:IsLoaded() and game.Players.LocalPlayer

    local function RenameTowers()
        local gameFolder = game:GetService("Workspace"):FindFirstChild("Game")
        if not gameFolder then return false end
        
        local towersFolder = gameFolder:FindFirstChild("Towers")
        if not towersFolder then return false end

        for i, tower in ipairs(towersFolder:GetChildren()) do
            if not tower.Name:match("^%d+%.") then
                tower.Name = i .. "." .. tower.Name
            end
        end
        return true
    end

    while true do
        pcall(RenameTowers)
        task.wait(5) -- Giảm tần suất kiểm tra để tối ưu
    end
end

-- 🚀 Khởi chạy tuần tự với delay
local startupSequence = {
    {name = "x1.5 Speed",      enabled = config["x1.5 Speed"],      func = function() loadstring(game:HttpGet(links["x1.5 Speed"]))() end},
    {name = "Join Map",        enabled = config["Map"] ~= nil,      func = function() loadstring(game:HttpGet(links["Join Map"]))() end},
    {name = "Auto Difficulty", enabled = config["Auto Difficulty"] ~= nil, func = function() loadstring(game:HttpGet(links["Auto Difficulty"]))() end},
    {name = "Run Macro",       enabled = config["Macros"] == "run" or config["Macros"] == "record", func = function() loadstring(game:HttpGet(links["Run Macro"]))() end},
    {name = "Auto Skill",      enabled = config["Auto Skill"],      func = function() loadstring(game:HttpGet(links["Auto Skill"]))() end},
    {name = "Tự động về lobby", enabled = true, func = setupAutoTeleport},
    {name = "Đặt lại tên tháp", enabled = true, func = setupTowerRenamer}
}

for _, item in ipairs(startupSequence) do
    tryRun(item.name, item.enabled, item.func)
    task.wait(1.5) -- Delay giữa các chức năng
end

print("✨ Tất cả chức năng đã được khởi chạy")
