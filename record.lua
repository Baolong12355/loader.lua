local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

print("🎯 Enhanced SkipWave Test - Safe Text Format")
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

-- Safe function để convert data thành text
local function safeDataToText(data)
    if data == nil then
        return "nil"
    elseif type(data) == "string" then
        return string.format('"%s"', data)
    elseif type(data) == "number" then
        return tostring(data)
    elseif type(data) == "boolean" then
        return tostring(data)
    elseif type(data) == "table" then
        local parts = {}
        for i, v in ipairs(data) do
            table.insert(parts, safeDataToText(v))
        end
        -- Nếu không có array elements, thử pairs
        if #parts == 0 then
            for k, v in pairs(data) do
                table.insert(parts, string.format("%s=%s", tostring(k), safeDataToText(v)))
            end
        end
        return string.format("{%s}", table.concat(parts, ", "))
    else
        return string.format("(%s: %s)", type(data), tostring(data))
    end
end

-- Safe function để convert args thành text
local function safeArgsToText(args)
    if not args or #args == 0 then
        return "(no args)"
    end
    
    local argTexts = {}
    for i, arg in ipairs(args) do
        table.insert(argTexts, safeDataToText(arg))
    end
    return table.concat(argTexts, ", ")
end

-- Xử lý skip wave với server response
local function handleSkipWave(method, args, serverResponse)
    skipCount = skipCount + 1
    local wave = getCurrentWave()
    local time = getCurrentTime()
    local timeNumber = convertTimeToNumber(time)
    
    print(string.format("🚀 [%s] SKIP WAVE #%d", method, skipCount))
    print(string.format("   📊 Wave: %s | Time: %s (%s)", wave, time, timeNumber or "N/A"))
    print(string.format("   📋 Args: %s", safeArgsToText(args)))
    
    -- Hiển thị server response nếu có
    if serverResponse ~= nil then
        local responseText = safeDataToText(serverResponse)
        print(string.format("   🌐 Server Response: %s", responseText))
        print(string.format("   📡 Response Type: %s", type(serverResponse)))
        
        -- Lưu response để phân tích
        table.insert(serverResponses, {
            count = skipCount,
            wave = wave,
            time = time,
            timeNumber = timeNumber,
            args = args,
            response = serverResponse,
            responseText = responseText,
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
    local success = pcall(function()
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
    
    if not success then
        print("❌ FireServer Hook - THẤT BẠI")
    end
else
    print("❌ hookfunction không khả dụng cho FireServer")
end

--==============================================================================
--=                        HOOK INVOKESERVER                                   =
--==============================================================================

print("🔧 Thiết lập Hook cho InvokeServer (RemoteFunction)")
if hookfunction then
    local success = pcall(function()
        local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
            -- Chỉ xử lý nếu có RemoteFunction tên SkipWaveVoteCast
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
    
    if not success then
        print("❌ InvokeServer Hook - THẤT BẠI")
    end
else
    print("❌ hookfunction không khả dụng cho InvokeServer")
end

--==============================================================================
--=                       HOOK METAMETHOD                                      =
--==============================================================================

print("🔧 Thiết lập Hook cho __namecall")
if hookmetamethod and checkcaller then
    local success = pcall(function()
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
    
    if not success then
        print("❌ Namecall Hook - THẤT BẠI")
    end
else
    print("❌ hookmetamethod hoặc checkcaller không khả dụng")
end

--==============================================================================
--=                      HOOK CLIENT EVENTS                                    =
--==============================================================================

print("🔧 Thiết lập Hook cho Client Events")
local function setupClientEventHooks()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        print("❌ Remotes folder không tìm thấy")
        return
    end
    
    local hookedEvents = 0
    
    -- Tìm các event có thể liên quan đến skip wave response
    for _, remote in pairs(remotes:GetChildren()) do
        if remote:IsA("RemoteEvent") then
            local name = remote.Name:lower()
            if string.find(name, "skip") or 
               string.find(name, "wave") or
               string.find(name, "vote") or
               string.find(name, "cast") or
               string.find(name, "result") then
                
                local success = pcall(function()
                    remote.OnClientEvent:Connect(function(...)
                        local args = {...}
                        local argsText = safeArgsToText(args)
                        
                        print(string.format("📡 Client Event [%s]: %s", remote.Name, argsText))
                        
                        -- Lưu event data
                        table.insert(serverResponses, {
                            type = "ClientEvent",
                            remoteName = remote.Name,
                            data = args,
                            dataText = argsText,
                            timestamp = tick()
                        })
                    end)
                    hookedEvents = hookedEvents + 1
                    print(string.format("✅ Đã hook client event: %s", remote.Name))
                end)
                
                if not success then
                    print(string.format("❌ Không thể hook event: %s", remote.Name))
                end
            end
        end
    end
    
    print(string.format("📊 Đã hook %d client events", hookedEvents))
end

setupClientEventHooks()

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
        if response.count then
            print(string.format("   Count: %s", response.count))
            print(string.format("   Wave: %s", response.wave or "N/A"))
            print(string.format("   Time: %s", response.time or "N/A"))
            print(string.format("   Type: Skip"))
        else
            print(string.format("   Type: %s", response.type or "Unknown"))
            print(string.format("   Remote: %s", response.remoteName or "N/A"))
        end
        
        if response.responseText then
            print(string.format("   Data: %s", response.responseText))
        elseif response.dataText then
            print(string.format("   Data: %s", response.dataText))
        else
            print("   Data: (No data)")
        end
        print("")
    end
end

-- Function để clear responses
_G.clearResponses = function()
    serverResponses = {}
    skipCount = 0
    print("🗑️ Đã xóa tất cả responses và reset counter")
end

-- Function để test với các arguments khác nhau
_G.testSkipVariations = function()
    print("")
    print("🧪 TESTING SKIP VARIATIONS...")
    print("="..string.rep("-", 30))
    
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        print("❌ Remotes folder không tìm thấy")
        return
    end
    
    local skipRemote = remotes:FindFirstChild("SkipWaveVoteCast")
    if not skipRemote then
        print("❌ SkipWaveVoteCast remote không tìm thấy")
        return
    end
    
    local tests = {
        {name = "Vote True", args = {true}},
        {name = "Vote False", args = {false}},
        {name = "String True", args = {"true"}},
        {name = "Number 1", args = {1}},
        {name = "Number 0", args = {0}},
        {name = "No Args", args = {}},
    }
    
    for i, test in ipairs(tests) do
        print(string.format("📤 Test %d: %s - Args: %s", i, test.name, safeArgsToText(test.args)))
        
        local success = pcall(function()
            if #test.args == 0 then
                skipRemote:FireServer()
            else
                skipRemote:FireServer(unpack(test.args))
            end
        end)
        
        if success then
            print("   ✅ Gửi thành công")
        else
            print("   ❌ Gửi thất bại")
        end
        
        task.wait(0.2) -- Ngắt giữa các test
    end
    
    print("✅ Hoàn thành tất cả test variations!")
    print("")
end

--==============================================================================
--=                         REMOTE ANALYSIS                                    =
--==============================================================================

print("🔍 Phân tích RemoteEvents và RemoteFunctions...")
local function analyzeRemotes()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        print("❌ Không tìm thấy Remotes folder")
        return
    end
    
    local skipRelated = {}
    local allRemotes = {}
    
    for _, remote in pairs(remotes:GetChildren()) do
        table.insert(allRemotes, {
            Name = remote.Name,
            Type = remote.ClassName
        })
        
        local name = remote.Name:lower()
        if string.find(name, "skip") or 
           string.find(name, "wave") or 
           string.find(name, "vote") or
           string.find(name, "cast") or
           string.find(name, "result") then
            table.insert(skipRelated, {
                Name = remote.Name,
                Type = remote.ClassName
            })
        end
    end
    
    print(string.format("📊 Tổng cộng: %d remotes", #allRemotes))
    
    if #skipRelated > 0 then
        print("🎯 Tìm thấy các remote liên quan đến skip/wave/vote:")
        for _, remote in ipairs(skipRelated) do
            print(string.format("   📡 %s (%s)", remote.Name, remote.Type))
        end
    else
        print("❌ Không tìm thấy remote nào liên quan đến skip/wave/vote")
        print("📋 Tất cả remotes:")
        for _, remote in ipairs(allRemotes) do
            print(string.format("   📡 %s (%s)", remote.Name, remote.Type))
        end
    end
end

analyzeRemotes()

print("="..string.rep("=", 50))
print("✅ Enhanced SkipWave Test (Safe Format) đã sẵn sàng!")
print("🎮 Commands:")
print("   _G.testSkipWave() - Test manual cơ bản")
print("   _G.testSkipVariations() - Test nhiều variations")
print("   _G.showResponses() - Xem tất cả responses")
print("   _G.clearResponses() - Clear data")
print("📊 Script sẽ hiển thị chi tiết server response (safe text format)")
print("")