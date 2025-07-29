-- Script: recorder_moving_skill_raw.lua
-- Mục đích: Ghi log thô các lần sử dụng skill di chuyển (moving skill) cho các tower Helio, Cryo Helio, Jet Trooper (skill 1,3), Cryo Helio (skill 1)
-- Ghi trực tiếp các args vào file log, không cần wave/time.

local replStorage = game:GetService("ReplicatedStorage")
local remotes = replStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = remotes:WaitForChild("TowerUseAbilityRequest")
local localPlayer = game:GetService("Players").LocalPlayer

-- Cấu hình các tower và skill index cần log
local TOWER_MOVING_SKILL = {
    ["Helicopter"] = {1, 3},
    ["Cryo Helicopter"] = {1},
    ["Jet Trooper"] = {1},
}

-- File log (có thể chỉnh lại đường dẫn)
local outFile = "tdx/moving_skill_log_raw.txt"

-- Lấy type tower theo hash (dựa vào TowerClass nếu có)
local function getTowerTypeByHash(hash)
    local success, TowerClass = pcall(function()
        local ps = localPlayer:FindFirstChild("PlayerScripts")
        local client = ps and ps:FindFirstChild("Client")
        local gameClass = client and client:FindFirstChild("GameClass")
        local towerModule = gameClass and gameClass:FindFirstChild("TowerClass")
        return require(towerModule)
    end)
    if success and TowerClass and TowerClass.GetTowers then
        local towers = TowerClass.GetTowers()
        local tower = towers and towers[hash]
        if tower then return tower.Type or tower.Name end
    end
    return nil
end

local function writeRawLog(args)
    local data = {}
    for i,v in ipairs(args) do
        table.insert(data, tostring(v))
    end
    local logLine = table.concat(data, " | ") .. "\n"
    if appendfile then
        appendfile(outFile, logLine)
    else
        print("[MovingSkillRawLog]", logLine)
    end
end

-- Hook namecall để log khi sử dụng moving skill (log raw args)
local originalNamecall
originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    if getnamecallmethod() == "InvokeServer" and self == TowerUseAbilityRequest and not checkcaller() then
        local args = {...}
        local hash = args[1]
        local skillIdx = args[2]
        -- Xác định tower type & có phải skill di chuyển không
        local ttype = getTowerTypeByHash(hash)
        if ttype and TOWER_MOVING_SKILL[ttype] then
            for _, idx in ipairs(TOWER_MOVING_SKILL[ttype]) do
                if skillIdx == idx then
                    writeRawLog(args)
                    break
                end
            end
        end
    end
    return originalNamecall(self, ...)
end)

print("✅ Recorder Moving Skill RAW đã hoạt động - Log thô các args khi dùng skill di chuyển!")