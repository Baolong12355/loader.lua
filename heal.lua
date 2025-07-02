local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")
local playerGui = player:WaitForChild("PlayerGui")

-- 🔍 Tìm Prompt gốc từ Map
local promptPart = workspace:FindFirstChild("Game")
if promptPart then
	promptPart = promptPart:FindFirstChild("Map")
end
if promptPart then
	promptPart = promptPart:FindFirstChild("ProximityPrompts")
end
if promptPart then
	promptPart = promptPart:FindFirstChild("Prompt")
end
if not promptPart then
	warn("Không tìm thấy Prompt Part trong map.")
	return
end

-- 🎯 Lấy Prompt gốc
local prompt = promptPart:FindFirstChildWhichIsA("ProximityPrompt")
if not prompt then
	warn("Không tìm thấy ProximityPrompt bên trong Part.")
	return
end

-- ✅ Gắn Prompt vào nhân vật
prompt.Parent = hrp
prompt.RequiresLineOfSight = false
prompt.MaxActivationDistance = 999999
prompt.HoldDuration = 999999
prompt.Enabled = true

-- 🔁 Tự động giữ Prompt vĩnh viễn
task.spawn(function()
	while true do
		if prompt and prompt.Enabled then
			pcall(function()
				prompt:InputHoldBegin()
			end)
		end
		task.wait(0.5)
	end
end)

-- 🔁 Tự bật lại nếu Prompt bị disable
task.spawn(function()
	while true do
		if prompt and not prompt.Enabled then
			prompt.Enabled = true
		end
		task.wait(1)
	end
end)

-- 🧹 Xoá GUI Prompt nếu nó xuất hiện trong PlayerGui
local function xoaGuiPrompt()
	local existed = playerGui:FindFirstChild("ProximityPrompts")
	if existed then existed:Destroy() end

	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "ProximityPrompts" then
			task.wait()
			child:Destroy()
		end
	end)
end

xoaGuiPrompt()
