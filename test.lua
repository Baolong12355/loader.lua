local ReplicatedStorage = game:GetService("ReplicatedStorage")
local fileName = "record.txt"
local offset = 0
local startTime = time()

if isfile(fileName) then
    delfile(fileName)
end
writefile(fileName, "")

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

-- Lưu thao tác pending theo tên remote client
local pending = {
    PlaceTower = {},
    SellTower = {},
    TowerUpgradeRequest = {},
    ChangeQueryType = {}
}

local function savePending(name, ...)
    if pending[name] then
        table.insert(pending[name], {
            time = time(),
            args = {...}
        })
        print("[DEBUG] Pending thao tác:", name, "#pending =", #pending[name])
    end
end

local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local name = tostring(self.Name)
    savePending(name, ...)
    return oldFireServer(self, ...)
end)

local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local name = tostring(self.Name)
    savePending(name, ...)
    return oldInvokeServer(self, ...)
end)

-- Khi server xác nhận thao tác (ví dụ Place/Sell)
local TowerFactoryQueueUpdated = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerFactoryQueueUpdated")
TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
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
            end
        else
            -- SELL (không có Vector3)
            if #pending.SellTower > 0 then
                local entry = table.remove(pending.SellTower, 1)
                local waitTime = (entry.time - offset) - startTime
                appendfile(fileName, ("task.wait(%s)\nTDX:sellTower(%s)\n"):format(waitTime, serializeArgs(entry.args)))
                startTime = entry.time - offset
            end
        end
    end
end)

-- Xác nhận upgrade
local TowerUpgradeQueueUpdated = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUpgradeQueueUpdated")
TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if #pending.TowerUpgradeRequest > 0 then
        local entry = table.remove(pending.TowerUpgradeRequest, 1)
        local waitTime = (entry.time - offset) - startTime
        appendfile(fileName, ("task.wait(%s)\nTDX:upgradeTower(%s)\n"):format(waitTime, serializeArgs(entry.args)))
        startTime = entry.time - offset
    end
end)

-- Xác nhận change query/target
local TowerQueryTypeIndexChanged = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerQueryTypeIndexChanged")
TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if #pending.ChangeQueryType > 0 then
        local entry = table.remove(pending.ChangeQueryType, 1)
        local waitTime = (entry.time - offset) - startTime
        appendfile(fileName, ("task.wait(%s)\nTDX:changeQueryType(%s)\n"):format(waitTime, serializeArgs(entry.args)))
        startTime = entry.time - offset
    end
end)

print("✅ Macro recorder TDX đã bắt đầu (chỉ ghi khi server xác nhận thành công vào record.txt!)")
