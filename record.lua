local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

print("🔬 SkipWave Hook Test - Thử Tất Cả Phương Pháp")
print("="..string.rep("=", 50))

-- File output cho test
local outTxt = "tdx/macros/skipwave_test.txt"

-- Tạo thư mục
if makefolder then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

-- Xóa file cũ
if isfile and isfile(outTxt) and delfile then
    pcall(delfile, outTxt)
end

-- Hàm ghi file test
local function writeTest(method, data)
    local content = string.format("[%s] Method: %s | Data: %s\n", 
        os.date("%H:%M:%S"), method, tostring(data))
    
    if appendfile then
        pcall(appendfile, outTxt, content)
    elseif writefile then
        local existing = ""
        if isfile and isfile(outTxt) and readfile then
            existing = pcall(readfile, outTxt) and readfile(outTxt) or ""
        end
        pcall(writefile, outTxt, existing .. content)
    end
    
    print("📝 " .. content:gsub("\n", ""))
end

-- Lấy thông tin wave hiện tại
local function getCurrentWave()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return "Unknown" end
    
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return "Unknown" end
    
    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
    if not gameInfoBar then return "Unknown" end
    
    return gameInfoBar.Wave.WaveText.Text
end

print("🎯 Bắt đầu thiết lập các hook...")

--==============================================================================
--=                    PHƯƠNG PHÁP 1: HOOK TRỰC TIẾP REMOTE                    =
--==============================================================================

print("🔧 Method 1: Hook trực tiếp lên Remote")
pcall(function()
    local skipRemote = ReplicatedStorage:WaitForChild("Remotes", 5)
    if skipRemote then
        skipRemote = skipRemote:WaitForChild("SkipWaveVoteCast", 2)
        if skipRemote then
            local originalFireServer = skipRemote.FireServer
            
            skipRemote.FireServer = function(self, voteValue)
                writeTest("Method1-DirectRemote", string.format("Vote: %s (%s) | Wave: %s", 
                    tostring(voteValue), typeof(voteValue), getCurrentWave()))
                
                -- Gọi original
                return originalFireServer(self, voteValue)
            end
            
            print("✅ Method 1: Hook trực tiếp Remote - THÀNH CÔNG")
        else
            print("❌ Method 1: Không tìm thấy SkipWaveVoteCast remote")
        end
    else
        print("❌ Method 1: Không tìm thấy Remotes folder")
    end
end)

--==============================================================================
--=                    PHƯƠNG PHÁP 2: HOOKFUNCTION                             =
--==============================================================================

print("🔧 Method 2: HookFunction")
if hookfunction then
    pcall(function()
        local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
            if self.Name == "SkipWaveVoteCast" then
                local args = {...}
                writeTest("Method2-HookFunction", string.format("Args: %s | Wave: %s", 
                    HttpService:JSONEncode(args), getCurrentWave()))
            end
            return oldFireServer(self, ...)
        end)
        print("✅ Method 2: HookFunction - THÀNH CÔNG")
    end)
else
    print("❌ Method 2: HookFunction không khả dụng")
end

--==============================================================================
--=                    PHƯƠNG PHÁP 3: HOOKMETAMETHOD                           =
--==============================================================================

print("🔧 Method 3: HookMetamethod")
if hookmetamethod and checkcaller then
    pcall(function()
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
            if checkcaller() then return oldNamecall(self, ...) end
            
            local method = getnamecallmethod()
            if method == "FireServer" and self.Name == "SkipWaveVoteCast" then
                local args = {...}
                writeTest("Method3-HookMetamethod", string.format("Args: %s | Wave: %s", 
                    HttpService:JSONEncode(args), getCurrentWave()))
            end
            
            return oldNamecall(self, ...)
        end)
        print("✅ Method 3: HookMetamethod - THÀNH CÔNG")
    end)
else
    print("❌ Method 3: HookMetamethod hoặc checkcaller không khả dụng")
end

--==============================================================================
--=              PHƯƠNG PHÁP 4: MONITOR REMOTES FOLDER                         =
--==============================================================================

print("🔧 Method 4: Monitor Remotes Folder")
pcall(function()
    local function connectToRemote()
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        if remotes then
            local skipRemote = remotes:FindFirstChild("SkipWaveVoteCast")
            if skipRemote and skipRemote:IsA("RemoteEvent") then
                -- Thử hook OnClientEvent (nếu có response)
                skipRemote.OnClientEvent:Connect(function(...)
                    writeTest("Method4-OnClientEvent", string.format("Response: %s | Wave: %s", 
                        HttpService:JSONEncode({...}), getCurrentWave()))
                end)
                
                print("✅ Method 4: Monitor OnClientEvent - THÀNH CÔNG")
            end
        end
    end
    
    connectToRemote()
    
    -- Theo dõi khi remote được thêm
    ReplicatedStorage.DescendantAdded:Connect(function(child)
        if child.Name == "SkipWaveVoteCast" then
            task.wait(0.1)
            connectToRemote()
        end
    end)
end)

--==============================================================================
--=                    PHƯƠNG PHÁP 5: SIMULATE CLICK                           =
--==============================================================================

print("🔧 Method 5: Monitor UI Click")
pcall(function()
    local function findSkipButton()
        local playerGui = player:FindFirstChildOfClass("PlayerGui")
        if not playerGui then return end
        
        -- Tìm skip button trong UI
        for _, gui in ipairs(playerGui:GetDescendants()) do
            if gui:IsA("GuiButton") or gui:IsA("TextButton") then
                local text = gui.Text or ""
                if text:lower():find("skip") or gui.Name:lower():find("skip") then
                    
                    -- Hook vào MouseButton1Click
                    gui.MouseButton1Click:Connect(function()
                        writeTest("Method5-UIClick", string.format("Button: %s | Text: %s | Wave: %s", 
                            gui.Name, text, getCurrentWave()))
                    end)
                    
                    print("✅ Method 5: Tìm thấy skip button:", gui.Name)
                end
            end
        end
    end
    
    findSkipButton()
    
    -- Theo dõi khi UI thay đổi
    player:FindFirstChildOfClass("PlayerGui").DescendantAdded:Connect(function(child)
        if child:IsA("GuiButton") or child:IsA("TextButton") then
            task.wait(0.1)
            findSkipButton()
        end
    end)
end)

--==============================================================================
--=                    PHƯƠNG PHÁP 6: NETWORK MONITORING                       =
--==============================================================================

print("🔧 Method 6: Network Monitoring")
if getconnections then
    pcall(function()
        task.spawn(function()
            while task.wait(1) do
                local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                if remotes then
                    local skipRemote = remotes:FindFirstChild("SkipWaveVoteCast")
                    if skipRemote then
                        local connections = getconnections(skipRemote.OnClientEvent)
                        if #connections > 0 then
                            writeTest("Method6-NetworkMonitor", string.format("Connections: %d | Wave: %s", 
                                #connections, getCurrentWave()))
                        end
                    end
                end
            end
        end)
        print("✅ Method 6: Network Monitoring - THÀNH CÔNG")
    end)
else
    print("❌ Method 6: getconnections không khả dụng")
end

--==============================================================================
--=                    PHƯƠNG PHÁP 7: MANUAL TRIGGER                           =
--==============================================================================

print("🔧 Method 7: Manual Trigger Test")
print("📋 Để test manual, hãy chạy lệnh sau trong console:")
print('game:GetService("ReplicatedStorage").Remotes.SkipWaveVoteCast:FireServer(true)')

-- Tạo function để test manual
_G.testSkipWave = function()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        local skipRemote = remotes:FindFirstChild("SkipWaveVoteCast")
        if skipRemote then
            writeTest("Method7-ManualTrigger", string.format("Manual test | Wave: %s", getCurrentWave()))
            skipRemote:FireServer(true)
            print("🚀 Manual trigger sent!")
        else
            print("❌ SkipWaveVoteCast remote không tìm thấy")
        end
    else
        print("❌ Remotes folder không tìm thấy")
    end
end

print("💡 Chạy _G.testSkipWave() để test manual")

--==============================================================================
--=                         STATUS & MONITORING                               =
--==============================================================================

print("="..string.rep("=", 50))
print("🎯 TẤT CẢ HOOK ĐÃ ĐƯỢC THIẾT LẬP!")
print("📁 Log file: " .. outTxt)
print("🔍 Hãy thử skip wave và kiểm tra file log")
print("⏰ Monitoring bắt đầu...")

-- Monitor task
task.spawn(function()
    local lastWave = getCurrentWave()
    while task.wait(5) do
        local currentWave = getCurrentWave()
        if currentWave ~= lastWave then
            writeTest("WaveChange", string.format("Wave changed: %s -> %s", lastWave, currentWave))
            lastWave = currentWave
        end
    end
end)

print("✅ SkipWave Hook Test đã sẵn sàng!")
print("🎮 Hãy thử skip wave trong game và kiểm tra kết quả!")