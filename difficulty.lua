-- 📌 Script Auto Vote Chế Độ (Raw Version)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- 🔎 Tìm Remote Events
local voteRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("DifficultyVoteCast", true)
local readyRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("DifficultyVoteReady", true)

-- ❌ Thoát nếu không tìm thấy Remote
if not voteRemote then
    warn("⚠️ KHÔNG TÌM THẤY REMOTE VOTE!")
    return
end

-- ⚡ Lấy chế độ từ config
local mode = getgenv().TDX_Config and getgenv().TDX_Config["Auto Difficulty"]

if not mode then
    warn("⚠️ CHƯA CÀI ĐẶT CHẾ ĐỘ TỰ ĐỘNG!")
    return
end

-- ⏳ Chờ đến khi giao diện DifficultyVoteScreen hiển thị
local difficultyVoteScreen
repeat
    task.wait(0.25)
    local interface = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("Interface")
    difficultyVoteScreen = interface and interface:FindFirstChild("DifficultyVoteScreen")
until difficultyVoteScreen and difficultyVoteScreen.Visible

-- 🚀 Gửi vote
voteRemote:FireServer(mode)
print("✅ ĐÃ CHỌN CHẾ ĐỘ (RAW):", mode)

-- 🟢 Bắt đầu sau 0.25s
if readyRemote then
    task.wait(0.25)
    readyRemote:FireServer()
    print("🎮 ĐÃ KÍCH HOẠT BẮT ĐẦU!")
end
