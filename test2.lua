-- cấu hình
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- thay bằng IP LAN của điện thoại chạy Termux
local logURL = "http://192.168.2.111:8080"

-- kiểm tra config
local inputKey = getgenv().TDX_Config and getgenv().TDX_Config.Key
if not inputKey or inputKey == "" then
    warn("[✘] chưa cấu hình getgenv().TDX_Config.Key")
    return
end

-- hàm gửi log lên server
local function sendLog(status)
    local data = {
        key = inputKey,
        username = player.Name,
        status = status or "online"
    }

    local success, response = pcall(function()
        return HttpService:PostAsync(
            logURL,
            HttpService:JSONEncode(data),
            Enum.HttpContentType.ApplicationJson
        )
    end)

    if success then
        local resp = HttpService:JSONDecode(response)
        if not resp.success then
            if resp.msg == "key maxed" then
                player:Kick("key đã đạt giới hạn người dùng (5 acc)")
            elseif resp.msg == "invalid key" then
                player:Kick("key không hợp lệ (không có trong danh sách)")
            else
                warn("[✘] lỗi server: "..tostring(resp.msg))
            end
        end
    else
        warn("[✘] không thể kết nối tới server log: "..tostring(response))
    end
end

-- gửi log ban đầu
sendLog("online")

-- cập nhật trạng thái mỗi 30s
task.spawn(function()
    while true do
        sendLog("online")
        task.wait(30)
    end
end)