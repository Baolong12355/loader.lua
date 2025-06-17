-- 🛡️ Auto Difficulty Selector - TDX
-- Phiên bản nhận config từ loader

-- Đảm bảo config được cung cấp từ loader
if not _G.TDX_Config then
    warn("⚠️ Không tìm thấy config từ loader! Vui lòng cung cấp config qua _G.TDX_Config")
    return
end

-- Lấy config từ global
local config = _G.TDX_Config
local vote = config["Auto Difficulty"] or "easy"  -- Mặc định easy nếu không có config

-- Viết hoa chữ cái đầu cho đúng định dạng server
local mode = vote:sub(1,1):upper() .. vote:sub(2):lower()

-- Đợi Remotes
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Đợi DifficultyVoteCast (tối đa 10s)
local voteRemote
local timeWaited = 0
repeat
    voteRemote = remotes:FindFirstChild("DifficultyVoteCast")
    if not voteRemote then
        task.wait(0.2)
        timeWaited = timeWaited + 0.2
    end
until voteRemote or timeWaited > 10

if not voteRemote then
    warn("⚠️ Không tìm thấy Remote DifficultyVoteCast sau 10s!")
    return
end

-- Gửi remote chọn chế độ
voteRemote:FireServer(mode)
print("✅ Đã chọn chế độ:", mode)

-- Nếu cần sẵn sàng ngay sau khi chọn độ khó
local readyRemote = remotes:WaitForChild("DifficultyVoteReady", 5)
if readyRemote then
    readyRemote:FireServer()
    print("✅ Đã báo ready sau khi chọn độ khó")
else
    warn("⚠️ Không tìm thấy Remote DifficultyVoteReady")
end
