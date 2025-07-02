-- 📌 Script Auto Vote Chế Độ (Raw Version)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 🔎 Tìm Remote Events
local voteRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("DifficultyVoteCast", true) -- Tìm sâu trong thư mục
local readyRemote = ReplicatedStorage:WaitForChild("Remotes"):FindFirstChild("DifficultyVoteReady", true)

-- ❌ Thoát nếu không tìm thấy Remote
if not voteRemote then
    warn("⚠️ KHÔNG TÌM THẤY REMOTE VOTE!")
    return
end

-- ⚡ Lấy chế độ từ config (dùng nguyên bản)
local mode = getgenv().TDX_Config and getgenv().TDX_Config["Auto Difficulty"]

if not mode then
    warn("⚠️ CHƯA CÀI ĐẶT CHẾ ĐỘ TỰ ĐỘNG!")
    return
end

-- 🚀 Gửi vote (dùng tên gốc)
voteRemote:FireServer(mode)
print("✅ ĐÃ CHỌN CHẾ ĐỘ (RAW):", mode)

-- ⏳ Tự động bấm BẮT ĐẦU sau 2s
if readyRemote then
    task.wait(2)
    readyRemote:FireServer()
    print("🎮 ĐÃ KÍCH HOẠT BẮT ĐẦU!")
end
