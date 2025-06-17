local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local interface = gui:WaitForChild("Interface")
local gameOver = interface:WaitForChild("GameOverScreen")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local teleport = remotes:FindFirstChild("RequestTeleportToLobby")

local lastState = gameOver.Visible

local function sendBack()
	task.wait(1)
	if teleport then
		if teleport:IsA("RemoteEvent") then
			teleport:FireServer()
		elseif teleport:IsA("RemoteFunction") then
			teleport:InvokeServer()
		end
	end
end

-- Lặp liên tục để kiểm tra trạng thái Visible mỗi 1 giây
task.spawn(function()
	while true do
		local current = gameOver.Visible
		if current and not lastState then
			-- Khi từ false chuyển thành true
			sendBack()
		end
		lastState = current
		task.wait(1)
	end
end)
