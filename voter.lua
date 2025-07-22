-- ⚙️ Config kiểm tra
getgenv().TDX_Config = {
    mapvoter = true,
    mapvoting = "MILITARY BASE" -- viết hoa chữ cái đầu của mỗi từ (dùng khi gửi remote)
}

-- 🚫 Nếu chưa bật config thì không làm gì
if not getgenv().TDX_Config or not getgenv().TDX_Config.mapvoter or not getgenv().TDX_Config.mapvoting then return end

-- ⏳ Chờ GUI hiện MapVoting
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local player = Players.LocalPlayer

repeat task.wait() until player:FindFirstChild("PlayerGui")
local gui = player.PlayerGui:WaitForChild("Interface"):WaitForChild("GameInfoBar"):WaitForChild("MapVoting")

-- 🧠 Hàm viết hoa toàn bộ
local function toUpper(str)
    return string.upper(str)
end

-- 🧠 Hàm viết hoa chữ cái đầu mỗi từ
local function titleCase(str)
    return str:gsub("(%w)(%w*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end)
end

-- 📌 Tên map để kiểm tra và vote
local targetMapUpper = toUpper(getgenv().TDX_Config.mapvoting)
local targetMapTitle = titleCase(getgenv().TDX_Config.mapvoting)

-- 📦 Remote
local changeRemote = ReplicatedStorage.Remotes:WaitForChild("MapChangeVoteCast")
local voteRemote = ReplicatedStorage.Remotes:WaitForChild("MapVoteCast")
local readyRemote = ReplicatedStorage.Remotes:WaitForChild("MapVoteReady")

local voted = false
while true do
    task.wait(0.25)

    local done = player.PlayerGui.Interface:FindFirstChild("MapVotingScreen") and
                 player.PlayerGui.Interface.MapVotingScreen.Bottom.ChangeMap.Disabled.Visible

    if done then break end -- ✅ Hết lượt đổi map

    for i = 1, 4 do
        local screen = workspace:FindFirstChild("Game") and workspace.Game.MapVoting.VotingScreens:FindFirstChild("VotingScreen" .. i)
        if screen then
            local mapGui = screen:FindFirstChild("ScreenPart") and screen.ScreenPart:FindFirstChild("SurfaceGui")
            local mapLabel = mapGui and mapGui:FindFirstChild("MapName")
            if mapLabel and typeof(mapLabel.Text) == "string" then
                local name = toUpper(mapLabel.Text)
                if name ~= targetMapUpper then
                    -- 🔁 Gọi remote đổi map nếu không đúng
                    changeRemote:FireServer(true)
                else
                    voted = true
                end
            end
        end
    end
end

-- ✅ Nếu đã thấy map cần vote thì vote map
if voted then
    voteRemote:FireServer(targetMapTitle)
    task.wait(0.25)
    readyRemote:FireServer()
else
    -- ❌ Nếu không thấy map cần vote, về lobby
    TeleportService:Teleport(9503261072, player)
end
