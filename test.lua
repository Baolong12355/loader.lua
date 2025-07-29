-- Script ghi lại skill di chuyển
-- Dùng cho: Helio skill 1/3, Cryo Helio, Jet Trooper skill 1
-- Format log: towermoving=x, skill index, location=pos, wave, time

local replStorage = game:GetService("ReplicatedStorage")
local remotes = replStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = remotes:WaitForChild("TowerUseAbilityRequest")
local localPlayer = game:GetService("Players").LocalPlayer
local HttpService = game:GetService("HttpService")

local outFile = "tdx/moving_skill_log.jsonl"

-- Tạo thư mục nếu cần
if makefolder then
    pcall(makefolder, "tdx")
end

-- Hàm lấy wave và time từ GUI
local function getWaveAndTime()
    local gui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not gui then return "?", "?" end
    local interface = gui:FindFirstChild("Interface")
    if not interface then return "?", "?" end
    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
    if not gameInfoBar then return "?", "?" end
    local wave = gameInfoBar:FindFirstChild("Wave")
    local timeLeft = gameInfoBar:FindFirstChild("TimeLeft")
    if not wave or not timeLeft then return "?", "?" end
    local waveText = wave:FindFirstChild("WaveText")
    local timeText = timeLeft:FindFirstChild("TimeLeftText")
    return waveText and waveText.Text or "?", timeText and timeText.Text or "?"
end

-- Serialize cho JSON
local function safeSerialize(val)
    if typeof(val) == "Vector3" then
        return { x = val.X, y = val.Y, z = val.Z, _type = "Vector3" }
    elseif typeof(val) == "CFrame" then
        local pos = val.Position
        return { x = pos.X, y = pos.Y, z = pos.Z, _type = "CFrame" }
    elseif typeof(val) == "Instance" then
        return tostring(val)
    elseif typeof(val) == "table" then
        local out = {}
        for k, v in pairs(val) do
            out[k] = safeSerialize(v)
        end
        return out
    else
        return val
    end
end

-- Ghi log JSON theo dòng
local function writeJsonLog(data)
    local line = HttpService:JSONEncode(data) .. "\n"
    if appendfile then
        appendfile(outFile, line)
    else
        print("[MovingSkillJsonLog]", line)
    end
end

-- Xử lý logic ghi riêng cho skill có position (moving skill)
local function handleMovingSkill(self, args)
    if self ~= TowerUseAbilityRequest then return end
    if typeof(args) ~= "table" then return end
    local arg1, arg2, arg3 = unpack(args)
    if typeof(arg1) ~= "number" or typeof(arg2) ~= "number" or typeof(arg3) ~= "Vector3" then return end

    local wave, time = getWaveAndTime()
    local logObj = {
        towermoving = arg1,
        skill = arg2,
        location = { x = arg3.X, y = arg3.Y, z = arg3.Z },
        wave = wave,
        time = time
    }
    writeJsonLog(logObj)
end

-- Hook trực tiếp hàm InvokeServer
local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
    local args = {...}
    handleMovingSkill(self, args)
    return oldInvokeServer(self, ...)
end)

-- Hook namecall để đảm bảo không sót
local oldNameCall
oldNameCall = hookmetamethod(game, "__namecall", function(self, ...)
    if getnamecallmethod() == "InvokeServer" and self == TowerUseAbilityRequest and not checkcaller() then
        local args = {...}
        handleMovingSkill(self, args)
    end
    return oldNameCall(self, ...)
end)

print("✅ Đã hook skill di chuyển: Helio, Cryo, Jet Trooper")