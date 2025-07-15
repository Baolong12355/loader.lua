local ReplicatedStorage = game:GetService("ReplicatedStorage")
local fileName = "record.txt"
local offset = 0
local startTime = time()

-- Reset file
if isfile(fileName) then
    delfile(fileName)
end
writefile(fileName, "")

local function debugPrint(...)
    print("[RECORD DEBUG]", ...)
end

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

local function serializeArgs(args)
    local output = {}
    for i, v in ipairs(args) do
        output[i] = serialize(v)
    end
    return table.concat(output, ", ")
end

-- Tạm lưu thao tác chờ xác nhận
local pending = {
    PlaceTower = {},
    SellTower = {},
    TowerUpgradeRequest = {},
    ChangeQueryType = {}
}

debugPrint("Khởi động macro recorder. Đang hook FireServer/InvokeServer...")

-- Hook FireServer để lưu thao tác chờ xác nhận
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = {...}
    local name = tostring(self.Name)
    debugPrint("FireServer gọi remote:", name, "args:", serializeArgs(args))
    if pending[name] then
        table.insert(pending[name], {
            time = time(),
            args = args
        })
        debugPrint("Đã lưu thao tác pending:", name, "#pending =", #pending[name])
    end
    return oldFireServer(self, unpack(args))
end)

-- Hook InvokeServer để lưu thao tác chờ xác nhận
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = {...}
    local name = tostring(self.Name)
    debugPrint("InvokeServer gọi remote:", name, "args:", serializeArgs(args))
    if pending[name] then
        table.insert(pending[name], {
            time = time(),
            args = args
        })
        debugPrint("Đã lưu thao tác pending:", name, "#pending =", #pending[name])
    end
    return oldInvokeServer(self, unpack(args))
end)

-- Xác nhận từ server: Place & Sell
local TowerFactoryQueueUpdated = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerFactoryQueueUpdated")
TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    debugPrint("TowerFactoryQueueUpdated xác nhận, data:", serialize(data))
    for _, v in ipairs(data) do
        local info = v.Data[1]
        if typeof(info) == "table" then
            -- PLACE (có Vector3)
            local foundVector = false
            for _, field in pairs(info) do
                if typeof(field) == "Vector3" then
                    foundVector = true
                    break
                end
            end
            if foundVector and #pending.PlaceTower > 0 then
                local entry = table.remove(pending.PlaceTower, 1)
                local waitTime = (entry.time - offset) - startTime
                appendfile(fileName, ("task.wait(%s)\nTDX:placeTower(%s)\n"):format(waitTime, serializeArgs(entry.args)))
                startTime = entry.time - offset
                debugPrint("Ghi thao tác PLACE thành công, waitTime:", waitTime, "args:", serializeArgs(entry.args))
            else
                debugPrint("Không có thao tác PLACE pending hoặc không có Vector3.")
            end
        else
            -- SELL (không có Vector3)
            if #pending.SellTower > 0 then
                local entry = table.remove(pending.SellTower, 1)
                local waitTime = (entry.time - offset) - startTime
                appendfile(fileName, ("task.wait(%s)\nTDX:sellTower(%s)\n"):format(waitTime, serializeArgs(entry.args)))
                startTime = entry.time - offset
                debugPrint("Ghi thao tác SELL thành công, waitTime:", waitTime, "args:", serializeArgs(entry.args))
            else
                debugPrint("Không có thao tác SELL pending.")
            end
        end
    end
end)

-- Xác nhận từ server: Upgrade
local TowerUpgradeQueueUpdated = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUpgradeQueueUpdated")
TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    debugPrint("TowerUpgradeQueueUpdated xác nhận, data:", serialize(data))
    if #pending.TowerUpgradeRequest > 0 then
        local entry = table.remove(pending.TowerUpgradeRequest, 1)
        local waitTime = (entry.time - offset) - startTime
        appendfile(fileName, ("task.wait(%s)\nTDX:upgradeTower(%s)\n"):format(waitTime, serializeArgs(entry.args)))
        startTime = entry.time - offset
        debugPrint("Ghi thao tác UPGRADE thành công, waitTime:", waitTime, "args:", serializeArgs(entry.args))
    else
        debugPrint("Không có thao tác UPGRADE pending.")
    end
end)

-- Xác nhận từ server: Change target/query
local TowerQueryTypeIndexChanged = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerQueryTypeIndexChanged")
TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    debugPrint("TowerQueryTypeIndexChanged xác nhận, data:", serialize(data))
    if #pending.ChangeQueryType > 0 then
        local entry = table.remove(pending.ChangeQueryType, 1)
        local waitTime = (entry.time - offset) - startTime
        appendfile(fileName, ("task.wait(%s)\nTDX:changeQueryType(%s)\n"):format(waitTime, serializeArgs(entry.args)))
        startTime = entry.time - offset
        debugPrint("Ghi thao tác CHANGE TARGET thành công, waitTime:", waitTime, "args:", serializeArgs(entry.args))
    else
        debugPrint("Không có thao tác CHANGE QUERY pending.")
    end
end)

debugPrint("✅ Macro recorder TDX đã bắt đầu (chỉ ghi thao tác xác nhận thành công vào record.txt!)")
