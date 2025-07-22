-- ✅ Config kiểm soát
getgenv().TDX_Config = {
    mapvoter = true,
    mapvoting = "Military Base"
}

-- ⛔ Script sẽ không chạy nếu chưa được bật
if not getgenv().TDX_Config or not getgenv().TDX_Config.mapvoter or not getgenv().TDX_Config.mapvoting then return end

-- ✅ Chờ đến khi GUI hiện MapVoting
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local player = Players.LocalPlayer

local function waitForMapVotingGUI()
    local guiPath = player:WaitForChild("PlayerGui"):WaitForChild("Interface"):WaitForChild("GameInfoBar"):WaitForChild("MapVoting")
    while not guiPath.Visible do
        task.wait(0.1)
    end
end

-- ✅ Chuyển chuỗi thành dạng 'Hưu Lưu' (capitalize đầu mỗi chữ)
local function capitalizeWords(str)
    return str:gsub("(%S)(%S*)", function(a, b)
        return utf8.upper(a) .. utf8.lower(b)
    end)
end

-- ✅ Chuyển chuỗi thành viết hoa toàn bộ
local function toUpperAll(str)
    return utf8.upper(str)
end

-- ✅ Thực hiện Vote
local function voteLoop()
    local voted = false
    local targetMapUpper = toUpperAll(getgenv().TDX_Config.mapvoting)

    local votingScreens = workspace:WaitForChild("Game"):WaitForChild("MapVoting"):WaitForChild("VotingScreens")

    for i = 1, 4 do
        local screen = votingScreens:FindFirstChild("VotingScreen" .. i)
        if screen then
            local mapNameLabel = screen:FindFirstChild("ScreenPart") and screen.ScreenPart:FindFirstChild("SurfaceGui") and screen.ScreenPart.SurfaceGui:FindFirstChild("MapName")
            if mapNameLabel then
                local currentMap = toUpperAll(mapNameLabel.Text)
                if currentMap ~= targetMapUpper then
                    local changeArgs = {true}
                    ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MapChangeVoteCast"):FireServer(unpack(changeArgs))
                    task.wait(0.25)
                else
                    voted = true
                    break
                end
            end
        end
    end

    return voted
end

-- ✅ Gửi vote nếu đã chọn đúng map
local function sendVote()
    local mapName = capitalizeWords(getgenv().TDX_Config.mapvoting)
    ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MapVoteCast"):FireServer(mapName)
    task.wait(0.25)
    ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MapVoteReady"):FireServer()
end

-- ✅ Kiểm tra đã hết lượt đổi chưa
local function isOutOfChange()
    local gui = player:WaitForChild("PlayerGui"):WaitForChild("Interface"):WaitForChild("MapVotingScreen")
    local changeMapGui = gui:WaitForChild("Bottom"):WaitForChild("ChangeMap")
    return changeMapGui.Disabled.Visible
end

-- ✅ Dịch chuyển về lobby nếu không thể vote
local function teleportToLobby()
    TeleportService:Teleport(9503261072) -- ID Tower Defense X Lobby
end

-- ✅ Luồng chính
coroutine.wrap(function()
    waitForMapVotingGUI()

    local success = false
    repeat
        success = voteLoop()
        task.wait(0.5)
    until success or isOutOfChange()

    if success then
        sendVote()
    else
        teleportToLobby()
    end
end)()
