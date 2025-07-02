local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- 🔄 Hàm tìm Prompt gốc trong map
local function findPrompt()
	local container = workspace:FindFirstChild("Game")
	if not container then return nil end
	container = container:FindFirstChild("Map")
	if not container then return nil end
	container = container:FindFirstChild("ProximityPrompts")
	if not container then return nil end
	container = container:FindFirstChild("Prompt")
	if not container then return nil end
	return container:FindFirstChildWhichIsA("ProximityPrompt")
end

-- 🧹 Xóa GUI khi nó xuất hiện trong PlayerGui
local function setupGuiDestroy()
	-- Xoá ngay nếu đã tồn tại
	local existing = playerGui:FindFirstChild("ProximityPrompts")
	if existing then existing:Destroy() end

	-- Theo dõi nếu xuất hiện lại
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "ProximityPrompts" then
			task.wait()
			child:Destroy()
		end
	end)
end

setupGuiDestroy()

-- 🔁 Vòng lặp giữ Prompt liên tục
task.spawn(function()
	while true do
		local prompt = findPrompt()
		if prompt then
			-- Đảm bảo giữ từ xa
			prompt.MaxActivationDistance = 999999
			prompt.RequiresLineOfSight = false

			if not prompt.Enabled then
				prompt.Enabled = true
			end

			pcall(function()
				prompt:InputHoldBegin()
			end)
		end
		task.wait(0.5)
	end
end)
