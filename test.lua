local ReplicatedStorage = game:GetService("ReplicatedStorage")

local fileName = "record.txt"
local startTime = time()
local offset = 0

-- Xoá file cũ
if isfile(fileName) then delfile(fileName) end
writefile(fileName, "")

-- Pending xác nhận
local pending = nil
local timeout = 2

-- Serialize giá trị
local function serialize(v)
    if typeof(v) == "Vector3" then
        return "Vector3.new(" .. v.X .. "," .. v.Y .. "," .. v.Z .. ")"
    elseif typeof(v) == "Vector2int16" then
        return "Vector2int16.new(" .. v.X .. "," .. v.Y .. ")"
    elseif type(v) == "table" then
        local out = {}
        for k, val in pairs(v) do
            out[#out + 1] = "[" .. tostring(k) .. "]=" .. serialize(val)
        end
        return "{" .. table.concat(out, ",") .. "}"
    else
        return tostring(v)
    end
end

-- Serialize args
local function serializeArgs(...)
    local args = {...}
    local out = {}
    for i, v in ipairs(args) do
        out[i] = serialize(v)
    end
    return table.concat(out, ", ")
end

-- Xác nhận và ghi
local function confirmAndWrite()
    if not pending then return end
    appendfile(fileName, "task.wait(" .. ((time() - offset) - startTime) .. ")\n")
    appendfile(fileName, pending.code .. "\n")
    startTime = time() - offset
    pending = nil
end

-- Ghi nếu server phản hồi đúng loại
local function tryConfirm(typeStr)
    if pending and pending.type == typeStr then
        confirmAndWrite()
    end
end

-- Ghi log
local function setPending(typeStr, code)
    pending = {
        type = typeStr,
        code = code,
        created = tick()
    }
end

-- Lắng nghe Remote xác thực
ReplicatedStorage.Remotes.TowerFactoryQueueUpdated.OnClientEvent:Connect(function(data)
    local d = data[1]
    if not d then return end
    if d.Creation then
        tryConfirm("Place")
    else
        tryConfirm("Sell")
    end
end)

ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if data[1] then
        tryConfirm("Upgrade")
    end
end)

ReplicatedStorage.Remotes.TowerQueryTypeIndexChanged.OnClientEvent:Connect(function(data)
    if data[1] then
        tryConfirm("Target")
    end
end)

-- Timeout check
task.spawn(function()
    while true do
        task.wait(0.3)
        if pending and tick() - pending.created > timeout then
            warn("❌ Không xác thực được: " .. pending.type)
            pending = nil
        end
    end
end)

-- Hook FireServer
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = serializeArgs(...)
    local name = self.Name

    if name == "PlaceTower" then
        setPending("Place", "TDX:placeTower(" .. args .. ")")
    elseif name == "SellTower" then
        setPending("Sell", "TDX:sellTower(" .. args .. ")")
    elseif name == "TowerUpgradeRequest" then
        setPending("Upgrade", "TDX:upgradeTower(" .. args .. ")")
    elseif name == "ChangeQueryType" then
        setPending("Target", "TDX:changeQueryType(" .. args .. ")")
    end

    return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = serializeArgs(...)
    return oldInvokeServer(self, ...)
end)

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        local args = serializeArgs(...)
        local name = self.Name

        if name == "PlaceTower" then
            setPending("Place", "TDX:placeTower(" .. args .. ")")
        elseif name == "SellTower" then
            setPending("Sell", "TDX:sellTower(" .. args .. ")")
        elseif name == "TowerUpgradeRequest" then
            setPending("Upgrade", "TDX:upgradeTower(" .. args .. ")")
        elseif name == "ChangeQueryType" then
            setPending("Target", "TDX:changeQueryType(" .. args .. ")")
        end
    end
    return oldNamecall(self, ...)
end)

print("📌 Đã bật ghi macro có xác nhận từ server.")
