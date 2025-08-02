local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

print("🎯 TDX SkipWave Hook - Advanced Analysis")
print("="..string.rep("=", 50))

-- Biến để track
local skipCount = 0
local serverResponses = {}
local bindevents = {}

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
end

--==============================================================================
--=                       HOOK TDX BINDABLE EVENTS                            =
--==============================================================================

print("🔧 Hooking TDX BindableEvents...")

-- Tìm BindableHandler trong TDX_Shared
local function hookBindableEvents()
    local tdxShared = ReplicatedStorage:FindFirstChild("TDX_Shared")
    if not tdxShared then
        print("❌ TDX_Shared không tìm thấy")
        return
    end
    
    local common = tdxShared:FindFirstChild("Common")
    if not common then
        print("❌ Common folder không tìm thấy")
        return
    end
    
    local bindableHandlerModule = common:FindFirstChild("BindableHandler")
    if not bindableHandlerModule then
        print("❌ BindableHandler module không tìm thấy")
        return
    end
    
    print("✅ Tìm thấy BindableHandler module")
    
    -- Hook các bindable events liên quan đến skip wave
    local skipRelatedEvents = {
        "SkipWaveVote",
        "SkipWaveVoteCast", 
        "SkipWave",
        "VoteSkip",
        "WaveSkip",
        "CastSkipVote",
        "VoteCast"
    }
    
    for _, eventName in ipairs(skipRelatedEvents) do
        local success = pcall(function()
            local bindableHandler = require(bindableHandlerModule)
            if bindableHandler and bindableHandler.GetEvent then
                local event = bindableHandler.GetEvent(eventName)
                if event then
                    event:Connect(function(...)
                        local args = {...}
                        print(string.format("📡 BindableEvent [%s]: %s", eventName, safeArgsToText(args)))
                        
                        table.insert(serverResponses, {
                            type = "BindableEvent",
                            eventName = eventName,
                            data = args,
                            dataText = safeArgsToText(args),
                            timestamp = tick()
                        })
                    end)
                    print(string.format("✅ Hooked BindableEvent: %s", eventName))
                    bindevents[eventName] = event
                end
            end
        end)
        
        if not success then
            print(string.format("❌ Không thể hook BindableEvent: %s", eventName))
        end
    end
end

hookBindableEvents()

--==============================================================================
--=                         HOOK REMOTES                                      =
--==============================================================================

print("🔧 Thiết lập Hook cho RemoteEvents...")

-- Hook FireServer
if hookfunction then
    local success = pcall(function()
        local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
            local name = self.Name:lower()
            if string.find(name, "skip") or string.find(name, "wave") or string.find(name, "vote") then
                local args = {...}
                handleSkipWave("FireServer-" .. self.Name, args, nil)
            end
            
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

-- Hook InvokeServer  
if hookfunction then
    local success = pcall(function()
        local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
            local name = self.Name:lower()
            if string.find(name, "skip") or string.find(name, "wave") or string.find(name, "vote") then
                local args = {...}
                local result = oldInvokeServer(self, ...)
                handleSkipWave("InvokeServer-" .. self.Name, args, result)
                return result
            end
            
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

-- Hook __namecall
if hookmetamethod and checkcaller then
    local success = pcall(function()
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            if checkcaller() then return oldNamecall(self, ...) end
            
            local method = getnamecallmethod()
            
            if (method == "FireServer" or method == "InvokeServer") and self.Name then
                local name = self.Name:lower()
                if string.find(name, "skip") or string.find(name, "wave") or string.find(name, "vote") then
                    local args = {...}
                    
                    if method == "InvokeServer" then
                        local result = oldNamecall(self, ...)
                        handleSkipWave("Namecall-" .. method .. "-" .. self.Name, args, result)
                        return result
                    else
                        handleSkipWave("Namecall-" .. method .. "-" .. self.Name, args, nil)
                    end
                end
            end
            
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
--=                      HOOK CLIENT EVENTS                                   =
--==============================================================================

print("🔧 Thiết lập Hook cho Client Events...")
local function setupClientEventHooks()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        print("❌ Remotes folder không tìm thấy")
        return
    end
    
    local hookedEvents = 0
    
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
--=                         HOOK USERINPUTSERVICE                             =
--==============================================================================

print("🔧 Hooking UserInputService...")

-- Hook input began
local function hookUserInput()
    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        
        -- Kiểm tra phím skip wave (thường là Enter hoặc Space)
        if input.KeyCode == Enum.KeyCode.Return or 
           input.KeyCode == Enum.KeyCode.KeypadEnter or
           input.KeyCode == Enum.KeyCode.Space then
            
            print(string.format("⌨️ Skip key pressed: %s", input.KeyCode.Name))
            
            -- Thử tìm skip wave interface
            local playerGui = player:FindFirstChildOfClass("PlayerGui")
            if playerGui then
                local interface = playerGui:FindFirstChild("Interface")
                if interface then
                    -- Tìm nút skip wave
                    local function findSkipButton(parent)
                        for _, child in pairs(parent:GetDescendants()) do
                            if child:IsA("TextButton") or child:IsA("ImageButton") then
                                local text = child.Text or ""
                                if string.find(text:lower(), "skip") or string.find(text:lower(), "vote") then
                                    print(string.format("🎯 Found skip button: %s", child:GetFullName()))
                                    return child
                                end
                            end
                        end
                    end
                    
                    local skipButton = findSkipButton(interface)
                    if skipButton then
                        print("🖱️ Simulating skip button click...")
                        skipButton.MouseButton1Click:Fire()
                    end
                end
            end
        end
    end)
    
    print("✅ UserInputService hooks đã thiết lập")
end

hookUserInput()

--==============================================================================
--=                         TEST FUNCTIONS                                    =
--==============================================================================

-- Test function với BindableEvent
_G.testSkipWave = function()
    print("")
    print("🧪 MANUAL TEST: Test BindableEvents...")
    print("="..string.rep("-", 30))
    
    -- Test với các BindableEvents đã hook
    for eventName, event in pairs(bindevents) do
        print(string.format("🔥 Testing BindableEvent: %s", eventName))
        
        local success = pcall(function()
            event:Fire(true) -- Test với vote = true
        end)
        
        if success then
            print(string.format("   ✅ %s - Fire thành công", eventName))
        else
            print(string.format("   ❌ %s - Fire thất bại", eventName))
        end
        
        task.wait(0.1)
    end
    
    -- Test với remotes
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        for _, remote in pairs(remotes:GetChildren()) do
            local name = remote.Name:lower()
            if string.find(name, "skip") or string.find(name, "wave") or string.find(name, "vote") then
                print(string.format("🔥 Testing Remote: %s", remote.Name))
                
                local success = pcall(function()
                    if remote:IsA("RemoteEvent") then
                        remote:FireServer(true)
                    elseif remote:IsA("RemoteFunction") then
                        remote:InvokeServer(true)
                    end
                end)
                
                if success then
                    print(string.format("   ✅ %s - Gửi thành công", remote.Name))
                else
                    print(string.format("   ❌ %s - Gửi thất bại", remote.Name))
                end
                
                task.wait(0.1)
            end
        end
    end
    
    print("✅ Manual test hoàn thành!")
    print("")
end

-- Function để xem tất cả responses đã thu thập
_G.showResponses = function()
    print("")
    print("📊 TẤT CẢ RESPONSES:")
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
            if response.remoteName then
                print(string.format("   Remote: %s", response.remoteName))
            elseif response.eventName then
                print(string.format("   Event: %s", response.eventName))
            end
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

-- Function để force skip wave
_G.forceSkipWave = function()
    print("🔥 FORCE SKIP WAVE...")
    
    -- Thử tất cả các methods có thể
    local methods = {
        {name = "BindableEvent", func = function()
            for eventName, event in pairs(bindevents) do
                pcall(function() event:Fire(true) end)
            end
        end},
        {name = "Remote", func = function()
            local remotes = ReplicatedStorage:FindFirstChild("Remotes")
            if remotes then
                for _, remote in pairs(remotes:GetChildren()) do
                    local name = remote.Name:lower()
                    if string.find(name, "skip") or string.find(name, "wave") or string.find(name, "vote") then
                        pcall(function()
                            if remote:IsA("RemoteEvent") then
                                remote:FireServer(true)
                            end
                        end)
                    end
                end
            end
        end},
        {name = "GUI Button", func = function()
            local playerGui = player:FindFirstChildOfClass("PlayerGui")
            if playerGui then
                for _, child in pairs(playerGui:GetDescendants()) do
                    if child:IsA("TextButton") and child.Text and 
                       string.find(child.Text:lower(), "skip") then
                        pcall(function() child.MouseButton1Click:Fire() end)
                    end
                end
            end
        end}
    }
    
    for _, method in ipairs(methods) do
        print(string.format("🎯 Trying method: %s", method.name))
        pcall(method.func)
        task.wait(0.1)
    end
    
    print("✅ Force skip attempts completed!")
end

--==============================================================================
--=                         ANALYSIS & INFO                                   =
--==============================================================================

print("🔍 Analyzing TDX Structure...")
local function analyzeTDXStructure()
    local results = {}
    
    -- Check TDX_Shared
    local tdxShared = ReplicatedStorage:FindFirstChild("TDX_Shared")
    if tdxShared then
        results.tdxShared = true
        print("✅ TDX_Shared found")
        
        local common = tdxShared:FindFirstChild("Common")
        if common then
            results.common = true
            print("✅ Common folder found")
            
            for _, child in pairs(common:GetChildren()) do
                if child.Name:find("Handler") then
                    print(string.format("   📦 Handler: %s", child.Name))
                end
            end
        end
    end
    
    -- Check Remotes
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        results.remotes = {}
        print("📡 Remotes found:")
        
        for _, remote in pairs(remotes:GetChildren()) do
            local name = remote.Name:lower()
            if string.find(name, "skip") or string.find(name, "wave") or string.find(name, "vote") then
                table.insert(results.remotes, {name = remote.Name, type = remote.ClassName})
                print(string.format("   🎯 %s (%s)", remote.Name, remote.ClassName))
            end
        end
    end
    
    return results
end

local analysis = analyzeTDXStructure()

print("="..string.rep("=", 50))
print("✅ TDX SkipWave Hook đã sẵn sàng!")
print("🎮 Commands:")
print("   _G.testSkipWave() - Test tất cả methods")
print("   _G.forceSkipWave() - Force skip với tất cả methods")
print("   _G.showResponses() - Xem tất cả responses")
print("   _G.clearResponses() - Clear data")
print("📊 Script sẽ capture skip wave từ mọi nguồn có thể!")
print("⌨️ Nhấn Enter/Space để thử skip wave")
print("")