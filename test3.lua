local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Cấu hình hệ thống
local Config = {
    CheDoDebug = true -- hiển thị log debug
}

-- Kiểm tra _G.WaveConfig
if not _G.WaveConfig or type(_G.WaveConfig) ~= "table" then
    error("Vui lòng gán bảng _G.WaveConfig trước khi chạy script!")
end

-- Hàm in debug
local function debugPrint(...)
    if Config.CheDoDebug then
        print("[AUTO-SKIP]", ...)
    end
end

-- Tham chiếu đến RemoteEvent
local SkipEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SkipWaveVoteCast")
local TDX_Shared = ReplicatedStorage:WaitForChild("TDX_Shared")
local Common = TDX_Shared:WaitForChild("Common")
local NetworkingHandler = require(Common:WaitForChild("NetworkingHandler"))

-- Lắng nghe khi server cho phép vote skip
NetworkingHandler.GetEvent("SkipWaveVoteStateUpdate"):AttachCallback(function(data)
    if not data.VotingEnabled then return end

    local waveText = PlayerGui.Interface.GameInfoBar.Wave.WaveText.Text
    local waveName = string.upper(waveText) -- chuẩn hóa WAVE

    local configValue = _G.WaveConfig[waveName]

    if configValue == 0 then
        debugPrint("Wave", waveName, "không skip (cấu hình 0).")
        return
    end

    if configValue == "now" or configValue == "i" then
        debugPrint("Skip wave ngay lập tức:", waveName)
        SkipEvent:FireServer(true)
    elseif tonumber(configValue) then
        -- Convert số thành "mm:ss"
        local number = tonumber(configValue)
        local mins = math.floor(number / 100)
        local secs = number % 100
        local targetTimeStr = string.format("%02d:%02d", mins, secs)

        local currentTime = PlayerGui.Interface.GameInfoBar.TimeLeft.TimeLeftText.Text
        if currentTime == targetTimeStr then
            debugPrint("Đang skip wave:", waveName, "| Thời gian:", currentTime)
            SkipEvent:FireServer(true)
        end
    else
        debugPrint("Cảnh báo: giá trị không hợp lệ cho wave", waveName)
    end
end)

debugPrint("Auto Skip đã sẵn sàng!")