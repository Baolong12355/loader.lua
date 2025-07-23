local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Kiểm tra file functions an toàn
local function safeFileOperation(operation, ...)
    local success, result = pcall(operation, ...)
    if not success then
        warn("File operation failed: " .. tostring(result))
        return false
    end
    return result
end

local fileName = "record.txt"
if isfile and safeFileOperation(isfile, fileName) then 
    safeFileOperation(delfile, fileName)
end 
if writefile then
    safeFileOperation(writefile, fileName, "")
end

local pendingQueue = {}
local timeout = 2
local lastKnownLevels = {} -- { [towerHash] = {path1Level, path2Level} }

-- Hàm phụ trợ
local function serialize(v)
    if typeof(v) == "Vector3" then
        return "Vector3.new("..v.X..","..v.Y..","..v.Z..")"
    elseif typeof(v) == "Vector2int16" then
        return "Vector2int16.new("..v.X..","..v.Y..")"
    elseif type(v) == "table" then
        local out = {}
        for k, val in pairs(v) do
            out[#out+1] = "["..tostring(k).."]="..serialize(val)
        end
        return "{"..table.concat(out, ",").."}"
    else
        return tostring(v)
    end
end

local function serializeArgs(...)
    local args = {...}
    local out = {}
    for i, v in ipairs(args) do
        out[i] = serialize(v)
    end
    return table.concat(out, ", ")
end

local function tryConfirm(typeStr, specificHash)
    for i, item in ipairs(pendingQueue) do
        if item.type == typeStr then
            -- Nếu có hash cụ thể, kiểm tra xem có khớp không
            if not specificHash or string.find(item.code, tostring(specificHash)) then
                if appendfile then
                    safeFileOperation(appendfile, fileName, item.code.."\n")
                end
                table.remove(pendingQueue, i)
                return
            end
        end
    end
end

local function setPending(typeStr, code, hash)
    table.insert(pendingQueue, {
        type = typeStr,
        code = code,
        created = tick(),
        hash = hash
    })
end

-- Xử lý TowerFactoryQueueUpdated (place/sell towers)
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data[1]
    if not d then return end
    
    if d.Creation then
        tryConfirm("Place")
    else
        tryConfirm("Sell")
    end
end)

-- Xử lý TowerUpgradeQueueUpdated với ưu tiên path từ server
ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or not data[1] then return end
    
    local towerData = data[1]
    local hash = towerData.Hash
    local newLevels = towerData.LevelReplicationData
    
    -- Tìm path nào thực sự được nâng cấp
    local upgradedPath = nil
    if lastKnownLevels[hash] then
        for path = 1, 2 do
            if (newLevels[path] or 0) > (lastKnownLevels[hash][path] or 0) then
                upgradedPath = path
                break
            end
        end
    end
    
    -- Nếu tìm thấy path được nâng cấp
    if upgradedPath then
        local code = string.format("TDX:upgradeTower(%s, %d, 1)", tostring(hash), upgradedPath)
        if appendfile then
            safeFileOperation(appendfile, fileName, code.."\n")
        end
        
        -- Xóa các yêu cầu đang chờ cho tower này
        for i = #pendingQueue, 1, -1 do
            if pendingQueue[i].type == "Upgrade" and pendingQueue[i].hash == hash then
                table.remove(pendingQueue, i)
            end
        end
    else
        -- Nếu không tìm thấy path cụ thể, thử confirm từ pending queue
        tryConfirm("Upgrade", hash)
    end
    
    -- Cập nhật trạng thái mới nhất
    lastKnownLevels[hash] = newLevels or {}
end)

-- Xử lý TowerQueryTypeIndexChanged (target change)
ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data[1] then
        tryConfirm("Target")
    end
end)

-- Task cleanup pending queue
task.spawn(function()
    while true do
        task.wait(0.05)
        local now = tick()
        for i = #pendingQueue, 1, -1 do
            if now - pendingQueue[i].created > timeout then
                warn("❌ Không xác thực được: " .. pendingQueue[i].type)
                table.remove(pendingQueue, i)
            end
        end
    end
end)

-- Xử lý các remote calls
local function handleRemote(name, args)
    if name == "TowerUpgradeRequest" then
        local hash, path, count = unpack(args)
        if typeof(hash) == "number" and typeof(path) == "number" and typeof(count) == "number" then
            if path >= 0 and path <= 2 and count > 0 and count <= 5 then
                for _ = 1, count do
                    setPending("Upgrade", string.format("TDX:upgradeTower(%s, %d, 1)", tostring(hash), path), hash)
                end
            end
        end
    elseif name == "PlaceTower" then
        local a1, towerName, vec, rot = unpack(args)
        if typeof(a1) == "number" and typeof(towerName) == "string" and typeof(vec) == "Vector3" and typeof(rot) == "number" then
            local code = string.format('TDX:placeTower(%d, "%s", Vector3.new(%s, %s, %s), %d)', 
                a1, towerName, tostring(vec.X), tostring(vec.Y), tostring(vec.Z), rot)
            setPending("Place", code)
        end
    elseif name == "SellTower" then
        setPending("Sell", "TDX:sellTower("..serializeArgs(unpack(args))..")")
    elseif name == "ChangeQueryType" then
        setPending("Target", "TDX:changeQueryType("..serializeArgs(unpack(args))..")")
    end
end

-- Kiểm tra và tạo function an toàn cho các executor
local function safeHookFunction(originalFunc, hookFunc)
    if hookfunction then
        return hookfunction(originalFunc, hookFunc)
    else
        warn("hookfunction không hỗ trợ trên executor này")
        return originalFunc
    end
end

local function safeHookMetamethod(object, method, hookFunc)
    if hookmetamethod then
        return hookmetamethod(object, method, hookFunc)
    else
        warn("hookmetamethod không hỗ trợ trên executor này")
        return nil
    end
end

local function safeCheckCaller()
    if checkcaller then
        return checkcaller()
    else
        return false
    end
end

-- Hook FireServer
local oldFireServer = safeHookFunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local name = self.Name
    local args = {...}
    handleRemote(name, args)
    return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = safeHookFunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local name = self.Name
    local args = {...}
    handleRemote(name, args)
    return oldInvokeServer(self, ...)
end)

-- Hook namecall metamethod
local oldNamecall
oldNamecall = safeHookMetamethod(game, "__namecall", function(self, ...)
    if safeCheckCaller() then return oldNamecall(self, ...) end
    
    local method = getnamecallmethod()
    if not method then return oldNamecall(self, ...) end
    
    local name = self.Name
    local args = {...}
    
    if method == "FireServer" or method == "InvokeServer" then
        handleRemote(name, args)
    end
    
    return oldNamecall(self, ...)
end)

print("✅ Complete TDX Recorder hoạt động: Tất cả hành động đã được hook")
print("📁 Ghi dữ liệu vào file: " .. fileName)

-- Kiểm tra các function cần thiết
if not hookfunction then warn("⚠️ hookfunction không khả dụng") end
if not hookmetamethod then warn("⚠️ hookmetamethod không khả dụng") end  
if not isfile then warn("⚠️ isfile không khả dụng") end
if not writefile then warn("⚠️ writefile không khả dụng") end
if not appendfile then warn("⚠️ appendfile không khả dụng") end

-- Test file operations
if writefile and appendfile then
    local testResult = safeFileOperation(writefile, "test_record.txt", "test")
    if testResult then
        print("✅ File operations working properly")
        safeFileOperation(delfile, "test_record.txt")
    else
        warn("❌ File operations not working")
    end
end