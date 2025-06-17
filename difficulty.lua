-- 📌 Auto chọn chế độ trong trận
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Chờ remote (tối đa 10s)
local voteRemote
for i = 1, 100 do
	voteRemote = remotes:FindFirstChild("DifficultyVoteCast")
	if voteRemote then break end
	task.wait(0.1)
end

if not voteRemote then
	warn("⚠️ Không tìm thấy remote DifficultyVoteCast sau 10s")
	return
end

-- Lấy cấu hình
local config = getgenv().TDX_Config or {}
local rawVote = config["Auto Difficulty"]

if not rawVote then
	warn("⚠️ Không có cấu hình Auto Difficulty")
	return
end

-- Chuẩn hóa thành "Easy", "Normal", "Hard"
local mode = rawVote:sub(1,1):upper() .. rawVote:sub(2):lower()

-- Gửi remote
voteRemote:FireServer(mode)
print("📌 Đã chọn chế độ:", mode)
