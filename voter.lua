-- Script Auto Vote Map cho Tower Defense X
-- Phiên bản không timeout và không kiểm tra mapvoter

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

-- Lấy thông tin người chơi
local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")

-- Chuẩn hóa tên map
local function normalize(str)
    return string.upper((str:gsub("%s+", " ")):gsub("^%s*(.-)%s*$", "%1"))
end

-- Viết hoa chữ cái đầu
local function titleCase(str)
    return string.gsub(str, "(%w)(%w*)", function(first, rest)
        return string.upper(first) .. string.lower(rest)
    end)
end

-- Teleport về lobby
local function teleportToLobby()
    local lobbyPlaceId = 9503261072
    TeleportService:Teleport(lobbyPlaceId)
end

-- Kiểm tra cấu hình cơ bản
if not getgenv().TDX_Config or not getgenv().TDX_Config.mapvoting then
    warn("❌ Thiếu cấu hình mapvoting")
    return
end

print("🔄 Đang chờ giao diện vote...")

-- Chờ giao diện vote xuất hiện (không timeout)
repeat
    task.wait()
until gui:FindFirstChild("Interface") and 
      gui.Interface:FindFirstChild("GameInfoBar") and 
      gui.Interface.GameInfoBar:FindFirstChild("MapVoting") and 
      gui.Interface.GameInfoBar.MapVoting.Visible

print("✅ Đã tìm thấy giao diện vote")

-- Tìm map trong các lựa chọn vote
local targetMap = normalize(getgenv().TDX_Config.mapvoting)
local mapScreens = workspace:WaitForChild("Game"):WaitForChild("MapVoting"):WaitForChild("VotingScreens")

local found = false
for i = 1, 4 do
    local screen = mapScreens:FindFirstChild("VotingScreen"..i)
    if screen then
        local mapGui = screen:FindFirstChild("ScreenPart"):FindFirstChild("SurfaceGui")
        if mapGui and mapGui:FindFirstChild("MapName") then
            local displayedName = normalize(mapGui.MapName.Text)
            if displayedName == targetMap then
                found = true
                break
            end
        end
    end
end

-- Xử lý khi không tìm thấy map
if not found then
    print("🔍 Không tìm thấy map '"..getgenv().TDX_Config.mapvoting.."', đang thử đổi map...")
    
    local changeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MapChangeVoteCast")
    local changeGui = gui.Interface:WaitForChild("MapVotingScreen").Bottom.ChangeMap
    
    while not changeGui.Disabled.Visible do
        changeRemote:FireServer(true)
        task.wait(0.5)
    end
    
    print("⏳ Đã hết lượt đổi map")
    teleportToLobby()
    return
end

-- Thực hiện vote
print("🗳️ Đang vote cho map:", getgenv().TDX_Config.mapvoting)
local voteName = titleCase(getgenv().TDX_Config.mapvoting)
local voteRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MapVoteCast")
local readyRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MapVoteReady")

-- Bọc trong pcall để bắt lỗi
local success, err = pcall(function()
    voteRemote:FireServer(voteName)
    task.wait(0.1)
    readyRemote:FireServer()
end)

if success then
    print("✅ Đã vote thành công cho map:", voteName)
else
    warn("❌ Lỗi khi vote:", err)
    teleportToLobby()
end
