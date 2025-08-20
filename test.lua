-- Script tìm và clone tất cả objects có DamagePoint để nghiên cứu
-- Sẽ tạo một folder chứa tất cả clones trong Workspace

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local LocalPlayer = Players.LocalPlayer

-- Tạo folder để chứa clones
local cloneFolder = Workspace:FindFirstChild("DamagePointClones")
if cloneFolder then
    cloneFolder:Destroy()
end
cloneFolder = Instance.new("Folder")
cloneFolder.Name = "DamagePointClones"
cloneFolder.Parent = Workspace

print("=== Bắt đầu tìm DamagePoints ===")

local foundCount = 0
local clonedCount = 0

-- Function để clone object và tất cả properties
local function DeepClone(obj)
    local success, clone = pcall(function()
        return obj:Clone()
    end)
    
    if success then
        return clone
    else
        -- Nếu không clone được, tạo thông tin text
        local info = Instance.new("StringValue")
        info.Name = obj.Name .. "_Info"
        info.Value = string.format("ClassName: %s, Parent: %s, Position: %s", 
            obj.ClassName, 
            obj.Parent and obj.Parent.Name or "nil",
            obj:IsA("BasePart") and tostring(obj.Position) or "N/A")
        return info
    end
end

-- Function để tìm DamagePoints
local function FindDamagePoints(parent, parentName)
    for _, obj in pairs(parent:GetDescendants()) do
        if obj:IsA("Attachment") then
            -- Kiểm tra tên có chứa "damage", "dmg", "hit" (không phân biệt hoa thường)
            local name = obj.Name:lower()
            if name:find("damage") or name:find("dmg") or name:find("hit") then
                foundCount = foundCount + 1
                print(string.format("[%d] Found: %s in %s", foundCount, obj.Name, parentName))
                
                -- Clone parent object của attachment
                local parentObj = obj.Parent
                if parentObj then
                    local clonedParent = DeepClone(parentObj)
                    if clonedParent then
                        clonedParent.Name = parentObj.Name .. "_Clone_" .. foundCount
                        clonedParent.Parent = cloneFolder
                        clonedCount = clonedCount + 1
                        
                        -- Thêm thông tin debug
                        local info = Instance.new("StringValue")
                        info.Name = "DEBUG_INFO"
                        info.Value = string.format("Original: %s, DamagePoint: %s, Found in: %s", 
                            parentObj.Name, obj.Name, parentName)
                        info.Parent = clonedParent
                        
                        print(string.format("  → Cloned parent: %s", clonedParent.Name))
                    end
                end
            end
        end
    end
end

-- Tìm trong character của player
if LocalPlayer.Character then
    print("\n--- Tìm trong Character ---")
    FindDamagePoints(LocalPlayer.Character, "LocalPlayer.Character")
end

-- Tìm trong backpack
if LocalPlayer.Backpack then
    print("\n--- Tìm trong Backpack ---")
    FindDamagePoints(LocalPlayer.Backpack, "LocalPlayer.Backpack")
end

-- Tìm trong StarterPack
local StarterPack = game:GetService("StarterPack")
print("\n--- Tìm trong StarterPack ---")
FindDamagePoints(StarterPack, "StarterPack")

-- Tìm trong ReplicatedStorage
local ReplicatedStorage = game:GetService("ReplicatedStorage")
print("\n--- Tìm trong ReplicatedStorage ---")
FindDamagePoints(ReplicatedStorage, "ReplicatedStorage")

-- Tìm trong ServerStorage (nếu có quyền truy cập)
pcall(function()
    print("\n--- Tìm trong ServerStorage ---")
    FindDamagePoints(ServerStorage, "ServerStorage")
end)

-- Tìm trong các characters khác
print("\n--- Tìm trong Characters khác ---")
for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer and player.Character then
        FindDamagePoints(player.Character, player.Name .. ".Character")
    end
end

-- Tìm trong Workspace (tools rơi xuống đất, etc.)
print("\n--- Tìm trong Workspace ---")
for _, obj in pairs(Workspace:GetChildren()) do
    if obj:IsA("Tool") or obj:IsA("Model") and obj ~= cloneFolder then
        FindDamagePoints(obj, "Workspace." .. obj.Name)
    end
end

-- Kết quả
print("\n=== KẾT QUẢ ===")
print(string.format("Tìm thấy: %d DamagePoints", foundCount))
print(string.format("Clone thành công: %d objects", clonedCount))
print(string.format("Tất cả clones đã được lưu trong: %s", cloneFolder:GetFullName()))

if clonedCount > 0 then
    print("\n=== HƯỚNG DẪN ===")
    print("1. Vào Workspace → DamagePointClones")
    print("2. Mở từng clone để xem cấu trúc")
    print("3. Kiểm tra attachment có tên chứa 'damage', 'dmg', 'hit'")
    print("4. Xem DEBUG_INFO để biết thông tin gốc")
    
    -- Tạo thông tin tổng hợp
    local summary = Instance.new("StringValue")
    summary.Name = "SUMMARY"
    summary.Value = string.format("Found %d DamagePoints, Cloned %d objects. Check each clone for structure analysis.", foundCount, clonedCount)
    summary.Parent = cloneFolder
else
    print("Không tìm thấy DamagePoints nào!")
    print("Có thể:")
    print("- Game không sử dụng attachment tên 'DamagePoint'")
    print("- DamagePoints chỉ xuất hiện khi dùng skill")
    print("- Tên khác: thử tìm 'HitPoint', 'AttackPoint', etc.")
end

-- Function để monitor DamagePoints real-time (optional)
print("\n--- Monitoring real-time DamagePoints ---")
local function MonitorCharacter()
    if LocalPlayer.Character then
        LocalPlayer.Character.DescendantAdded:Connect(function(obj)
            if obj:IsA("Attachment") then
                local name = obj.Name:lower()
                if name:find("damage") or name:find("dmg") or name:find("hit") then
                    print(string.format("NEW DamagePoint detected: %s in %s", obj.Name, obj.Parent.Name))
                    
                    -- Auto clone khi có DamagePoint mới
                    wait(0.1) -- Đợi setup xong
                    local parent = obj.Parent
                    if parent then
                        local clone = DeepClone(parent)
                        if clone then
                            clone.Name = parent.Name .. "_RealTime_" .. tick()
                            clone.Parent = cloneFolder
                            print("  → Auto cloned:", clone.Name)
                        end
                    end
                end
            end
        end)
    end
end

MonitorCharacter()
LocalPlayer.CharacterAdded:Connect(MonitorCharacter)

print("Real-time monitoring active - sẽ tự động clone khi có DamagePoint mới!")