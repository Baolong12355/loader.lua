local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")

if Remotes then
    local Remote = Remotes:FindFirstChild("SoloToggleSpeedControl")
    if Remote then
        if Remote:IsA("RemoteEvent") then
            Remote:FireServer(true, true)
        elseif Remote:IsA("RemoteFunction") then
            Remote:InvokeServer(true, true)
        end
    else
        warn("⚠️ Không tìm thấy SoloToggleSpeedControl")
    end
else
    warn("⚠️ Không tìm thấy Remotes")
end
