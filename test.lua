local startTime = time()
local offset = 0
local fileName = "record.txt"

-- Xóa file cũ nếu có
if isfile(fileName) then
    delfile(fileName)
end
writefile(fileName, "")

-- Serialize giá trị
local function serialize(value)
    if type(value) == "table" then
        local result = "{"
        for k, v in pairs(value) do
            result ..= "[" .. serialize(k) .. "]=" .. serialize(v) .. ", "
        end
        if result ~= "{" then
            result = result:sub(1, -3)
        end
        return result .. "}"
    else
        return tostring(value)
    end
end

local function serializeArgs(...)
    local args = {...}
    local output = {}
    for i, v in ipairs(args) do
        output[i] = serialize(v)
    end
    return table.concat(output, ", ")
end

-- Ghi log vào file
local function log(method, self, serializedArgs, upgradeSuccess)
    local name = tostring(self.Name)

    if name == "PlaceTower" then
        appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:placeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "SellTower" then
        appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:sellTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "TowerUpgradeRequest" then
        -- Chỉ ghi lại nâng cấp nếu upgradeSuccess là true
        if upgradeSuccess then
            appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
            appendfile(fileName, "TDX:upgradeTower(" .. serializedArgs .. ")\n")
            startTime = time() - offset
        end

    elseif name == "ChangeQueryType" then
        appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:changeQueryType(" .. serializedArgs .. ")\n")
        startTime = time() - offset
    end
end

-- Hook FireServer
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = {...}
    local serialized = serializeArgs(...)
    -- Nếu là upgrade thì kiểm tra kết quả trả về (giả sử trả về true nếu thành công)
    if tostring(self.Name) == "TowerUpgradeRequest" then
        local upgradeSuccess = oldFireServer(self, unpack(args))
        log("FireServer", self, serialized, upgradeSuccess)
        return upgradeSuccess
    else
        log("FireServer", self, serialized)
        return oldFireServer(self, unpack(args))
    end
end)

-- Hook InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = {...}
    local serialized = serializeArgs(...)
    if tostring(self.Name) == "TowerUpgradeRequest" then
        local upgradeSuccess = oldInvokeServer(self, unpack(args))
        log("InvokeServer", self, serialized, upgradeSuccess)
        return upgradeSuccess
    else
        log("InvokeServer", self, serialized)
        return oldInvokeServer(self, unpack(args))
    end
end)

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    local args = {...}
    local serialized = serializeArgs(...)
    if method == "FireServer" or method == "InvokeServer" then
        if tostring(self.Name) == "TowerUpgradeRequest" then
            local upgradeSuccess = oldNamecall(self, unpack(args))
            log(method, self, serialized, upgradeSuccess)
            return upgradeSuccess
        else
            log(method, self, serialized)
            return oldNamecall(self, unpack(args))
        end
    end
    return oldNamecall(self, unpack(args))
end)

print("✅ Ghi macro TDX đã bắt đầu (chỉ ghi nâng cấp thành công vào record.txt).")

-- Phần chuyển đổi sang macro runner giữ nguyên như cũ
-- ... (phần chuyển đổi macro sang JSON)
