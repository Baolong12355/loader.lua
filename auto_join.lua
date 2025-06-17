-- ✅ Auto Join Map - TDX (Fixed Structure) -- Tự động vào map với cấu trúc chính xác

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local config = getgenv().TDX_Config or {}
local targetMapName = config["Map"] or "HAKUREI SHRINE"
local expectedPlaceId = 9503261072 -- lobby TDX

-- Kiểm tra có đang ở đúng lobby TDX không
local function isInLobby()
    return game.PlaceId == expectedPlaceId
end

-- So sánh tên map mềm
local function matchMap(a, b)
    return (a or ""):lower():gsub("%s+", "") == (b or ""):lower():gsub("%s+", "")
end

-- Dịch chuyển chính xác đến Detector
local function enterDetectorExact(detector)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then
        hrp.CFrame = detector.CFrame * CFrame.new(0, 0, -2) -- Đứng trước detector một chút
    end
end

-- Xử lý vào map nếu hợp lệ
local function tryEnterMap()
    if not isInLobby() then
        warn("⛔ Đã rời khỏi lobby TDX. Dừng script.")
        return false
    end

    local LeaveQueue = ReplicatedStorage:FindFirstChild("Network") and ReplicatedStorage.Network:FindFirstChild("LeaveQueue")
    local roots = {Workspace:FindFirstChild("APCs"), Workspace:FindFirstChild("APCs2")}

    for _, root in ipairs(roots) do
        if root then
            for _, folder in ipairs(root:GetChildren()) do
                if folder:IsA("Folder") then
                    -- APC và Detector nằm trong Folder
                    local apc = folder:FindFirstChild("APC")
                    local detector = apc and apc:FindFirstChild("Detector")
                    
                    -- MapDisplay nằm trực tiếp trong Folder
                    local mapDisplay = folder:FindFirstChild("mapdisplay")
                    local screen = mapDisplay and mapDisplay:FindFirstChild("screen")
                    local displayscreen = screen and screen:FindFirstChild("displayscreen")
                    local mapLabel = displayscreen and displayscreen:FindFirstChild("map")
                    local plrCountLabel = displayscreen and displayscreen:FindFirstChild("plrcount")

                    if detector and mapLabel and plrCountLabel then
                        if matchMap(mapLabel.Text, targetMapName) then
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
                                task.wait(1.5)
                            else
                                print("🔄 Đợi map trống...", mapLabel.Text, "| Hiện tại:", cur.."/"..max)
                            end
                        end
                    end
                end
            end
        end
    end

    return true -- Tiếp tục lặp
end

-- Main loop
while isInLobby() do
    local ok, result = pcall(tryEnterMap)
    if not ok then
        warn("❌ Có lỗi:", result)
    elseif not result then
        break
    end
    task.wait(1)
end

print("📤 Script kết thúc")
