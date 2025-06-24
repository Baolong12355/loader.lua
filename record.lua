local HttpService = game:GetService("HttpService")
local startTime = time()
local offset = 0
local fileName = 1

-- Tìm tên file mới chưa tồn tại
while isfile(tostring(fileName)..".txt") do
    fileName += 1
end
fileName = tostring(fileName)..".txt"
writefile(fileName, "")

-- Serialize value cho JSON ghi file
local function serialize(value)
    if typeof(value) == "Vector3" then
        return {__type = "Vector3", x = value.X, y = value.Y, z = value.Z}
    elseif typeof(value) == "CFrame" then
        return {__type = "CFrame", values = {value:GetComponents()}}
    elseif type(value) == "table" then
        local result = {}
        for k, v in pairs(value) do
            result[tostring(k)] = serialize(v)
        end
        return result
    else
        return value
    end
end

local function serializeArgsTable(args)
    local output = {}
    for i, v in ipairs(args) do
        output[i] = serialize(v)
    end
    return output
end

local function log(method, self, args)
    local name = tostring(self.Name)
    local entry = { method = method, name = name, args = serializeArgsTable(args), time = tick() }
    -- Ghi từng entry JSON ra file, mỗi dòng một entry:
    appendfile(fileName, HttpService:JSONEncode(entry).."\n")
    print(name, HttpService:JSONEncode(entry))

    -- Ghi thêm các dòng runner TDX nếu muốn
    if name == "PlaceTower" then
        appendfile(fileName, "-- PlaceTower: "..HttpService:JSONEncode(entry).."\n")
        startTime = time() - offset
    elseif name == "SellTower" then
        appendfile(fileName, "-- SellTower: "..HttpService:JSONEncode(entry).."\n")
        startTime = time() - offset
    elseif name == "TowerUpgradeRequest" then
        appendfile(fileName, "-- Upgrade: "..HttpService:JSONEncode(entry).."\n")
        startTime = time() - offset
    elseif name == "DifficultyVoteReady" then
        offset = time()
        appendfile(fileName, "-- DifficultyVoteReady: "..HttpService:JSONEncode(entry).."\n")
        startTime = time() - offset
    elseif name == "ChangeQueryType" then
        appendfile(fileName, "-- ChangeQueryType: "..HttpService:JSONEncode(entry).."\n")
        startTime = time() - offset
    end
end

local function getArgs(...)
    local args = {...}
    return args
end

-- Hook FireServer (hook theo đúng phong cách macro chuẩn)
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = getArgs(...)
    pcall(log, "FireServer", self, args)
    return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = getArgs(...)
    pcall(log, "InvokeServer", self, args)
    return oldInvokeServer(self, ...)
end)

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        local args = getArgs(...)
        pcall(log, method, self, args)
    end
    return oldNamecall(self, ...)
end)

print("✅ Ghi macro TDX đã bắt đầu. File:", fileName)
