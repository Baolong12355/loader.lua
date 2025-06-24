-- TDX Macro Recorder (Safe, không bỏ sót trứng/nâng cấp)
-- Ghi lại mọi thao tác đặt, nâng cấp, bán, đổi target, kể cả trường hợp không match tower cũ

local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- Tìm tên file macro chưa bị trùng
local fileIndex = 1
while isfile("tdx_macro_"..fileIndex..".txt") do
    fileIndex += 1
end
local fileName = "tdx_macro_"..fileIndex..".txt"
writefile(fileName, "")

local macro = {}
local placedTowers = {}

-- Lấy giá tower từ GUI (giá trị tham khảo)
local function get_tower_price_from_gui(towerName)
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then return 0 end
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return 0 end
    local bottomBar = interface:FindFirstChild("BottomBar")
    if not bottomBar then return 0 end
    local towersBar = bottomBar:FindFirstChild("TowersBar")
    if not towersBar then return 0 end
    for _, tower in ipairs(towersBar:GetChildren()) do
        if tower.Name == towerName then
            local costFrame = tower:FindFirstChild("CostFrame")
            if costFrame then
                local costText = costFrame:FindFirstChild("CostText")
                if costText then
                    local num = tonumber(costText.Text:gsub("%D", ""))
                    return num or 0
                end
            end
        end
    end
    return 0
end

local function vector3ToString(v3)
    return string.format("%.14f, %.14f, %.14f", v3.X, v3.Y, v3.Z)
end

local function append_macro(text)
    appendfile(fileName, text.."\n")
end

local function handleRemote(self, args)
    local remoteName = tostring(self.Name)
    if remoteName == "PlaceTower" then
        local towerName = tostring(args[2])
        local vector3 = args[3]
        if typeof(vector3) ~= "Vector3" then return end
        local vectorStr = vector3ToString(vector3)
        local rotation = tonumber(args[4]) or 0
        local timeNow = tostring(tick())
        local price = get_tower_price_from_gui(towerName)
        local keyX = tonumber(string.format("%.14f", vector3.X))
        placedTowers[keyX] = {
            price = price,
            towerName = towerName,
            vector = vectorStr,
            rotation = rotation,
            tick = timeNow
        }
        -- Ghi từng dòng plain text (appendfile)
        append_macro("[PlaceTower] " .. towerName .. " | Pos: " .. vectorStr .. " | Rot: " .. rotation .. " | Price: " .. price .. " | Time: " .. timeNow)
    elseif remoteName == "TowerUpgradeRequest" then
        local towerHash = tostring(args[1])
        local upgradePath = tostring(args[2])
        local info = placedTowers[tonumber(towerHash)]
        local price = info and info.price or ""
        append_macro("[Upgrade] TowerHash: " .. towerHash .. " | Path: " .. upgradePath .. " | Price: " .. tostring(price) .. " | Time: " .. tostring(tick()))
    elseif remoteName == "SellTower" then
        local towerHash = tostring(args[1])
        local info = placedTowers[tonumber(towerHash)]
        append_macro("[Sell] TowerHash: " .. towerHash .. " | Time: " .. tostring(tick()))
    elseif remoteName == "ChangeTarget" or remoteName == "ChangeQueryType" then
        local towerHash = tostring(args[1])
        local targetWanted = tostring(args[2])
        append_macro("[Target] TowerHash: " .. towerHash .. " | Target: " .. targetWanted .. " | Time: " .. tostring(tick()))
    end
end

local function getArgs(...)
    local args = {...}
    return args
end

-- Hook FireServer
local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = getArgs(...)
    pcall(handleRemote, self, args)
    return oldFireServer(self, ...)
end)

-- Hook InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = getArgs(...)
    pcall(handleRemote, self, args)
    return oldInvokeServer(self, ...)
end)

-- Hook __namecall
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    if method == "FireServer" or method == "InvokeServer" then
        local args = getArgs(...)
        pcall(handleRemote, self, args)
    end
    return oldNamecall(self, ...)
end)

print("✅ Ghi macro TDX (full, không mất trứng/nâng cấp, log đầy đủ args, dạng plain text) đã bắt đầu. File:", fileName)
