local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local character = player.Character or player.CharacterAdded:Wait()
local hrp = character:WaitForChild("HumanoidRootPart")

-- Lấy Prompt gốc từ map
local promptPart = workspace.Game.Map.ProximityPrompts:FindFirstChild("Prompt")
if not promptPart then
    warn("Không tìm thấy Prompt gốc.")
    return
end

local prompt = promptPart:FindFirstChildWhichIsA("ProximityPrompt")
if not prompt then
    warn("Không tìm thấy ProximityPrompt bên trong.")
    return
end

-- Gắn Prompt gốc vào người
prompt.Parent = hrp
prompt.RequiresLineOfSight = false
prompt.MaxActivationDistance = 999999
prompt.HoldDuration = 999999
prompt.Enabled = true

-- Xoá GUI nếu nó xuất hiện ở PlayerGui.ProximityPrompts
local function setupGuiDestroy()
    playerGui.ChildAdded:Connect(function(child)
        if child.Name == "ProximityPrompts" then
            task.wait()
            child:Destroy()
        end
    end)
    local existing = playerGui:FindFirstChild("ProximityPrompts")
    if existing then
        existing:Destroy()
    end
end

setupGuiDestroy()

-- Xóa GUI nếu Prompt hiện
prompt.PromptShown:Connect(function(ui)
    ui:Destroy()
end)

-- Giữ Prompt mãi mãi
task.spawn(function()
    while true do
        if prompt.Enabled then
            prompt:InputHoldBegin()
        end
        task.wait(0.5)
    end
end)

-- Luôn bật lại nếu bị game tắt
task.spawn(function()
    while true do
        if not prompt.Enabled then
            prompt.Enabled = true
        end
        task.wait(0.5)
    end
end)
