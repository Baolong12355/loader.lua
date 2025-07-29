-- moving_skill_recorder.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local TowerUseAbilityRequest = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TowerUseAbilityRequest")

-- Cấu hình các tower có skill di chuyển cần record
local MOVING_SKILL_TOWERS = {
    ["Helio"] = {skills = {1, 3}},       -- Helio skill 1 và 3
    ["Cryo Helicopter"] = {skills = {1}}, -- Cryo Helio skill 1
    ["Jet Trooper"] = {skills = {1}}     -- Jet Trooper skill 1
}

-- Khởi tạo thư mục nếu chưa tồn tại
if makefolder and not isfile("tdx/macros") then
    pcall(makefolder, "tdx")
    pcall(makefolder, "tdx/macros")
end

local outputPath = "tdx/macros/moving_skills.json"

-- Hàm ghi dữ liệu vào file JSON
local function saveToFile(data)
    if not writefile then return end
    
    local existingData = {}
    if isfile(outputPath) then
        local success, content = pcall(function()
            return HttpService:JSONDecode(readfile(outputPath))
        end)
        if success and type(content) == "table" then
            existingData = content
        end
    end
    
    table.insert(existingData, data)
    
    pcall(function()
        writefile(outputPath, HttpService:JSONEncode(existingData))
    end)
end

-- Hàm lấy thông tin wave hiện tại
local function getCurrentWave()
    local playerGui = player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return "?" end
    
    local interface = playerGui:FindFirstChild("Interface")
    if not interface then return "?" end
    
    local gameInfoBar = interface:FindFirstChild("GameInfoBar")
    if not gameInfoBar then return "?" end
    
    local waveText = gameInfoBar:FindFirstChild("Wave"):FindFirstChild("WaveText")
    return waveText and waveText.Text or "?"
end

-- Hook sự kiện sử dụng skill
local function hookSkillUsage()
    local originalInvoke
    if TowerUseAbilityRequest:IsA("RemoteFunction") then
        originalInvoke = hookfunction(TowerUseAbilityRequest.InvokeServer, function(self, ...)
            if self == TowerUseAbilityRequest and not checkcaller() then
                local args = {...}
                if #args >= 3 and typeof(args[3]) == "Vector3" then
                    local hash, skillIndex, targetPos = args[1], args[2], args[3]
                    
                    -- Lấy thông tin tower
                    local tower = require(player.PlayerScripts.Client.GameClass.TowerClass).GetTowers()[hash]
                    if tower and MOVING_SKILL_TOWERS[tower.Type] then
                        local validSkills = MOVING_SKILL_TOWERS[tower.Type].skills
                        if table.find(validSkills, skillIndex) then
                            -- Tạo bản ghi
                            local record = {
                                TowerType = tower.Type,
                                TowerHash = hash,
                                SkillIndex = skillIndex,
                                Position = {
                                    X = math.floor(targetPos.X * 100)/100,
                                    Y = math.floor(targetPos.Y * 100)/100,
                                    Z = math.floor(targetPos.Z * 100)/100
                                },
                                Wave = getCurrentWave(),
                                Timestamp = os.time()
                            }
                            
                            -- Lưu vào file
                            saveToFile(record)
                            print(string.format("[Recorder] Đã ghi %s skill %d tại vị trí %s", 
                                tower.Type, skillIndex, tostring(targetPos)))
                        end
                    end
                end
            end
            return originalInvoke(self, ...)
        end)
    end
    
    -- Hook namecall để bắt mọi trường hợp
    local originalNamecall
    originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() == "InvokeServer" and self == TowerUseAbilityRequest and not checkcaller() then
            local args = {...}
            if #args >= 3 and typeof(args[3]) == "Vector3" then
                local hash, skillIndex, targetPos = args[1], args[2], args[3]
                
                -- Lấy thông tin tower
                local tower = require(player.PlayerScripts.Client.GameClass.TowerClass).GetTowers()[hash]
                if tower and MOVING_SKILL_TOWERS[tower.Type] then
                    local validSkills = MOVING_SKILL_TOWERS[tower.Type].skills
                    if table.find(validSkills, skillIndex) then
                        -- Tạo bản ghi
                        local record = {
                            TowerType = tower.Type,
                            TowerHash = hash,
                            SkillIndex = skillIndex,
                            Position = {
                                X = math.floor(targetPos.X * 100)/100,
                                Y = math.floor(targetPos.Y * 100)/100,
                                Z = math.floor(targetPos.Z * 100)/100
                            },
                            Wave = getCurrentWave(),
                            Timestamp = os.time()
                        }
                        
                        -- Lưu vào file
                        saveToFile(record)
                        print(string.format("[Recorder] Đã ghi %s skill %d tại vị trí %s", 
                            tower.Type, skillIndex, tostring(targetPos)))
                    end
                end
            end
        end
        return originalNamecall(self, ...)
    end)
end

-- Khởi động recorder
if hookfunction and hookmetamethod then
    hookSkillUsage()
    print("Moving Skill Recorder đã khởi động! Đang ghi lại các skill di chuyển...")
else
    warn("Không thể khởi động recorder do thiếu hàm hook")
end

return {
    Config = MOVING_SKILL_TOWERS,
    OutputPath = outputPath
}