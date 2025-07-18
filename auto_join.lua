-- ✅ Auto Join Map - TDX (Đã thêm Remote đổi party + kiểm tra TRANSPORTING)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local config = getgenv().TDX_Config or {}
local targetMapName = config["Map"] or "Christmas24Part1"
local expectedPlaceId = 9503261072

-- Map cần đổi bằng Remote (ghi đúng tên, phân biệt hoa thường)
local specialMaps = {
    ["Halloween Part 1"] = true,
    ["Halloween Part 2"] = true,
    ["Halloween Part 3"] = true,
    ["Halloween Part 4"] = true,
    ["Tower Battles"] = true,
    ["Christmas24Part1"] = true,
    ["Christmas24Part2"] = true
}

local function isInLobby()
    return game.PlaceId == expectedPlaceId
end

local function matchMap(a, b)
    return tostring(a or "") == tostring(b or "")
end

local function enterDetectorExact(detector)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.CFrame = detector.CFrame * CFrame.new(0, 0, -2)
    end
end

local function trySetMapIfNeeded()
    if specialMaps[targetMapName] then
        -- 🔁 Đổi chế độ sang Party trước
        local argsPartyType = { "Party" }
        ReplicatedStorage:WaitForChild("Network"):WaitForChild("ClientChangePartyTypeRequest"):FireServer(unpack(argsPartyType))
        print("⚙️ Đã đổi sang chế độ Party")

        -- 🎯 Chọn map
        local argsMap = { targetMapName }
        ReplicatedStorage:WaitForChild("Network"):WaitForChild("ClientChangePartyMapRequest"):FireServer(unpack(argsMap))
        print("🎯 Đã chọn map:", targetMapName)

        task.wait(1.5)

        -- ▶️ Bắt đầu game
        ReplicatedStorage:WaitForChild("Network"):WaitForChild("ClientStartGameRequest"):FireServer()
        print("🚀 Đã gửi yêu cầu bắt đầu game")
    end
end

local function tryEnterMap()
    if not isInLobby() then
        warn("⛔ Đã rời khỏi lobby TDX. Dừng script.")
        return false
    end

    trySetMapIfNeeded()

    local LeaveQueue = ReplicatedStorage:FindFirstChild("Network") and ReplicatedStorage.Network:FindFirstChild("LeaveQueue")
    local roots = {Workspace:FindFirstChild("APCs"), Workspace:FindFirstChild("APCs2")}

    for _, root in ipairs(roots) do
        if root then
            for _, folder in ipairs(root:GetChildren()) do
                if folder:IsA("Folder") then
                    local apc = folder:FindFirstChild("APC")
                    local detector = apc and apc:FindFirstChild("Detector")
                    local mapDisplay = folder:FindFirstChild("mapdisplay")
                    local screen = mapDisplay and mapDisplay:FindFirstChild("screen")
                    local displayscreen = screen and screen:FindFirstChild("displayscreen")
                    local mapLabel = displayscreen and displayscreen:FindFirstChild("map")
                    local plrCountLabel = displayscreen and displayscreen:FindFirstChild("plrcount")
                    local statusLabel = displayscreen and displayscreen:FindFirstChild("status")

                    if detector and mapLabel and plrCountLabel and statusLabel then
                        if matchMap(mapLabel.Text, targetMapName) then
                            if statusLabel.Text == "TRANSPORTING..." then
                                print("⏸️ Đang có người vào map... Bỏ qua")
                                continue
                            end

                            local countText = plrCountLabel.Text or ""
                            local cur, max = countText:match("(%d+)%s*/%s*(%d+)")
                            cur, max = tonumber(cur), tonumber(max)

                            if not cur or not max then
                                print("⚠️ Không đọc được số người:", countText)
                                continue
                            end

                            if cur == 0 and max == 4 then
                                print("✅ Vào map:", mapLabel.Text, "| Trạng thái:", cur.."/"..max)
                                enterDetectorExact(detector)
                                return true
                            elseif cur >= 2 and max == 4 and LeaveQueue then
                                print("❌ Map đã có người:", cur.."/"..max, "→ Thoát queue")
                                pcall(LeaveQueue.FireServer, LeaveQueue)
                                task.wait()
                            else
                                print("🔄 Đợi map trống...", mapLabel.Text, "| Hiện tại:", cur.."/"..max)
                            end
                        end
                    end
                end
            end
        end
    end

    return true
end

while isInLobby() do
    local ok, result = pcall(tryEnterMap)
    if not ok then
        warn("❌ Có lỗi:", result)
    elseif not result then
        break
    end
    task.wait()
end

print("📤 Script kết thúc")
