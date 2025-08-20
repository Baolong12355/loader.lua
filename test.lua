-- Real-time DamagePoint Monitor - Chỉ clone khi có DamagePoint MỚI xuất hiện
-- Chạy liên tục để theo dõi và clone ngay khi dùng skill

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- Tạo folder để chứa clones
local cloneFolder = Workspace:FindFirstChild("NewDamagePoints")
if cloneFolder then
    cloneFolder:Destroy()
end
cloneFolder = Instance.new("Folder")
cloneFolder.Name = "NewDamagePoints"
cloneFolder.Parent = Workspace

print("=== Real-time DamagePoint Monitor Started ===")
print("Chờ bạn dùng skill để phát hiện DamagePoints...")

local cloneCount = 0
local connections = {}

-- Function clone nhanh
local function QuickClone(obj, reason)
    cloneCount = cloneCount + 1
    local timestamp = os.date("%H:%M:%S")
    
    print(string.format("[%s] #%d - Found: %s in %s (%s)", 
        timestamp, cloneCount, obj.Name, obj.Parent.Name, reason))
    
    local success, clone = pcall(function()
        return obj.Parent:Clone()
    end)
    
    if success and clone then
        clone.Name = string.format("%s_Clone_%d_%s", 
            obj.Parent.Name, cloneCount, timestamp:gsub(":", "-"))
        clone.Parent = cloneFolder
        
        -- Thêm info
        local info = Instance.new("StringValue")
        info.Name = "INFO"
        info.Value = string.format("DamagePoint: %s | Time: %s | Reason: %s | Original: %s", 
            obj.Name, timestamp, reason, obj.Parent.Name)
        info.Parent = clone
        
        print(string.format("  → Cloned: %s", clone.Name))
        return true
    else
        print("  → Clone failed!")
        return false
    end
end

-- Monitor character descendants
local function MonitorCharacter(character)
    if not character then return end
    
    print("Monitoring character:", character.Name)
    
    -- Monitor khi có object MỚI được thêm vào
    local connection = character.DescendantAdded:Connect(function(obj)
        if obj:IsA("Attachment") then
            local name = obj.Name:lower()
            -- Kiểm tra tên có phải DamagePoint không
            if name:find("damage") or name:find("dmg") or name:find("hit") or 
               name:find("point") or name:find("attack") then
                
                wait(0.1) -- Đợi object setup xong
                QuickClone(obj, "NEW_ATTACHMENT")
            end
        elseif obj:IsA("Part") or obj:IsA("MeshPart") then
            -- Kiểm tra part mới có chứa attachments không
            wait(0.2) -- Đợi attachments được add vào part
            for _, child in pairs(obj:GetChildren()) do
                if child:IsA("Attachment") then
                    local name = child.Name:lower()
                    if name:find("damage") or name:find("dmg") or name:find("hit") or 
                       name:find("point") or name:find("attack") then
                        QuickClone(child, "NEW_PART_WITH_ATTACHMENT")
                    end
                end
            end
        end
    end)
    
    table.insert(connections, connection)
end

-- Monitor backpack (tools)
local function MonitorBackpack()
    if not LocalPlayer.Backpack then return end
    
    LocalPlayer.Backpack.ChildAdded:Connect(function(tool)
        if tool:IsA("Tool") then
            -- Monitor tool descendants
            tool.DescendantAdded:Connect(function(obj)
                if obj:IsA("Attachment") then
                    local name = obj.Name:lower()
                    if name:find("damage") or name:find("dmg") or name:find("hit") or 
                       name:find("point") or name:find("attack") then
                        wait(0.1)
                        QuickClone(obj, "TOOL_ATTACHMENT")
                    end
                end
            end)
        end
    end)
end

-- Monitor workspace (rơi xuống)
local function MonitorWorkspace()
    Workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("Attachment") and obj.Parent ~= cloneFolder then
            local name = obj.Name:lower()
            if name:find("damage") or name:find("dmg") or name:find("hit") or 
               name:find("point") or name:find("attack") then
                wait(0.1)
                QuickClone(obj, "WORKSPACE_ATTACHMENT")
            end
        end
    end)
end

-- Khởi tạo monitoring
local function StartMonitoring()
    -- Monitor character hiện tại
    if LocalPlayer.Character then
        MonitorCharacter(LocalPlayer.Character)
    end
    
    -- Monitor khi respawn
    LocalPlayer.CharacterAdded:Connect(function(character)
        print("Character respawned, monitoring new character...")
        MonitorCharacter(character)
    end)
    
    -- Monitor backpack
    MonitorBackpack()
    
    -- Monitor workspace
    MonitorWorkspace()
    
    print("✅ All monitors active!")
    print("🎯 Dùng skill để test - script sẽ tự động clone DamagePoints mới!")
end

-- Status display
local function ShowStatus()
    spawn(function()
        while true do
            wait(10) -- Update mỗi 10 giây
            if cloneCount > 0 then
                print(string.format("📊 Status: %d DamagePoints cloned | Folder: %s", 
                    cloneCount, cloneFolder:GetFullName()))
            end
        end
    end)
end

-- Cleanup function
local function Cleanup()
    for _, connection in pairs(connections) do
        if connection then
            connection:Disconnect()
        end
    end
    connections = {}
end

-- Commands
local function AddCommands()
    -- Command để clear clones
    game.Players.LocalPlayer.Chatted:Connect(function(msg)
        if msg:lower() == "/clear" then
            cloneFolder:ClearAllChildren()
            cloneCount = 0
            print("🗑️ Cleared all clones")
        elseif msg:lower() == "/stop" then
            Cleanup()
            print("⏹️ Stopped monitoring")
        elseif msg:lower() == "/status" then
            print(string.format("📊 Found: %d clones | Monitoring: %s", 
                cloneCount, #connections > 0 and "ON" or "OFF"))
        end
    end)
end

-- Start everything
StartMonitoring()
ShowStatus()
AddCommands()

print("\n=== HƯỚNG DẪN SỬ DỤNG ===")
print("1. Script đang chạy liên tục, theo dõi DamagePoints MỚI")
print("2. Dùng skill bất kỳ → sẽ tự động clone DamagePoints")
print("3. Kiểm tra folder 'NewDamagePoints' trong Workspace")
print("4. Chat '/clear' để xóa clones")
print("5. Chat '/stop' để dừng monitor")
print("6. Chat '/status' để xem trạng thái")
print("\n⏳ Đang chờ bạn dùng skill...")

-- Keep script running indicator
spawn(function()
    local dots = 0
    while true do
        wait()
        dots = (dots + 1) % 4
        local dotString = string.rep(".", dots)
        print(string.format("🔄 Monitoring%s (Cloned: %d)", dotString, cloneCount))
    end
end)