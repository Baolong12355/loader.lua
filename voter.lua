local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer

local function toUpper(str)
	return string.upper(str)
end

local function toSentenceCase(str)
	return string.gsub(str, "^%l", string.upper)
end

-- chờ until visible
local function waitUntilVisible(instance, timeout)
	local t = 0
	while not (instance and instance.Visible) and t < (timeout or 10) do
		task.wait(0.1)
		t += 0.1
	end
	return instance and instance.Visible
end

-- kiểm tra config hợp lệ
if not getgenv().TDX_Config or not getgenv().TDX_Config.mapvoter or not getgenv().TDX_Config.mapvoting then return end

local desiredMap = toUpper(getgenv().TDX_Config.mapvoting)

-- chờ GUI hiện
local mapVotingGui = LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Interface"):WaitForChild("GameInfoBar"):WaitForChild("MapVoting")
if not waitUntilVisible(mapVotingGui, 10) then return end

local voted = false
local votingScreens = workspace:WaitForChild("Game"):WaitForChild("MapVoting"):WaitForChild("VotingScreens")

-- lặp kiểm tra 4 màn
for i = 1, 4 do
	local screen = votingScreens:FindFirstChild("VotingScreen"..i)
	if screen then
		local mapNameLabel = screen:FindFirstChild("ScreenPart") and screen.ScreenPart:FindFirstChild("SurfaceGui") and screen.ScreenPart.SurfaceGui:FindFirstChild("MapName")
		if mapNameLabel and toUpper(mapNameLabel.Text) == desiredMap then
			voted = true
			break
		end
	end
end

-- nếu chưa thấy map mong muốn
if not voted then
	repeat
		-- Gọi remote đổi map
		ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MapChangeVoteCast"):FireServer(true)
		task.wait()
	until LocalPlayer.PlayerGui.Interface.MapVotingScreen.Bottom.ChangeMap.Disabled.Visible
end

-- kiểm tra lần nữa sau đổi
local found = false
for i = 1, 4 do
	local screen = votingScreens:FindFirstChild("VotingScreen"..i)
	if screen then
		local mapNameLabel = screen:FindFirstChild("ScreenPart") and screen.ScreenPart:FindFirstChild("SurfaceGui") and screen.ScreenPart.SurfaceGui:FindFirstChild("MapName")
		if mapNameLabel and toUpper(mapNameLabel.Text) == desiredMap then
			found = true
			break
		end
	end
end

if found then
	local formattedName = toSentenceCase(string.lower(desiredMap)) -- gửi map với chữ cái đầu hoa
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MapVoteCast"):FireServer(formattedName)
	task.wait(0.25)
	ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("MapVoteReady"):FireServer()
else
	-- teleport về lobby TDX (ID gốc: 9503261072)
	TeleportService:Teleport(9503261072)
end
