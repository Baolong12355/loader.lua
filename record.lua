local startTime = time()
local offset = 0
local fileName = 1

-- Tìm tên file mới chưa tồn tại
while isfile(tostring(fileName)..".txt") do
    fileName += 1
end
fileName = tostring(fileName)..".txt"
writefile(fileName, "")

-- Hàm serialize giá trị
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

-- Hàm serialize tất cả argument
local function serializeArgs(...)
    local args = {...}
    local output = {}
    for i, v in ipairs(args) do
        output[i] = serialize(v)
    end
    return table.concat(output, ", ")
end

-- Hàm log thao tác vào file
local function log(method, self, serializedArgs)
    local name = tostring(self.Name)
    local text = name.." "..serializedArgs.."\n"
    print(text)

    if name == "PlaceTower" then
        appendfile(fileName, "task.wait("..tostring((time() - offset) - startTime)..")\n")
        appendfile(fileName, "TDX:placeTower("..serializedArgs..")\n")
        startTime = time() - offset

    elseif name == "SellTower" then
        appendfile(fileName, "task.wait("..tostring((time() - offset) - startTime)..")\n")
        appendfile(fileName, "TDX:sellTower("..serializedArgs..")\n")
        startTime = time() - offset

    elseif name == "TowerUpgradeRequest" then
        appendfile(fileName, "task.wait("..tostring((time() - offset) - startTime)..")\n")
        appendfile(fileName, "TDX:upgradeTower("..serializedArgs..")\n")
        startTime = time() - offset

    elseif name == "DifficultyVoteReady" then
        offset = time()
        appendfile(fileName, "TDX:Start('ENTER DIFFICULTY')\n")
        startTime = time() - offset

    elseif name == "ChangeQueryType" then
        appendfile(fileName, "task.wait("..tostring((time() - offset) - startTime)..")\n")
        appendfile(fileName, "TDX:changeQueryType("..serializedArgs..")\n")
        startTime = time() - offset
    end
end

-- Hook FireServer
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = serializeArgs(...)
    log("FireServer", self, args)
    return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = serializeArgs(...)
    log("InvokeServer", self, args)
    return oldInvokeServer(self, ...)
end)

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        local args = serializeArgs(...)
        log(method, self, args)
    end
    return oldNamecall(self, ...)
end)

print("✅ Ghi macro TDX đã bắt đầu.")
