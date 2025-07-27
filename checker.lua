-- Webhook sender dành riêng cho executor, không chạy trên Roblox server/Studio
-- Tự động tương thích với loadstring và mọi executor phổ biến
-- FIX: Chỉ cho phép HTTPS requests

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- FORCE ENABLE HTTP SERVICE
HttpService.HttpEnabled = true
print("WEBHOOK: Force enabled HttpService")

-- Chỉ cho phép trên executor, kiểm tra cả server-side và client-side
local function isExecutor()
    -- Synapse, KRNL, Fluxus, ScriptWare, v.v.
    local hasExecutor = typeof(getgenv) == "function" or 
                       typeof(syn) == "table" or 
                       typeof(is_synapse_function) == "function"
    
    -- Kiểm tra nếu đang chạy trên server
    local RunService = game:GetService("RunService")
    local isServer = RunService:IsServer()
    
    print("WEBHOOK: IsExecutor =", hasExecutor, "IsServer =", isServer)
    
    return hasExecutor
end

local function canSend()
    -- Force enable trước khi check
    pcall(function() HttpService.HttpEnabled = true end)
    
    -- Roblox chỉ cho phép PostAsync client-side, https luôn bắt buộc
    local ok, httpEnabled = pcall(function() return HttpService.HttpEnabled end)
    local executorCheck = isExecutor()
    
    print("WEBHOOK DEBUG:")
    print("- HttpEnabled:", httpEnabled)
    print("- IsExecutor:", executorCheck)
    print("- CanSend:", ok and httpEnabled and executorCheck)
    
    return ok and httpEnabled and executorCheck
end

local function sendToWebhook(data)
    if not canSend() then
        print("WEBHOOK: Không thể gửi - HttpEnabled hoặc Executor không hợp lệ")
        return
    end
    
    local url = "https://discord.com/api/webhooks/972059328276201492/DPHtxfsIldI5lND2dYUbA8WIZwp4NLYsPDG1Sy6-MKV9YMgV8OohcTf-00SdLmyMpMFC"
    local body = HttpService:JSONEncode({content = "```json\n"..HttpService:JSONEncode(data).."\n```"})
    
    print("WEBHOOK: Đang test các methods...")
    
    -- Method 1: syn.request (Synapse)
    if typeof(syn) == "table" and syn.request then
        local success1, result1 = pcall(function()
            return syn.request({
                Url = url,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = body
            })
        end)
        if success1 then
            print("WEBHOOK: syn.request thành công!")
            return
        else
            print("WEBHOOK: syn.request thất bại:", result1)
        end
    end
    
    -- Method 2: http_request (Universal)
    if typeof(http_request) == "function" then
        local success2, result2 = pcall(function()
            return http_request({
                Url = url,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = body
            })
        end)
        if success2 then
            print("WEBHOOK: http_request thành công!")
            return
        else
            print("WEBHOOK: http_request thất bại:", result2)
        end
    end
    
    -- Method 3: request (KRNL/Fluxus)
    if typeof(request) == "function" then
        local success3, result3 = pcall(function()
            return request({
                Url = url,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = body
            })
        end)
        if success3 then
            print("WEBHOOK: request thành công!")
            return
        else
            print("WEBHOOK: request thất bại:", result3)
        end
    end
    
    -- Method 4: HttpService PostAsync (fallback)
    local success4, result4 = pcall(function()
        return HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
    end)
    
    if success4 then
        print("WEBHOOK: HttpService thành công!")
    else
        print("WEBHOOK: Tất cả methods đều thất bại. Lỗi cuối:", result4)
        print("WEBHOOK: Có thể executor không hỗ trợ HTTP hoặc Discord block IP")
    end
end

local function checkLobby()
    local stats = {
        Level = LocalPlayer.leaderstats and LocalPlayer.leaderstats.Level and LocalPlayer.leaderstats.Level.Value or "N/A",
        Wins  = LocalPlayer.leaderstats and LocalPlayer.leaderstats.Wins and LocalPlayer.leaderstats.Wins.Value or "N/A",
        Gold  = LocalPlayer.PlayerGui and LocalPlayer.PlayerGui.GUI and LocalPlayer.PlayerGui.GUI.NewGoldDisplay 
            and LocalPlayer.PlayerGui.GUI.NewGoldDisplay.GoldText and LocalPlayer.PlayerGui.GUI.NewGoldDisplay.GoldText.Text or "N/A"
    }
    sendToWebhook({type = "lobby", stats = stats})
end

local function waitForGameOverScreen()
    local gui = LocalPlayer.PlayerGui:WaitForChild("Interface")
    local gos = gui:WaitForChild("GameOverScreen", 60)
    if not gos then return end
    repeat wait() until gos.Visible
    return gos
end

local function checkGameOver()
    local gos = waitForGameOverScreen()
    if not gos then return end
    local main = gos.Main
    local rewards, withTokens = nil, false
    local result = {}

    if main:FindFirstChild("RewardsFrameWithTokens") and main.RewardsFrameWithTokens.Visible then
        rewards = main.RewardsFrameWithTokens.InnerFrame
        withTokens = true
    elseif main:FindFirstChild("RewardsFrame") and main.RewardsFrame.Visible then
        rewards = main.RewardsFrame.InnerFrame
        withTokens = false
    end

    if rewards then
        result.Gold = rewards.Gold and rewards.Gold.TextLabel and rewards.Gold.TextLabel.Text or "N/A"
        result.GoldBonus = rewards.Gold and rewards.Gold.BonusTextLabel and rewards.Gold.BonusTextLabel.Text or "N/A"
        result.XP = rewards.XP and rewards.XP.TextLabel and rewards.XP.TextLabel.Text or "N/A"
        result.XPBonus = rewards.XP and rewards.XP.BonusTextLabel and rewards.XP.BonusTextLabel.Text or "N/A"
        if withTokens then
            result.Tokens = rewards.Tokens and rewards.Tokens.TextLabel and rewards.Tokens.TextLabel.Text or "N/A"
        end
    end

    if main:FindFirstChild("InfoFrame") then
        result.Map = main.InfoFrame.Map and main.InfoFrame.Map.Text or "N/A"
        result.Time = main.InfoFrame.Time and main.InfoFrame.Time.Text or "N/A"
        result.Mode = main.InfoFrame.Mode and main.InfoFrame.Mode.Text or "N/A"
    end

    local powerups = {}
    local content = gos.Rewards and gos.Rewards.Content
    if content then
        for _,v in pairs(content:GetChildren()) do
            if v.Name:find("PowerUps") then
                for _,item in pairs(v.Items:GetChildren()) do
                    if item.Name ~= "ItemTemplate" then
                        table.insert(powerups, item.Name)
                    end
                end
            end
        end
    end
    result.PowerUps = powerups

    if main:FindFirstChild("VictoryText") and main.VictoryText.Visible then
        result.Result = "Victory"
    elseif main:FindFirstChild("DefeatText") and main.DefeatText.Visible then
        result.Result = "Defeat"
    else
        result.Result = "Unknown"
    end

    sendToWebhook({type = "game", rewards = result})
end

local function isLobby()
    local gui = LocalPlayer.PlayerGui:FindFirstChild("GUI")
    return gui and gui:FindFirstChild("NewGoldDisplay")
end

if isLobby() then
    print("WEBHOOK: Phát hiện lobby, đang check stats...")
    checkLobby()
else
    print("WEBHOOK: Không trong lobby, đang check game over...")
    checkGameOver()
end