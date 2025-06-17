local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local interface = gui:WaitForChild("Interface")
local gameOver = interface:WaitForChild("GameOverScreen")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local teleport = remotes:FindFirstChild("RequestTeleportToLobby")

local function tryTeleport()
	while task.wait(1) do
		local ok, err = pcall(function()
			if teleport:IsA("RemoteEvent") then
				teleport:FireServer()
			elseif teleport:IsA("RemoteFunction") then
				teleport:InvokeServer()
			end
		end)
		if ok then
			print("✅ Đã gửi yêu cầu về lobby.")
			break
		else
			warn("❌ Gửi teleport thất bại, thử lại... ", err)
		end
	end
end

if gameOver and teleport then
	if gameOver.Visible then
		tryTeleport()
	end

	gameOver:GetPropertyChangedSignal("Visible"):Connect(function()
		if gameOver.Visible then
			tryTeleport()
		end
	end)
end
