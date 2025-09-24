local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Cấu hình hệ thống
local Config = {
    DelayKiemTra = 0.05, -- thời gian chờ giữa mỗi lần kiểm tra (giây)
    CheDoDebug = true
}

-- Kiểm tra xem _G.WaveConfig đã được cấu hình chưa
if not _G.WaveConfig or type(_G.WaveConfig) ~= "table" then
    error("Vui lòng gán bảng _G.WaveConfig trước khi chạy script!")
end

-- Hàm in debug
local function debugPrint(...)
    if Config.CheDoDebug then
        print("[AUTO-SKIP]", ...)
    end
end

-- Chờ GameInfoBar xuất hiện (vô hạn)
local function waitForGameInfoBar()
    debugPrint("Đang chờ GameInfoBar...")
    while true do
        local interface = PlayerGui:FindFirstChild("Interface")
        if interface then
            local gameInfoBar = interface:FindFirstChild("GameInfoBar")
            if gameInfoBar then
                debugPrint("Đã tìm thấy GameInfoBar!")
                return gameInfoBar
            end
        end
        task.wait(1)
    end
end

-- Khởi tạo UI
local function initUI()
    local gameInfoBar = waitForGameInfoBar()
    return {
        waveText = gameInfoBar.Wave.WaveText,
        timeText = gameInfoBar.TimeLeft.TimeLeftText,
        skipEvent = ReplicatedStorage.Remotes.SkipWaveVoteCast
    }
end

-- Chuyển số thành chuỗi thời gian "mm:ss"
local function convertToTimeFormat(number)
    local mins = math.floor(number / 100)
    local secs = number % 100
    return string.format("%02d:%02d", mins, secs)
end

-- Hàm chính
local function main()
    debugPrint("Khởi động Auto Skip...")
    local ui = initUI()
    local skippedWaves = {}

    while task.wait(Config.DelayKiemTra) do
        local waveName = ui.waveText.Text
        local currentTime = ui.timeText.Text
        local configValue = _G.WaveConfig[waveName]

        if configValue ~= nil and not skippedWaves[waveName] then
            -- Không skip nếu giá trị là 0
            if configValue == 0 then
                skippedWaves[waveName] = true
                debugPrint("Wave", waveName, "được cấu hình KHÔNG skip.")
            elseif tostring(configValue) == "now" or tostring(configValue) == "i" then
                -- Skip ngay lập tức nếu là "now" hoặc "i"
                debugPrint("Skip wave ngay lập tức:", waveName)
                ui.skipEvent:FireServer(true)
                skippedWaves[waveName] = true
            elseif tonumber(configValue) then
                -- Skip khi đến đúng thời gian chỉ định
                local targetTimeStr = convertToTimeFormat(tonumber(configValue))
                if currentTime == targetTimeStr then
                    debugPrint("Đang skip wave:", waveName, "| Thời gian:", currentTime)
                    ui.skipEvent:FireServer(true)
                    skippedWaves[waveName] = true
                end
            else
                debugPrint("Cảnh báo: giá trị không hợp lệ cho wave", waveName)
                skippedWaves[waveName] = true
            end
        end
    end
end

-- Chạy
main()