local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- IP của điện thoại chạy Termux server Python
local logURL = "http://192.168.2.111:8080" -- thay bằng IP LAN điện thoại của bạn

-- hàm gửi log lên server
local function sendLog(status)
    local key = getgenv().TDX_Config.Key
    local data = {
        key = key,
        username = player.Name,
        status = status or "online"
    }
    local success, response = pcall(function()
        return HttpService:PostAsync(logURL, HttpService:JSONEncode(data), Enum.HttpContentType.ApplicationJson)
    end)
    if success then
        local resp = HttpService:JSONDecode(response)
        if resp.success == false and resp.msg == "key maxed" then
            player:Kick("key đã đạt max 5 acc")
        end
    end
end

-- vòng lặp update status mỗi 30 giây
spawn(function()
    repeat
        sendLog("online")
        wait(30)
    until false
end)

-- ví dụ: update status khác khi chơi
-- sendLog("busy") -- bạn có thể gọi khi cần