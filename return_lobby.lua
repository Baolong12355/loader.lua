local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local interface = gui:WaitForChild("Interface")
local gameOver = interface:WaitForChild("GameOverScreen")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local teleport = remotes:FindFirstChild("RequestTeleportToLobby")

local function sendBackToLobby()
	task.wait(1)
	if teleport then
		if teleport:IsA("RemoteEvent") then
			teleport:FireServer()
		elseif teleport:IsA("RemoteFunction") then
			teleport:InvokeServer()
		end
	end
end

if gameOver and teleport then
	-- Trường hợp đã visible từ trước
	if gameOver.Visible then
		sendBackToLobby()
	end

	-- Trường hợp visible thay đổi sau
