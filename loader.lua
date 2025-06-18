-- ✅ TDX Loader - Giữ nguyên bản gốc từng script
local config = getgenv().TDX_Config or {}

-- Không sửa hàm tryRun gốc
local function tryRun(name, enabled, url)
    if enabled and typeof(url) == "string" and url:match("^https?://") then
        print("⏳ Loading:", name)
        local ok, result = pcall(function()
            return loadstring(game:HttpGet(url))()
        end)
        if ok then
            print("✅ Loaded:", name)
        else
            warn("❌ Failed:", name, result)
        end
    else
        print("⏭️ Skipped:", name)
    end
end

-- Giữ nguyên links gốc
local base = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/"
local links = {
    ["x1.5 Speed"]      = base .. "speed.lua",
    ["Auto Skill"]      = base .. "auto_skill.lua",
    ["Run Macro"]       = base .. "run_macro.lua",
    ["Join Map"]        = base .. "auto_join.lua",
    ["Auto Difficulty"] = base .. "difficulty.lua"
}

-- Chạy tuần tự các chức năng từ repo (giữ nguyên thứ tự gốc)
tryRun("x1.5 Speed",      config["x1.5 Speed"], links["x1.5 Speed"])
task.wait(1)

tryRun("Join Map",        config["Map"] ~= nil, links["Join Map"])
task.wait(0.5)

tryRun("Auto Difficulty", config["Auto Difficulty"] ~= nil, links["Auto Difficulty"])
task.wait(1)

tryRun("Run Macro",       config["Macros"] == "run" or config["Macros"] == "record", links["Run Macro"])
task.wait(2)

tryRun("Auto Skill",      config["Auto Skill"], links["Auto Skill"])
task.wait(2)

-- Tích hợp nguyên bản script Return Lobby (không sửa gì)
do
    print("⏳ Loading: Return Lobby (Integrated)")
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
    else
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
                    print("✅ Teleport thành công")
                    return true
                else
                    warn(`❌ Lỗi lần {attempt}:`, response)
                    task.wait(1)
                end
            end
            return false
        end

        if gameOverScreen and gameOverScreen.Visible then
            tryTeleport()
        end

        if gameOverScreen then
            gameOverScreen:GetPropertyChangedSignal("Visible"):Connect(function()
                if gameOverScreen.Visible then
                    tryTeleport()
                end
            end)
        end
    end
    print("✅ Loaded: Return Lobby (Integrated)")
end

-- Tích hợp nguyên bản script Rename Towers (không sửa gì)
do
    print("⏳ Loading: Rename Towers (Integrated)")
    repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

    local function RenameTowers()
        local towersFolder = game:GetService("Workspace"):FindFirstChild("Game"):FindFirstChild("Towers")
        
        if not towersFolder then
            return false
        end

        for i, tower in ipairs(towersFolder:GetChildren()) do
            if not tower.Name:match("^%d+%.") then
                tower.Name = i .. "." .. tower.Name
            end
        end
        
        return true
    end

    while true do
        pcall(RenameTowers)
        wait()
    end
    print("✅ Loaded: Rename Towers (Integrated)")
end
