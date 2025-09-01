repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- urls
local remoteKeyURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/key.txt" -- URL mới để lấy key
local sheetURL = "https://api.sheetbest.com/sheets/15da3e15-a25e-423c-bdbf-92a1deaae024"
local jsonURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/x.json"
local loaderURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/loader.lua"
local skipWaveURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/auto_skip.lua"
local macroFolder = "tdx/macros"
local macroFile = macroFolder.."/x.json"

local maxSlots = 5
local pingInterval = 30
local username = Players.LocalPlayer.Name

-- Cấu hình loader sớm để có thể lấy Key
getgenv().TDX_Config = getgenv().TDX_Config or {
    ["Key"] = "", -- Để trống hoặc cung cấp một giá trị mặc định nếu cần
    ["mapvoting"] = "MILITARY BASE",
    ["Return Lobby"] = true,
    ["x1.5 Speed"] = true,
    ["loadout"] = 2,
    ["Auto Skill"] = true,
    ["Map"] = "Tower Battles",
    ["Macros"] = "run",
    ["Macro Name"] = "x",
    ["Auto Difficulty"] = "Tower Battles"
}

local inputKey = getgenv().TDX_Config.Key

-- Hàm mới để xác thực key từ xa
local function validateRemoteKey(key)
    if not key or key == "" then return false end -- Kiểm tra nếu key rỗng
    local success, content = pcall(function()
        return game:HttpGet(remoteKeyURL)
    end)

    if not success then
        warn("[✘] Không thể tải key từ xa:", content)
        return false
    end

    for line in content:gmatch("[^\r\n]+") do
        if line:match("^%s*(.-)%s*$") == key then
            return true
        end
    end
    return false
end

-- Thực hiện xác thực key từ xa
if not validateRemoteKey(inputKey) then
    Players.LocalPlayer:Kick("Key không hợp lệ hoặc không có trong danh sách.")
    return
end

-- update trạng thái online lên sheet
local function updateStatus(username, key, status)
    local data = {
        username = username,
        key = key,
        status = status,
        last_ping = os.date("!%Y-%m-%dT%H:%M:%SZ")
    }
    -- Sử dụng HttpService:PostAsync cho HttpPost an toàn hơn (nếu có sẵn hoặc giả định môi trường hỗ trợ)
    pcall(function() HttpService:PostAsync(sheetURL, HttpService:JSONEncode(data), Enum.HttpContentType.ApplicationJson) end)
end

-- kiểm tra slot key
local function checkKeySlot()
    local responseSuccess, response = pcall(function()
        return game:HttpGet(sheetURL)
    end)

    if not responseSuccess then
        warn("[✘] Không thể truy cập SheetBest để kiểm tra slot key:", response)
        -- Cho phép người dùng tiếp tục nếu không thể kiểm tra slot để tránh bị kick oan
        -- Hoặc bạn có thể chọn kick người dùng nếu muốn bảo mật nghiêm ngặt hơn
        return true 
    end

    local dataSuccess, data = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if not dataSuccess or type(data) ~= "table" then
        warn("[✘] Lỗi phân tích phản hồi SheetBest:", data)
        return true -- Cho phép tiếp tục nếu dữ liệu không hợp lệ
    end

    local count = 0
    for _, row in pairs(data) do
        if row.key == inputKey and row.status == "online" then
            local success, lastPing = pcall(function()
                -- Đảm bảo định dạng thời gian phù hợp với os.time
                return os.time(os.date("!*t", os.time{year=tonumber(row.last_ping:sub(1,4)), month=tonumber(row.last_ping:sub(6,7)), day=tonumber(row.last_ping:sub(9,10)), hour=tonumber(row.last_ping:sub(12,13)), min=tonumber(row.last_ping:sub(15,16)), sec=tonumber(row.last_ping:sub(18,19))}))
            end)
            if success and os.time() - lastPing <= pingInterval * 2 then
                count = count + 1
            end
        end
    end
    return count < maxSlots
end

-- main
if checkKeySlot() then
    updateStatus(username, inputKey, "online")
    print("[✔] Key slot có sẵn. Bạn đang online.")

    spawn(function()
        while true do
            wait(pingInterval)
            updateStatus(username, inputKey, "online")
        end
    end)
else
    Players.LocalPlayer:Kick("Key của bạn hiện đã đạt giới hạn slot. Vui lòng chờ cho đến khi có slot trống.")
    return
end

-- tạo folder macro nếu chưa có
if not isfolder("tdx") then makefolder("tdx") end
if not isfolder(macroFolder) then makefolder(macroFolder) end

-- download macro file
local success, result = pcall(function()
    return game:HttpGet(jsonURL)
end)

if success then
    writefile(macroFile, result)
    print("[✔] Đã tải xuống tệp macro.")
else
    warn("[✘] Không thể tải xuống macro:", result)
    return
end

-- skip wave config
_G.WaveConfig = {
    ["WAVE 0"] = 0,
    ["WAVE 1"] = 444,
    ["WAVE 2"] = 44,
    ["WAVE 3"] = 44,
    ["WAVE 4"] = 44,
    ["WAVE 5"] = 44,
    ["WAVE 6"] = 44,
    ["WAVE 7"] = 44,
    ["WAVE 8"] = 44,
    ["WAVE 9"] = 44,
    ["WAVE 10"] = 44,
    ["WAVE 11"] = 44, 
    ["WAVE 12"] = 44, 
    ["WAVE 13"] = 44,
    ["WAVE 14"] = 144,
    ["WAVE 15"] = 44,
    ["WAVE 16"] = 120,
    ["WAVE 17"] = 44,
    ["WAVE 18"] = 44,
    ["WAVE 19"] = 44,
    ["WAVE 20"] = 144,
    ["WAVE 21"] = 44,
    ["WAVE 22"] = 144,
    ["WAVE 23"] = 144,
    ["WAVE 24"] = 44,
    ["WAVE 25"] = 44,
    ["WAVE 26"] = 44,
    ["WAVE 27"] = 44,
    ["WAVE 28"] = 144,
    ["WAVE 29"] = 20,
    ["WAVE 30"] = 200,
    ["WAVE 31"] = 120,
    ["WAVE 32"] = 20,
    ["WAVE 33"] = 120,
    ["WAVE 34"] = 230,
    ["WAVE 35"] = 0,
}

-- chạy loader & auto skip
loadstring(game:HttpGet(loaderURL))()
loadstring(game:HttpGet(skipWaveURL))()