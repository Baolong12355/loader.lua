local replStorage = game:GetService("ReplicatedStorage")
local remotes = replStorage:WaitForChild("Remotes")
local TowerUseAbilityRequest = remotes:WaitForChild("TowerUseAbilityRequest")
local localPlayer = game:GetService("Players").LocalPlayer

-- Biến lưu hàm gốc
local originalInvokeServer

-- Hàm ghi log vào file (thêm vào nhưng không ảnh hưởng code hiện có)
local function logToFile(text)
    local filePath = "tdx/skills_log.txt"
    pcall(function() makefolder("tdx") end)
    writefile(filePath, (readfile(filePath) or "") .. text .. "\n")
end

-- Hook nguyên mẫu cho Ability Request (giữ nguyên hoàn toàn)
local function setupAbilityHook()
    if TowerUseAbilityRequest:IsA("RemoteFunction") then
        originalInvokeServer = hookfunction(TowerUseAbilityRequest.InvokeServer, function(self, ...)
            local args = {...}
            -- Chỉ thay đổi từ print sang logToFile
            local logText = string.format("[Skill Used] Hash: %s | Skill Index: %s | Position: %s",
                tostring(args[1]),
                tostring(args[2]),
                args[3] and tostring(args[3]) or "N/A")
            logToFile(logText)

            return originalInvokeServer(self, ...)
        end)
    end

    -- Hook namecall (giữ nguyên hoàn toàn)
    local originalNamecall
    originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() == "InvokeServer" and self == TowerUseAbilityRequest then
            local args = {...}
            -- Chỉ thay đổi từ print sang logToFile
            local logText = string.format("[Namecall Skill] Hash: %s | Skill Index: %s | Position: %s",
                tostring(args[1]),
                tostring(args[2]),
                args[3] and tostring(args[3]) or "N/A")
            logToFile(logText)
        end
        return originalNamecall(self, ...)
    end
end

-- Khởi tạo hook (giữ nguyên)
setupAbilityHook()

logToFile("✅ TowerUseAbilityRequest hook activated - Ready to track skills")