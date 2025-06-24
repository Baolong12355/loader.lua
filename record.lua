local startTime = time()
local offset = 0
local fileName = "record.txt"  -- <--- ĐẶT TÊN FILE CỐ ĐỊNH Ở ĐÂY

-- Nếu file đã tồn tại thì xóa để tạo mới
if isfile(fileName) then
    delfile(fileName)
end
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
    local text = name .. " " .. serializedArgs .. "\n"
    print(text)

    if name == "PlaceTower" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:placeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "SellTower" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:sellTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "TowerUpgradeRequest" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:upgradeTower(" .. serializedArgs .. ")\n")
        startTime = time() - offset

    elseif name == "ChangeQueryType" then
        appendfile(fileName, "task.wait(" .. tostring((time() - offset) - startTime) .. ")\n")
        appendfile(fileName, "TDX:changeQueryType(" .. serializedArgs .. ")\n")
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

print("✅ Ghi macro TDX đã bắt đầu (luôn dùng tên record.txt).")

-- Gộp logger giá nâng cấp tower (real-time Heartbeat, lưu lịch sử) & rewrite macro thành 1 script
-- Đảm bảo đúng giá, đúng vị trí X cho upgrade/sell/changeTarget, không lỗi tonumber

local txtFile = "record.txt"
local outJson = "tdx/macros/o.json"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local PlayerScripts = player:WaitForChild("PlayerScripts")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

-- SafeRequire
local function SafeRequire(module)
    local success, result = pcall(require, module)
    return success and result or nil
end

-- Load TowerClass
local TowerClass
do
    local client = PlayerScripts:WaitForChild("Client")
    local gameClass = client:WaitForChild("GameClass")
    local towerModule = gameClass:WaitForChild("TowerClass")
    TowerClass = SafeRequire(towerModule)
    if not TowerClass then return end
end

-- Lấy vị trí tower
local function GetTowerPosition(tower)
    if not tower or not tower.Character then return nil end
    local ok, pos = pcall(function()
        local model = tower.Character:GetCharacterModel()
        local root = model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
        return root and root.Position
    end)
    if ok and pos then
        return {x = tonumber(string.format("%.8g", pos.X)), y = tonumber(string.format("%.8g", pos.Y)), z = tonumber(string.format("%.8g", pos.Z))}
    end
    return nil
end

-- Lấy giá nâng cấp path (SỬA LỖI: chỉ trả về số, không truyền base, không lỗi)
local function GetUpgradeCost(tower, path)
    if not tower or not tower.LevelHandler then
        return 0
    end
    local lvl = tower.LevelHandler:GetLevelOnPath(path)
    if lvl < tower.LevelHandler:GetMaxLevel() then
        local ok, cost = pcall(function()
            return tower.LevelHandler:GetLevelUpgradeCost(path, lvl + 1)
        end)
        if ok and cost ~= nil then
            local coststr = tostring(cost):gsub("[^%d]", "")
            local num = tonumber(coststr)
            return num or 0
        end
    end
    return 0
end

-- Lấy giá đặt tower từ UI
local function GetTowerPlaceCostByName(name)
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return 0 end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return 0 end
    local bottomBar = interface:FindFirstChild("BottomBar")
    if not bottomBar then return 0 end
    local towersBar = bottomBar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end
    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == name then
            local costFrame = tower:FindFirstChild("CostFrame")
            local costText = costFrame and costFrame:FindFirstChild("CostText")
            if costText then
                local raw = tostring(costText.Text):gsub("%D", "")
                return tonumber(raw) or 0
            end
        end
    end
    return 0
end

-- Tạo folder nếu cần
if makefolder then
    pcall(function() makefolder("tdx") end)
    pcall(function() makefolder("tdx/macros") end)
end

-- Lịch sử hash cho từng frame
local frame = 0
local history = {} -- { {tick, hash, x, y, z, path1, path2} }

RunService.Heartbeat:Connect(function()
    frame = frame + 1
    local towers = TowerClass.GetTowers()
    for hash, tower in pairs(towers) do
        if type(tower) == "table" then
            local pos = GetTowerPosition(tower)
            if pos then
                local path1 = GetUpgradeCost(tower, 1)
                local path2 = GetUpgradeCost(tower, 2)
                table.insert(history, {
                    tick = frame,
                    hash = tostring(hash),
                    x = pos.x,
                    y = pos.y,
                    z = pos.z,
                    path1 = path1,
                    path2 = path2,
                })
            end
        end
    end
end)

-- Tra lịch sử hash -> {tick, x, path1, path2} gần nhất về trước tick yêu cầu
local function findHistory(hash, tick)
    local res
    for i = #history,1,-1 do
        local h = history[i]
        if h.hash == hash and h.tick <= tick then
            res = h
            break
        end
    end
    return res
end

-- Rewrite macro mỗi khi file record thay đổi
local lastMacro = ""
while true do
    if isfile(txtFile) then
        local macro = readfile(txtFile)
        if macro ~= lastMacro then
            local logs = {}
            local macroLines = {}
            for l in macro:gmatch("[^\r\n]+") do table.insert(macroLines, l) end

            for idx, line in ipairs(macroLines) do
                -- PlaceTower
                local x, name, y, rot, z, a1 = line:match('TDX:placeTower%(([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^,]+),%s*([^%)]+)%)')
                if x and name and y and rot and z and a1 then
                    name = tostring(name):gsub('^%s*"(.-)"%s*$', '%1')
                    local cost = GetTowerPlaceCostByName(name)
                    local vector = string.format("%.8g, %.8g, %.8g", tonumber(x), tonumber(y), tonumber(z))
                    table.insert(logs, {
                        TowerPlaceCost = cost,
                        TowerPlaced = name,
                        TowerVector = vector,
                        Rotation = tonumber(rot),
                        TowerA1 = tostring(a1)
                    })
                else
                    -- UpgradeTower
                    local hash, path = line:match('TDX:upgradeTower%(([^,]+),%s*([^,]+),')
                    if hash and path then
                        local h = findHistory(hash, idx)
                        if h then
                            local price = tonumber(path) == 1 and h.path1 or h.path2
                            table.insert(logs, {
                                UpgradeCost = price,
                                UpgradePath = tonumber(path),
                                TowerUpgraded = h.x
                            })
                        end
                    else
                        -- ChangeQueryType
                        local hash, targetType = line:match('TDX:changeQueryType%(([^,]+),%s*([^%)]+)%)')
                        if hash and targetType then
                            local h = findHistory(hash, idx)
                            if h then
                                table.insert(logs, {
                                    ChangeTarget = h.x,
                                    TargetType = tonumber(targetType)
                                })
                            end
                        else
                            -- SellTower
                            local hash = line:match('TDX:sellTower%(([^%)]+)%)')
                            if hash then
                                local h = findHistory(hash, idx)
                                if h then
                                    table.insert(logs, {
                                        SellTower = h.x
                                    })
                                end
                            end
                        end
                    end
                end
            end

            writefile(outJson, HttpService:JSONEncode(logs))
            lastMacro = macro
        end
    end
    task.wait(0.02) -- Cực nhanh, vẫn an toàn!
end
