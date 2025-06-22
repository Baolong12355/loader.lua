-- 📜 SCR Recorder Chính Xác - Ronix Ready
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Danh sách remote cần hook (đúng tên trong game)
local TARGET_REMOTES = {
    "PlaceTower",           -- RemoteFunction
    "TowerUpgradeRequest",  -- RemoteEvent
    "SellTower",            -- RemoteEvent
    "ChangeQueryType"       -- RemoteEvent
}

-- Debug mode (hiển thị chi tiết trong console)
local DEBUG_MODE = true
local function debugPrint(...)
    if DEBUG_MODE then
        print("[DEBUG]", ...)
    end
end

-- Kiểm tra dịch vụ cơ bản
if not ReplicatedStorage or not LocalPlayer then
    error("❌ Không thể khởi tạo dịch vụ cần thiết")
end

-- Tải TowerClass an toàn
local TowerClass
local success, err = pcall(function()
    TowerClass = require(LocalPlayer.PlayerScripts.Client.GameClass:WaitForChild("TowerClass"))
end)
if not success then
    warn("⚠️ Không thể tải TowerClass: "..tostring(err))
end

-- Cấu hình lưu dữ liệu
local recorded = {}
local SAVE_PATH = "tdx/macros/recorded.json"
local dirty = false

-- Tạo thư mục nếu chưa tồn tại
if not isfolder("tdx/macros") then
    makefolder("tdx/macros")
end

-- 💾 Hàm lưu an toàn
local function save()
    if #recorded == 0 then return end
    local success, err = pcall(function()
        local json = HttpService:JSONEncode(recorded)
        writefile(SAVE_PATH, json)
        debugPrint("💾 Đã lưu dữ liệu")
    end)
    if not success then
        warn("❌ Lỗi khi lưu: "..tostring(err))
    end
end

-- Tự động lưu mỗi 5 giây
task.spawn(function()
    while true do
        task.wait(5)
        if dirty then
            save()
            dirty = false
        end
    end
end)

local function addRecord(entry)
    if not entry then return end
    table.insert(recorded, entry)
    dirty = true
    debugPrint("📝 Đã ghi:", entry._type or "unknown")
end

-- ✅ Hàm lấy vị trí tower chính xác
local function GetTowerXFromHash(hash)
    if not TowerClass then return nil end
    
    local tower
    pcall(function()
        tower = TowerClass:GetTower(hash)
        if not tower then
            debugPrint("⚠️ Không tìm thấy tower với hash:", hash)
            return
        end
        
        local model = tower.Character and tower.Character:GetCharacterModel()
        if not model then
            debugPrint("⚠️ Tower không có model")
            return
        end
        
        local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
        if not root then
            debugPrint("⚠️ Không tìm thấy root part")
            return
        end
        
        return tonumber(string.format("%.15f", root.Position.X))
    end)
    
    return nil
end

-- 🔍 Tìm remote trong ReplicatedStorage.Remotes
local function FindTargetRemote(remoteName)
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then
        debugPrint("❌ Không tìm thấy thư mục Remotes")
        return nil
    end
    
    for _, remote in ipairs(remotes:GetDescendants()) do
        if remote.Name == remoteName and (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then
            debugPrint("✅ Đã tìm thấy remote:", remoteName)
            return remote
        end
    end
    
    debugPrint("⚠️ Không tìm thấy remote:", remoteName)
    return nil
end

-- 🎯 Hook từng remote cụ thể
local function HookSpecificRemote(remote)
    if not remote then return end
    
    local remoteName = remote.Name
    debugPrint("🛠️ Đang hook remote:", remoteName)
    
    if remote:IsA("RemoteFunction") and remoteName == "PlaceTower" then
        local oldInvoke = remote.InvokeServer
        remote.InvokeServer = newcclosure(function(self, ...)
            local args = {...}
            if #args >= 4 then
                local a1, towerName, pos, rot = args[1], args[2], args[3], args[4]
                if typeof(pos) == "Vector3" then
                    addRecord({
                        _type = "PlaceTower",
                        TowerA1 = tostring(a1),
                        TowerPlaced = towerName,
                        TowerVector = string.format("%.15f, %.15f, %.15f", pos.X, pos.Y, pos.Z),
                        Rotation = rot,
                        Timestamp = os.time()
                    })
                end
            end
            return oldInvoke(self, ...)
        end)
        
    elseif remote:IsA("RemoteEvent") then
        local oldFire = remote.FireServer
        remote.FireServer = newcclosure(function(self, ...)
            local args = {...}
            
            -- Tower Upgrade
            if remoteName == "TowerUpgradeRequest" and #args >= 2 then
                local hash, path = args[1], args[2]
                local x = GetTowerXFromHash(hash)
                if x then
                    addRecord({
                        _type = "TowerUpgrade",
                        TowerX = x,
                        UpgradePath = path,
                        Timestamp = os.time()
                    })
                end
            
            -- Sell Tower
            elseif remoteName == "SellTower" and #args >= 1 then
                local hash = args[1]
                local x = GetTowerXFromHash(hash)
                if x then
                    addRecord({
                        _type = "SellTower",
                        TowerX = x,
                        Timestamp = os.time()
                    })
                end
            
            -- Change Target
            elseif remoteName == "ChangeQueryType" and #args >= 2 then
                local hash, target = args[1], args[2]
                local x = GetTowerXFromHash(hash)
                if x then
                    addRecord({
                        _type = "ChangeTarget",
                        TowerX = x,
                        TargetType = target,
                        Timestamp = os.time()
                    })
                end
            end
            
            return oldFire(self, ...)
        end)
    end
    
    debugPrint("✅ Đã hook thành công:", remoteName)
end

-- Khởi tạo hook cho tất cả remote cần thiết
for _, remoteName in ipairs(TARGET_REMOTES) do
    local remote = FindTargetRemote(remoteName)
    if remote then
        HookSpecificRemote(remote)
    else
        warn("⚠️ Không thể hook remote: "..remoteName)
    end
end

-- Hook bổ sung bằng __namecall (phương án dự phòng)
local mt = getrawmetatable(game)
if mt then
    local originalNamecall = mt.__namecall
    setreadonly(mt, false)

    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        local remoteName = self.Name

        if not checkcaller() and table.find(TARGET_REMOTES, remoteName) then
            -- Place Tower (RemoteFunction)
            if method == "InvokeServer" and remoteName == "PlaceTower" and #args >= 4 then
                local a1, towerName, pos, rot = args[1], args[2], args[3], args[4]
                if typeof(pos) == "Vector3" then
                    addRecord({
                        _type = "PlaceTower_Namecall",
                        TowerA1 = tostring(a1),
                        TowerPlaced = towerName,
                        TowerVector = string.format("%.15f, %.15f, %.15f", pos.X, pos.Y, pos.Z),
                        Rotation = rot,
                        Timestamp = os.time()
                    })
                end
            
            -- Các RemoteEvents khác
            elseif method == "FireServer" then
                -- Tower Upgrade
                if remoteName == "TowerUpgradeRequest" and #args >= 2 then
                    local hash, path = args[1], args[2]
                    local x = GetTowerXFromHash(hash)
                    if x then
                        addRecord({
                            _type = "TowerUpgrade_Namecall",
                            TowerX = x,
                            UpgradePath = path,
                            Timestamp = os.time()
                        })
                    end
                
                -- Sell Tower
                elseif remoteName == "SellTower" and #args >= 1 then
                    local hash = args[1]
                    local x = GetTowerXFromHash(hash)
                    if x then
                        addRecord({
                            _type = "SellTower_Namecall",
                            TowerX = x,
                            Timestamp = os.time()
                        })
                    end
                
                -- Change Target
                elseif remoteName == "ChangeQueryType" and #args >= 2 then
                    local hash, target = args[1], args[2]
                    local x = GetTowerXFromHash(hash)
                    if x then
                        addRecord({
                            _type = "ChangeTarget_Namecall",
                            TowerX = x,
                            TargetType = target,
                            Timestamp = os.time()
                        })
                    end
                end
            end
        end

        return originalNamecall(self, ...)
    end)

    setreadonly(mt, true)
    debugPrint("✅ Đã hook __namecall backup")
end

print("✅ SCR Recorder Chính Xác đã sẵn sàng! Chỉ hook các remote:", table.concat(TARGET_REMOTES, ", "))
