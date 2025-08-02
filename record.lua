local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

-- File output
local outJson = "tdx/macros/recorder_output.json"

-- Xóa file cũ nếu tồn tại
if isfile and isfile(outJson) and delfile then
    local ok, err = pcall(delfile, outJson)
    if not ok then
        warn("Không thể xóa file cũ: " .. tostring(err))
    end
end

local recordedActions = {}

-- Tạo thư mục nếu chưa tồn tại
if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

--==============================================================================
--=                           HÀM TIỆN ÍCH                                     =
--==============================================================================

-- Hàm ghi file an toàn
local function safeWriteFile(path, content)
    if writefile then
        local success, err = pcall(writefile, path, content)
        if not success then
            warn("Lỗi khi ghi file: " .. tostring(err))
        else
            print("✅ Đã ghi file:", path)
        end
    end
end

-- Lấy thông tin wave và thời gian hiện tại
local function getCurrentWaveAndTime()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil, nil end

    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return nil, nil end
    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
    if not gameInfoBar then return nil, nil end

    local wave = gameInfoBar.Wave.WaveText.Text
    local time = gameInfoBar.TimeLeft.TimeLeftText.Text
    return wave, time
end

-- Chuyển đổi chuỗi thời gian (vd: "1:23") thành số (vd: 123)
local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- Cập nhật file JSON
local function updateJsonFile()
    if not HttpService then return end
    local jsonLines = {}
    for i, entry in ipairs(recordedActions) do
        local ok, jsonStr = pcall(HttpService.JSONEncode, HttpService, entry)
        if ok then
            if i < #recordedActions then
                jsonStr = jsonStr .. ","
            end
            table.insert(jsonLines, jsonStr)
        end
    end
    local finalJson = "[\n" .. table.concat(jsonLines, "\n") .. "\n]"
    safeWriteFile(outJson, finalJson)
end

-- Parse TXT command thành JSON format
local function parseTxtToJson(txtCommand)
    -- Parse lệnh skip wave: "TDX:skipWave()"
    if txtCommand:match('TDX:skipWave%(%)') then
        local currentWave, currentTime = getCurrentWaveAndTime()
        return {
            SkipWhen = currentWave,
            SkipWave = tostring(convertTimeToNumber(currentTime))
        }
    end
    return nil
end

--==============================================================================
--=                      XỬ LÝ SKIP WAVE                                       =
--==============================================================================

-- Hook namecall để bắt Skip Wave
local function setupSkipWaveHook()
    if not hookmetamethod or not checkcaller then
        warn("Executor không hỗ trợ hook!")
        return
    end

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if checkcaller() then return oldNamecall(self, ...) end
        
        local method = getnamecallmethod()
        if method == "FireServer" then
            local args = {...}
            local remoteName = self.Name

            -- Debug: Log tất cả remote calls
            print("🔥 REMOTE:", remoteName, "| ARGS:", unpack(args))
            
            -- Xử lý Skip Wave
            if remoteName == "SkipWaveVoteCast" then
                local voteValue = args[1]
                print("🎯 SKIP WAVE DETECTED!")
                print("📋 Vote Value:", voteValue, "| Type:", typeof(voteValue))
                
                if typeof(voteValue) == "boolean" and voteValue == true then
                    -- Bước 1: Tạo TXT command và cache
                    local txtCommand = "TDX:skipWave()"
                    print("📝 TXT Command cached:", txtCommand)
                    
                    -- Bước 2: Delay parse sau khi server xử lý xong
                    task.spawn(function()
                        task.wait(0.1) -- Chờ server xử lý xong
                        
                        -- Parse TXT thành JSON format
                        local jsonEntry = parseTxtToJson(txtCommand)
                        if jsonEntry then
                            print("🌊 Parsing - Wave:", jsonEntry.SkipWhen, "| Time:", jsonEntry.SkipWave)
                            print("📋 JSON Entry:", HttpService:JSONEncode(jsonEntry))
                            
                            -- Ghi vào file JSON
                            table.insert(recordedActions, jsonEntry)
                            updateJsonFile()
                            print("✅ Skip Wave đã được ghi vào JSON!")
                        else
                            print("❌ Không thể parse TXT command")
                        end
                    end)
                else
                    print("❌ Vote value không hợp lệ")
                end
            end
        end
        
        -- Gửi server nguyên bản (server nhận TXT)
        return oldNamecall(self, ...)
    end)
    
    print("🎣 Skip Wave hook đã được thiết lập!")
end

--==============================================================================
--=                         KHỞI TẠO                                           =
--==============================================================================

setupSkipWaveHook()

print("✅ TDX Skip Wave Recorder đã hoạt động!")
print("📁 File output: " .. outJson)
print("🎯 Server nhận TXT, script ghi JSON")
print("🔍 Sẽ log tất cả remote calls để debug")