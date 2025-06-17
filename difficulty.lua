-- 📌 Auto chọn chế độ trong trận và bấm bắt đầu
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Chờ remote vote (tối đa 10s)
local voteRemote, readyRemote
for i = 1, 100 do
	voteRemote = remotes:FindFirstChild("DifficultyVoteCast")
	readyRemote = remotes:FindFirstChild("DifficultyVoteReady")
	if voteRemote and readyRemote then break end
	task.wait(0.1)
end

if not voteRemote then
	warn("⚠️ Không tìm thấy DifficultyVoteCast")
	return
end

-- Lấy cấu hình
local config = getgenv().TDX_Config or {}
local rawVote = config["Auto Difficulty"]

if not rawVote then
	warn("⚠️ Không có cấu hình Auto Difficulty")
	return
end

-- Định dạng lại chuỗi vote (vd: "easy" → "Easy")
local mode = rawVote:sub(1,1):upper() .. rawVote:sub(2):lower()

-- Gửi vote chọn chế độ
voteRemote:FireServer(mode)
print("📌 Đã chọn chế độ:", mode)

-- Nếu có remote "READY", gửi luôn để bắt đầu
if readyRemote then
	task.wait(0.5)
	readyRemote:FireServer()
	print("▶️ Đã bấm BẮT ĐẦU trận.")
end
