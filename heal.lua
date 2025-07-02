local player = game.Players.LocalPlayer
local camera = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

-- Tìm Prompt gốc
local prompt = workspace.Game.Map.ProximityPrompts:FindFirstChild("Prompt")
if prompt then
	prompt = prompt:FindFirstChildWhichIsA("ProximityPrompt")
end
if not prompt then
	warn("Không tìm thấy Prompt gốc.")
	return
end

-- ⚙️ Cấu hình Prompt
prompt.RequiresLineOfSight = false
prompt.MaxActivationDistance = 999999
prompt.HoldDuration = 999999
prompt.Enabled = true

-- 🧱 Tạo Part phía trước Camera
local fakePart = Instance.new("Part")
fakePart.Name = "CameraPromptPart"
fakePart.Size = Vector3.new(1, 1, 1)
fakePart.Transparency = 1
fakePart.Anchored = true
fakePart.CanCollide = false
fakePart.Parent = workspace

-- Prompt gắn vào part này
prompt.Parent = fakePart

-- Cập nhật vị trí part mỗi frame: nằm ngay trước camera (trung tâm nhìn)
game:GetService("RunService").RenderStepped:Connect(function()
	if camera and fakePart then
		local camCF = camera.CFrame
		fakePart.CFrame = camCF * CFrame.new(0, 0, -3) -- trước camera 3 studs
	end
end)

-- 🔁 Giữ Prompt liên tục
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

-- 🧹 Xoá GUI nếu có
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
