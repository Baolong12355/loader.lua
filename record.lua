local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

print("🎯 Enhanced SkipWave Test - With Server Response")
print("="..string.rep("=", 50))

-- Biến để track
local skipCount = 0
local serverResponses = {}

-- Lấy wave hiện tại
local function getCurrentWave()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return "Unknown" end
    
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return "Unknown" end
    
    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
    if not gameInfoBar then return "Unknown" end
    
    return gameInfoBar.Wave.WaveText.Text
end

-- Lấy thời gian hiện tại
local function getCurrentTime()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return "Unknown" end
    
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return "Unknown" end
    
    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
    if not gameInfoBar then return "Unknown" end
    
    return gameInfoBar.TimeLeft.TimeLeftText.Text
end

-- Chuyển đổi time string thành number
local function convertTimeToNumber(timeStr)
    if not timeStr then return nil end
    local mins, secs = timeStr:match("(%d+):(%d+)")
    if mins and secs then
        return tonumber(mins) * 100 + tonumber(secs)
    end
    return nil
end

-- Xử lý skip wave với server response
local function handleSkipWave(method, args, serverResponse)
    skipCount = skipCount + 1
    local wave = getCurrentWave()
    local time = getCurrentTime()
    local timeNumber = convertTimeToNumber(time)
    
    print(string.format("🚀 [%s] SKIP WAVE #%d", method, skipCount))
    print(string.format("   📊 Wave: %s | Time: %s (%s)", wave, time, timeNumber or "N/A"))
    print(string.format("   📋 Args: %s", HttpService:JSONEncode(args)))
    
    -- Hiển thị server response nếu có
    if serverResponse ~= nil then
        print(string.format("   🌐 Server Response: %s", tostring(serverResponse)))
        print(string.format("   📡 Response Type: %s", type(serverResponse)))
        
        -- Nếu response là table, hiển thị chi tiết
        if type(serverResponse) == "table" then
            local success, jsonStr = pcall(HttpService.JSONEncode, HttpService, serverResponse)
            if success then
                print(string.format("   📦 Response JSON: %s", jsonStr))
            end
        end
        
        -- Lưu response để phân tích
        table.insert(serverResponses, {
            count = skipCount,
            wave = wave,
            time = time,
            timeNumber = timeNumber,
            args = args,
            response = serverResponse,
            timestamp = tick()
        })
    else
        print("   🌐 Server Response: (No response - FireServer)")
    end
    
    print(string.format("   🕐 Timestamp: %s", os.date("%H:%M:%S")))
    print("")
    
    -- Tạo command format TDX với thông tin chi tiết
    local command = "TDX:skipWave()"
    print(string.format("   💾 Command: %s", command))
    
    -- Thêm thông tin cho macro format
    if timeNumber then
        print(string.format("   📝 Macro Format: SkipWhen=%s, SkipWave=%s", wave, timeNumber))
    end
    print("")
end

--==============================================================================
--=                         HOOK FIRESERVER                                    =
--==============================================================================

print("🔧 Thiết lập Hook cho FireServer (RemoteEvent)")
if hookfunction then
    pcall(function()
        local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
            -- Chỉ xử lý SkipWaveVoteCast
            if self.Name == "SkipWaveVoteCast" then
                local args = {...}
                handleSkipWave("FireServer-Hook", args, nil) -- FireServer không có return value
            end
            
            -- Gọi original function
            return oldFireServer(self, ...)
        end)
        print("✅ FireServer Hook - THÀNH CÔNG")
    end)
else
    print("❌ hookfunction không khả dụng cho FireServer")
end

--==============================================================================
--=                        HOOK INVOKESERVER                                   =
--==============================================================================

print("🔧 Thiết lập Hook cho InvokeServer (RemoteFunction)")
if hookfunction then
    pcall(function()
        local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
            -- Chỉ xử lý nếu có RemoteFunction tên SkipWaveVoteCast (ít khả năng)
            if self.Name == "SkipWaveVoteCast" then
                local args = {...}
                local result = oldInvokeServer(self, ...)
                handleSkipWave("InvokeServer-Hook", args, result)
                return result
            end
            
            -- Gọi original function cho các remote khác
            return oldInvokeServer(self, ...)
        end)
        print("✅ InvokeServer Hook - THÀNH CÔNG")
    end)
else
    print("❌ hookfunction không khả dụng cho InvokeServer")
end

--==============================================================================
--=                       HOOK METAMETHOD                                      =
--==============================================================================

print("🔧 Thiết lập Hook cho __namecall")
if hookmetamethod and checkcaller then
    pcall(function()
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            -- Bỏ qua nếu là internal call
            if checkcaller() then return oldNamecall(self, ...) end
            
            local method = getnamecallmethod()
            
            -- Xử lý FireServer
            if method == "FireServer" and self.Name == "SkipWaveVoteCast" then
                local args = {...}
                handleSkipWave("Namecall-FireServer", args, nil)
            
            -- Xử lý InvokeServer (nếu có)
            elseif method == "InvokeServer" and self.Name == "SkipWaveVoteCast" then
                local args = {...}
                local result = oldNamecall(self, ...)
                handleSkipWave("Namecall-InvokeServer", args, result)
                return result
            end
            
            -- Gọi original function
            return oldNamecall(self, ...)
        end)
        print("✅ Namecall Hook - THÀNH CÔNG")
    end)
else
    print("❌ hookmetamethod hoặc checkcaller không khả dụng")
end

--==============================================================================
--=                      HOOK CLIENT EVENTS                                    =
--==============================================================================

print("🔧 Thiết lập Hook cho Client Events")
pcall(function()
    -- Hook sự kiện có thể liên quan đến skip wave
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        -- Tìm các event có thể liên quan đến skip wave response
        for _, remote in pairs(remotes:GetChildren()) do
            if remote:IsA("RemoteEvent") and 
               (string.find(remote.Name:lower(), "skip") or 
                string.find(remote.Name:lower(), "wave") or
                string.find(remote.Name:lower(), "vote")) then
                
                pcall(function()
                    remote.OnClientEvent:Connect(function(...)
                        local args = {...}
                        print(string.format("📡 Client Event [%s]: %s", 
                              remote.Name, 
                              HttpService:JSONEncode(args)))
                        
                        -- Lưu event data
                        table.insert(serverResponses, {
                            type = "ClientEvent",
                            remoteName = remote.Name,
                            data = args,
                            timestamp = tick()
                        })
                    end)
                    print(string.format("✅ Đã hook client event: %s", remote.Name))
                end)
            end
        end
    end
end)

--==============================================================================
--=                         MANUAL TEST FUNCTIONS                              =
--==============================================================================

-- Test function với detailed logging
_G.testSkipWave = function()
    print("")
    print("🧪 MANUAL TEST: Gửi SkipWaveVoteCast...")
    print("="..string.rep("-", 30))
    
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local skipRemote = remotes:FindFirstChild("SkipWaveVoteCast")
        if skipRemote then
            local beforeWave = getCurrentWave()
            local beforeTime = getCurrentTime()
            
            print(string.format("📊 Trước khi skip - Wave: %s, Time: %s", beforeWave, beforeTime))
            
            -- Test với vote = true
            print("📤 Gửi vote = true...")
            skipRemote:FireServer(true)
            
            -- Chờ một chút để xem response
            task.wait(0.5)
            
            local afterWave = getCurrentWave()
            local afterTime = getCurrentTime()
            print(string.format("📊 Sau khi skip - Wave: %s, Time: %s", afterWave, afterTime))
            
            print("✅ Manual test hoàn thành!")
        else
            print("❌ SkipWaveVoteCast remote không tìm thấy")
        end
    else
        print("❌ Remotes folder không tìm thấy")
    end
    print("")
end

-- Function để xem tất cả responses đã thu thập
_G.showResponses = function()
    print("")
    print("📊 TẤT CẢ SERVER RESPONSES:")
    print("="..string.rep("=", 40))
    
    if #serverResponses == 0 then
        print("❌ Chưa có response nào được ghi nhận")
        return
    end
    
    for i, response in ipairs(serverResponses) do
        print(string.format("📦 Response #%d:", i))
        print(string.format("   Count: %s", response.count or "N/A"))
        print(string.format("   Wave: %s", response.wave or "N/A"))
        print(string.format("   Time: %s", response.time or "N/A"))
        print(string.format("   Type: %s", response.type or "Skip"))
        print(string.format("   Data: %s", HttpService:JSONEncode(response.response or response.data)))
        print("")
    end
end

-- Function để clear responses
_G.clearResponses = function()
    serverResponses = {}
    skipCount = 0
    print("🗑️ Đã xóa tất cả responses và reset counter")
end

--==============================================================================
--=                         REMOTE ANALYSIS                                    =
--==============================================================================

print("🔍 Phân tích RemoteEvents và RemoteFunctions...")
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if remotes then
    local skipRelated = {}
    for _, remote in pairs(remotes:GetChildren()) do
        local name = remote.Name:lower()
        if string.find(name, "skip") or string.find(name, "wave") or string.find(name, "vote") then
            table.insert(skipRelated, {
                Name = remote.Name,
                Type = remote.ClassName
            })
        end
    end
    
    if #skipRelated > 0 then
        print("🎯 Tìm thấy các remote liên quan đến skip/wave/vote:")
        for _, remote in ipairs(skipRelated) do
            print(string.format("   📡 %s (%s)", remote.Name, remote.Type))
        end
    else
        print("❌ Không tìm thấy remote nào liên quan đến skip/wave/vote")
    end
else
    print("❌ Không tìm thấy Remotes folder")
end

print("="..string.rep("=", 50))
print("✅ Enhanced SkipWave Test đã sẵn sàng!")
print("🎮 Commands:")
print("   _G.testSkipWave() - Test manual")
print("   _G.showResponses() - Xem tất cả responses")
print("   _G.clearResponses() - Clear data")
print("📊 Script sẽ hiển thị chi tiết server response khi bắt được skip wave")
print("")