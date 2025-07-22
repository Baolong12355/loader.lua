-- ✅ Auto Join Map - TDX (Đã thêm Remote đổi party + kiểm tra TRANSPORTING)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local config = getgenv().TDX_Config or {}
local targetMapName = config["Map"] or "Xmas1" -- Mặc định là Xmas1 (Christmas24Part1)
local expectedPlaceId = 9503261072 -- ID lobby TDX

-- Danh sách map cần đổi bằng Remote (dùng cả tên đầy đủ và tên rút gọn)
local specialMaps = {
    -- Tên đầy đủ
    ["Halloween Part 1"] = true,
    ["Halloween Part 2"] = true,
    ["Halloween Part 3"] = true,
    ["Halloween Part 4"] = true,
    ["Tower Battles"] = true,
    ["Christmas24Part1"] = true,
    ["Christmas24Part2"] = true,
    
    -- Tên rút gọn
    ["HW1"] = "Halloween Part 1",
    ["HW2"] = "Halloween Part 2",
    ["HW3"] = "Halloween Part 3",
    ["HW4"] = "Halloween Part 4",
    ["TB"] = "Tower Battles",
    ["Xmas1"] = "Christmas24Part1",
    ["Xmas2"] = "Christmas24Part2"
-- ✅ Auto Join Map - TDX (Đã sửa lỗi tên rút gọn)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local config = getgenv().TDX_Config or {}
local targetMapInput = config["Map"] or "Xmas1" -- Cho phép nhập tên rút gọn
local expectedPlaceId = 9503261072

-- Bảng ánh xạ TÊN RÚT GỌN → TÊN ĐẦY ĐỦ (chỉ dùng cho Remote)
local fullMapNames = {
    -- Halloween
    ["HW1"] = "Halloween Part 1",
    ["HW2"] = "Halloween Part 2", 
    ["HW3"] = "Halloween Part 3",
    ["HW4"] = "Halloween Part 4",
    
    -- Christmas
    ["Xmas1"] = "Christmas24Part1",
    ["Xmas2"] = "Christmas24Part2",
    
    -- Tower Battles
    ["TB"] = "Tower Battles"
}

-- Danh sách map cần đổi bằng Remote (dùng TÊN ĐẦY ĐỦ)
local specialMaps = {
    ["Halloween Part 1"] = true,
    ["Halloween Part 2"] = true,
    ["Halloween Part 3"] = true,
    ["Halloween Part 4"] = true,
    ["Tower Battles"] = true,
    ["Christmas24Part1"] = true,
    ["Christmas24Part2"] = true
}

-- Chuyển đổi tên map đầu vào → tên đầy đủ
local function getFullMapName(input)
    return fullMapNames[input] or input
end

local targetMapFullName = getFullMapName(targetMapInput) -- Tên đầy đủ dùng cho Remote
local targetMapName = targetMapInput -- Giữ nguyên tên gốc để so sánh

print("🎯 Map mục tiêu:", targetMapName)
print("📌 Tên đầy đủ:", targetMapFullName)

local function isInLobby()
    return game.PlaceId == expectedPlaceId
end

local function matchMap(displayName, targetName)
    -- So khớp cả tên hiển thị và tên đích (có thể là rút gọn hoặc đầy đủ)
    local displayFull = getFullMapName(displayName)
    local targetFull = getFullMapName(targetName)
    return displayFull == targetFull
end

local function trySetMapIfNeeded()
    -- Chỉ đổi map nếu nằm trong danh sách specialMaps (dùng tên ĐẦY ĐỦ)
    if specialMaps[targetMapFullName] then
        -- 🔁 Đổi sang Party Mode
        ReplicatedStorage.Network.ClientChangePartyTypeRequest:FireServer("Party")
        print("⚙️ Đã đổi sang chế độ Party")
        
        -- 🎯 Gửi TÊN ĐẦY ĐỦ lên Remote
        ReplicatedStorage.Network.ClientChangePartyMapRequest:FireServer(targetMapFullName)
        print("📡 Đã gửi tên map lên server:", targetMapFullName)
        
        task.wait(1.5)
        
        -- ▶️ Bắt đầu game
        ReplicatedStorage.Network.ClientStartGameRequest:FireServer()
        print("🚀 Đã yêu cầu bắt đầu game")
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

-- Thông báo bắt đầu script
print("====================================")
print("🛠️ TDX Auto Join Map - Phiên bản Tiếng Việt")
print("🎯 Map mục tiêu:", targetMapName)
print("📌 Tên đầy đủ:", specialMaps[targetMapName] or targetMapName)
print("====================================")

while isInLobby() do
    local ok, result = pcall(tryEnterMap)
    if not ok then
        warn("❌ Có lỗi:", result)
    elseif not result then
        break
    end
    task.wait()
end

print("Đ phải lobby bố m đình công")
