assert(writefile and getconnections, "⚠️ Cần exploit hỗ trợ writefile và getconnections!")

-- ======== CẤU HÌNH ========
local teleportPositions = {
    Vector3.new(-746.103271484375, 86.75001525878906, 0),
    Vector3.new(-620.12060546875, 86.75, 0),
    Vector3.new(-353.05078125, 132.3436279296875, 50.36767578125),
    Vector3.new(-70.82891845703125, 81.39054107666016, 834.0664672851562)
}
local spawnRoot = workspace.ItemSpawns.LabCrate
local keywordSpawn = "equipment crate+has been reported!"
local keywordDespawn = "equipment crate+has despawned or been turned in!"
local checkInterval = 0.25

-- ======== HÀM GHI LOG CHAT ========
local logFile = "ChatDump_" .. os.time() .. ".txt"
writefile(logFile, "")
local lastChat = ""

local function logToFile(text)
    appendfile(logFile, text .. "\n")
    lastChat = text
end

local function monitorChat()
    local function scan(container)
        container.DescendantAdded:Connect(function(desc)
            if desc:IsA("TextLabel") and desc.Text and #desc.Text > 0 then
                local text = desc.Text
                logToFile("[GUI Chat] " .. text)
            end
        end)
    end

    local guiTargets = {
        game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui"),
        game:GetService("CoreGui")
    }

    for _, gui in ipairs(guiTargets) do
        scan(gui)
        gui.ChildAdded:Connect(scan)
    end
end

-- ======== HÀM TELEPORT ========
local function teleportTo(position)
    local character = game:GetService("Players").LocalPlayer.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        character:MoveTo(position)
    end
end

-- ======== HÀM KIỂM TRA SPAWN ========
local function getValidCrate()
    for _, spawn in ipairs(spawnRoot:GetChildren()) do
        if spawn:IsA("Model") and spawn:FindFirstChild("Crate") then
            local proximity = spawn.Crate:FindFirstChild("ProximityAttachment") and spawn.Crate.ProximityAttachment:FindFirstChild("Interaction")
            if proximity and proximity.Enabled then
                return proximity
            end
        end
    end
    return nil
end

-- ======== HÀM TƯƠNG TÁC CRATE ========
local function turnInCrate()
    local args = {
        [1] = "TurnInCrate"
    }
    game:GetService("ReplicatedStorage"):WaitForChild("ReplicatedModules"):WaitForChild("KnitPackage"):WaitForChild("Knit"):WaitForChild("Services"):WaitForChild("DialogueService"):WaitForChild("RF"):WaitForChild("CheckRequirement"):InvokeServer(unpack(args))
end

-- ======== HÀM ĐỢI CHAT CHỨA TỪ KHÓA ========
local function waitForKeyword(keyword)
    while true do
        if lastChat:lower():find(keyword:lower()) then
            break
        end
        task.wait(0.25)
    end
end

-- ======== VÒNG LẶP CHÍNH ========
monitorChat()
teleportTo(teleportPositions[1]) -- dịch chuyển ban đầu

while true do
    local found = false

    for _, pos in ipairs(teleportPositions) do
        teleportTo(pos)
        task.wait(checkInterval)

        local proximity = getValidCrate()
        if proximity then
            fireproximityprompt(proximity, 1, true)

            repeat
                task.wait()
            until not proximity.Enabled

            turnInCrate()
            found = true
            break
        end
    end

    if not found then
        waitForKeyword(keywordSpawn)
    else
        waitForKeyword(keywordDespawn)
    end
end