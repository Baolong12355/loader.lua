-- Script Auto Skip Wave hoàn chỉnh không giới hạn thời gian chờ
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Cấu hình hệ thống
local Config = {
    DelayKiemTra = 0.05,  -- Thời gian giữa các lần kiểm tra (giây)
    CheDoDebug = true     -- Hiển thị thông báo console
}

-- Kiểm tra config
if not _G.WaveConfig or type(_G.WaveConfig) ~= "table" then
    error("Vui lòng thêm _G.WaveConfig trước khi chạy script!")
end

-- Hàm hiển thị thông báo
local function debugPrint(...)
    if Config.CheDoDebug then
        print("[AUTO-SKIP]", ...)
    end
end

-- Hàm chờ vô hạn cho GameInfoBar
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

-- Lấy các thành phần UI cần thiết
local function initUI()
    local gameInfoBar = waitForGameInfoBar()
    
    return {
        waveText = gameInfoBar.Wave.WaveText,
        timeText = gameInfoBar.TimeLeft.TimeLeftText,
        skipEvent = ReplicatedStorage.Remotes.SkipWaveVoteCast
    }
end

-- Chuyển số thành chuỗi thời gian (ví dụ: 235 -> "02:35")
local function convertToTimeFormat(number)
    local mins = math.floor(number / 100)
    local secs = number % 100
    return string.format("%02d:%02d", mins, secs)
end

-- Hàm chính
local function main()
    debugPrint("Đang khởi động hệ thống auto skip...")
    
    local ui = initUI()
    
    while task.wait(Config.DelayKiemTra) do
        local waveName = ui.waveText.Text
        local currentTime = ui.timeText.Text
        local targetTime = _G.WaveConfig[waveName]
        
        if targetTime and targetTime > 0 then
            local targetTimeStr = convertToTimeFormat(targetTime)
            
            if currentTime == targetTimeStr then
                debugPrint("Đang skip wave:", waveName, "| Thời gian:", currentTime)
                ui.skipEvent:FireServer(true)
            end
        end
    end
end

-- Bắt đầu chương trình
main()
