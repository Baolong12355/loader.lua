-- GITHUB SESSION MANAGEMENT - OPTIMIZED VERSION
-- Chỉ tạo session khi bắt đầu, xóa khi tắt - KHÔNG timeout, KHÔNG heartbeat
-- Hỗ trợ Base64 Token Decode

local keyURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/key2.txt"
local jsonURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/i.json"
local macroFolder = "tdx/macros"
local macroFile = macroFolder.."/x.json"
local loaderURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/main/loader.lua"
local skipWaveURL = "https://raw.githubusercontent.com/Baolong12355/loader.lua/refs/heads/main/auto_skip.lua"

-- GITHUB CONFIGURATION
-- Nhập Base64 encoded token vào đây thay vì token thật
local GITHUB_TOKEN_BASE64 = "Z2hwX0p5WGtieFlqZHNwZ3p2M3pBam1RU2tEY1NzY2RnaDBlUnNPeQ==" -- Base64 encoded GitHub token

local GITHUB_REPO = "Baolong12355/loader.lua"
local SESSIONS_FILE = "sessions.json" -- File trong repo để lưu sessions
local GITHUB_API_URL = "https://api.github.com/repos/" .. GITHUB_REPO .. "/contents/" .. SESSIONS_FILE

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- CONFIGURATION
local MAX_SESSIONS_PER_KEY = 3 -- Số session tối đa mỗi key

-- Decode Base64 token
local function decodeGitHubToken()
    -- Kiểm tra xem có token base64 không
    if not GITHUB_TOKEN_BASE64 or GITHUB_TOKEN_BASE64 == "" then
        error("[❌] GITHUB_TOKEN_BASE64 không được để trống!")
    end
    
    local success, decodedToken = pcall(function()
        return HttpService:base64decode(GITHUB_TOKEN_BASE64)
    end)
    
    if success and decodedToken and decodedToken ~= "" then
        print("[🔓] GitHub token đã được decode thành công")
        return decodedToken
    else
        warn("[❌] Lỗi decode Base64 token. Kiểm tra lại GITHUB_TOKEN_BASE64")
        warn("[ℹ️] Current Base64:", GITHUB_TOKEN_BASE64:sub(1, 20) .. "...")
        error("[❌] Không thể decode GitHub token từ Base64!")
    end
end

-- Get decoded token
local GITHUB_TOKEN = decodeGitHubToken()

-- Headers cho GitHub API
local function getHeaders()
    return {
        ["Authorization"] = "token " .. GITHUB_TOKEN,
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "TDX-SessionManager/1.0"
    }
end

-- Validate GitHub token
local function validateGitHubToken()
    local success, response = pcall(function()
        return request({
            Url = "https://api.github.com/user",
            Method = "GET",
            Headers = getHeaders()
        })
    end)
    
    if success and response.StatusCode == 200 then
        local userData = HttpService:JSONDecode(response.Body)
        print("[✅] GitHub token hợp lệ cho user:", userData.login)
        return true
    else
        error("[❌] GitHub token không hợp lệ! Kiểm tra lại token.")
    end
end

-- Đọc sessions từ GitHub
local function getSessionsFromGitHub()
    local success, response = pcall(function()
        return request({
            Url = GITHUB_API_URL,
            Method = "GET",
            Headers = getHeaders()
        })
    end)
    
    if success and response.StatusCode == 200 then
        local data = HttpService:JSONDecode(response.Body)
        -- Decode base64 content
        local content = HttpService:base64decode(data.content)
        local sessions = HttpService:JSONDecode(content)
        return sessions, data.sha
    elseif success and response.StatusCode == 404 then
        -- File chưa tồn tại, tạo mới
        return {}, nil
    else
        warn("[❌] Failed to get sessions from GitHub:", response and response.StatusCode or "Unknown error")
        return nil, nil
    end
end

-- Lưu sessions lên GitHub
local function saveSessionsToGitHub(sessions, sha)
    local content = HttpService:JSONEncode(sessions)
    local encodedContent = HttpService:base64encode(content)
    
    local requestData = {
        message = "Update sessions - " .. os.date("%Y-%m-%d %H:%M:%S"),
        content = encodedContent
    }
    
    if sha then
        requestData.sha = sha
    end
    
    local success, response = pcall(function()
        return request({
            Url = GITHUB_API_URL,
            Method = "PUT",
            Headers = getHeaders(),
            Body = HttpService:JSONEncode(requestData)
        })
    end)
    
    if success and (response.StatusCode == 200 or response.StatusCode == 201) then
        local responseData = HttpService:JSONDecode(response.Body)
        return true, responseData.content.sha
    else
        warn("[❌] Failed to save sessions to GitHub:", response and response.StatusCode or "Unknown error")
        return false, sha
    end
end

-- Generate unique session ID
local function generateSessionId()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    local result = ""
    for i = 1, 16 do
        result = result .. chars:sub(math.random(1, #chars), math.random(1, #chars))
    end
    return result .. "_" .. Players.LocalPlayer.UserId .. "_" .. math.floor(tick())
end

-- Validate key
local function validateKey(key)
    local success, response = pcall(function()
        return game:HttpGet(keyURL)
    end)

    if not success then
        warn("[✘] Failed to fetch key list:", response)
        return false
    end

    for line in response:gmatch("[^\r\n]+") do
        if line:match("^%s*(.-)%s*$") == key then
            return true
        end
    end
    return false
end

-- Thêm session mới vào GitHub
local function addSessionToGitHub(key)
    local sessions, sha = getSessionsFromGitHub()
    if not sessions then
        warn("[❌] Cannot get sessions from GitHub")
        return false, 0, nil
    end
    
    local keySessions = sessions[key] or {}
    local activeCount = 0
    for _ in pairs(keySessions) do activeCount = activeCount + 1 end
    
    -- Check session limit
    if activeCount >= MAX_SESSIONS_PER_KEY then
        return false, activeCount, nil
    end
    
    -- Create new session
    local sessionId = generateSessionId()
    local currentTime = os.time()
    
    keySessions[sessionId] = {
        userId = Players.LocalPlayer.UserId,
        username = Players.LocalPlayer.Name,
        startTime = currentTime,
        gameId = game.GameId,
        placeId = game.PlaceId,
        server = game.JobId or "Unknown"
    }
    
    sessions[key] = keySessions
    
    -- Save to GitHub
    local saveSuccess, newSha = saveSessionsToGitHub(sessions, sha)
    if not saveSuccess then
        warn("[❌] Failed to save session to GitHub")
        return false, activeCount, nil
    end
    
    print(string.format("[✅] Session added! Active sessions: %d/%d", 
        activeCount + 1, MAX_SESSIONS_PER_KEY))
    print("[ℹ️] Session ID:", sessionId:sub(1, 12) .. "...")
    
    return true, activeCount + 1, sessionId
end

-- Xóa session khỏi GitHub
local function removeSessionFromGitHub(key, sessionId)
    if not key or not sessionId then 
        warn("[⚠️] Missing key or sessionId for removal")
        return false 
    end
    
    local sessions, sha = getSessionsFromGitHub()
    if not sessions then 
        warn("[❌] Cannot get sessions for removal")
        return false 
    end
    
    if sessions[key] and sessions[key][sessionId] then
        local sessionData = sessions[key][sessionId]
        local duration = os.time() - sessionData.startTime
        
        print(string.format("[🏁] Removing session: %s (Duration: %d minutes)", 
            sessionData.username, math.floor(duration / 60)))
        
        sessions[key][sessionId] = nil
        
        -- Xóa key nếu không còn session nào
        if next(sessions[key]) == nil then
            sessions[key] = nil
        end
        
        -- Save to GitHub
        local success, newSha = saveSessionsToGitHub(sessions, sha)
        if success then
            print("[✅] Session removed successfully")
        else
            warn("[❌] Failed to remove session from GitHub")
        end
        return success
    else
        warn("[⚠️] Session not found for removal:", sessionId:sub(1, 12) .. "...")
        return false
    end
end

-- Setup shutdown handlers - chỉ xóa session khi thực sự tắt
local function setupShutdownHandlers(key, sessionId)
    local sessionRemoved = false
    
    local function removeSession()
        if not sessionRemoved then
            sessionRemoved = true
            print("[📴] Script ending, removing session...")
            removeSessionFromGitHub(key, sessionId)
        end
    end
    
    -- Handle game closing
    game:BindToClose(function()
        removeSession()
        wait(3) -- Đảm bảo có thời gian để API call hoàn thành
    end)
    
    -- Handle teleport/server hop
    Players.LocalPlayer.OnTeleport:Connect(function()
        removeSession()
    end)
    
    -- Handle player leaving game
    Players.LocalPlayer.AncestryChanged:Connect(function()
        if not Players.LocalPlayer.Parent then
            removeSession()
        end
    end)
    
    -- Handle manual script stop
    getgenv().endTDXSession = function()
        removeSession()
        getgenv().TDX_SessionActive = false
        print("[🔴] Session ended manually")
    end
end

-- Command để check active sessions (debug)
getgenv().checkActiveSessions = function()
    local sessions, sha = getSessionsFromGitHub()
    if sessions then
        print("\n=== ACTIVE SESSIONS ===")
        local totalSessions = 0
        for key, keySessions in pairs(sessions) do
            local keyCount = 0
            print("Key:", key:sub(1, 8) .. "...")
            for sessionId, sessionData in pairs(keySessions) do
                local timeActive = os.time() - sessionData.startTime
                print(string.format("  - %s (%s) | Started: %s ago", 
                    sessionData.username, 
                    sessionId:sub(1, 8) .. "...", 
                    math.floor(timeActive / 60) .. "m"))
                keyCount = keyCount + 1
                totalSessions = totalSessions + 1
            end
            print(string.format("  Total for this key: %d/%d", keyCount, MAX_SESSIONS_PER_KEY))
        end
        print("Total active sessions:", totalSessions)
        print("======================\n")
    else
        print("[❌] Failed to get sessions")
    end
end

-- Command để force remove session (emergency)
getgenv().forceRemoveSession = function(targetSessionId)
    if not targetSessionId then
        print("[❌] Usage: getgenv().forceRemoveSession('session_id')")
        return
    end
    
    local sessions, sha = getSessionsFromGitHub()
    if not sessions then return end
    
    for key, keySessions in pairs(sessions) do
        if keySessions[targetSessionId] then
            sessions[key][targetSessionId] = nil
            if next(sessions[key]) == nil then
                sessions[key] = nil
            end
            
            local success = saveSessionsToGitHub(sessions, sha)
            if success then
                print("[✅] Force removed session:", targetSessionId:sub(1, 12) .. "...")
            else
                print("[❌] Failed to force remove session")
            end
            return
        end
    end
    
    print("[❌] Session not found:", targetSessionId:sub(1, 12) .. "...")
end

-- Command để update GitHub token (nếu cần thay đổi)
getgenv().updateGitHubToken = function(newBase64Token)
    if not newBase64Token then
        print("[❌] Usage: getgenv().updateGitHubToken('new_base64_token')")
        return
    end
    
    GITHUB_TOKEN_BASE64 = newBase64Token
    GITHUB_TOKEN = decodeGitHubToken()
    print("[✅] GitHub token đã được cập nhật!")
    
    -- Validate new token
    validateGitHubToken()
end

-- ============ MAIN EXECUTION ============

print("[🔧] Đang khởi tạo GitHub Session Management...")
print("[🔓] Đang decode GitHub token...")

-- Validate GitHub token trước khi bắt đầu
validateGitHubToken()

-- Get key from config
local inputKey = getgenv().TDX_Config and getgenv().TDX_Config.Key
if not inputKey or inputKey == "" then
    warn("[✘] No key found in getgenv().TDX_Config.Key")
    warn("[ℹ] Please set your key before running this script")
    return
end

local cleanKey = inputKey:match("^%s*(.-)%s*$")
if not cleanKey or #cleanKey == 0 then
    warn("[✘] Invalid key format")
    return
end

print("[ℹ] Validating key:", cleanKey:sub(1, 8) .. "...")

-- Validate key
if not validateKey(cleanKey) then
    warn("[✘] Invalid key:", cleanKey:sub(1, 8) .. "...")
    return
end

print("[✔] Key valid! Adding session to GitHub...")

-- Add session to GitHub
local success, activeCount, sessionId = addSessionToGitHub(cleanKey)
if not success then
    warn(string.format("[✘] Cannot start session! Active sessions: %d/%d", 
        activeCount or 0, MAX_SESSIONS_PER_KEY))
    warn("[ℹ] Wait for other sessions to end or use a different key")
    return
end

print("[✔] Session created successfully!")

-- Set global variables
getgenv().TDX_SessionActive = true
getgenv().TDX_SessionId = sessionId
getgenv().TDX_SessionKey = cleanKey

-- Setup shutdown handlers (chỉ xóa khi thực sự tắt)
setupShutdownHandlers(cleanKey, sessionId)

-- Create folders
if not isfolder("tdx") then makefolder("tdx") end
if not isfolder(macroFolder) then makefolder(macroFolder) end

-- Download macro
local downloadSuccess, result = pcall(function()
    return game:HttpGet(jsonURL)
end)

if downloadSuccess then
    writefile(macroFile, result)
    print("[✔] Downloaded macro file.")
else
    warn("[✘] Failed to download macro:", result)
    -- Vẫn tiếp tục chạy script, chỉ warn
end

repeat wait() until game:IsLoaded() and game.Players.LocalPlayer

getgenv().TDX_Config = {
    ["Key"] = cleanKey,
    ["mapvoting"] = "MILITARY BASE",
    ["Return Lobby"] = true,
    ["x1.5 Speed"] = true,
    ["Auto Skill"] = true,
    ["Map"] = "Tower Battles",
    ["Macros"] = "run",
    ["Macro Name"] = "i",
    ["Auto Difficulty"] = "TowerBattlesNightmare"
}

-- Load main script
loadstring(game:HttpGet(loaderURL))()

_G.WaveConfig = {
    ["WAVE 0"] = 0,
    ["WAVE 1"] = 44,
    ["WAVE 2"] = 44,
    ["WAVE 3"] = 44,
    ["WAVE 4"] = 44,
    ["WAVE 5"] = 44,
    ["WAVE 6"] = 44,
    ["WAVE 7"] = 44,
    ["WAVE 8"] = 44,
    ["WAVE 9"] = 44,
    ["WAVE 10"] = 44,
    ["WAVE 11"] = 44, 
    ["WAVE 12"] = 44, 
    ["WAVE 13"] = 40,
    ["WAVE 14"] = 40,
    ["WAVE 15"] = 40,
    ["WAVE 16"] = 44,
    ["WAVE 17"] = 44,
    ["WAVE 18"] = 15,
    ["WAVE 19"] = 15,
    ["WAVE 20"] = 44,
    ["WAVE 21"] = 44,
    ["WAVE 22"] = 44,
    ["WAVE 23"] = 44,
    ["WAVE 24"] = 44,
    ["WAVE 25"] = 44,
    ["WAVE 26"] = 44,
    ["WAVE 27"] = 25,
    ["WAVE 28"] = 144,
    ["WAVE 29"] = 20,
    ["WAVE 30"] = 200,
    ["WAVE 31"] = 135,
    ["WAVE 32"] = 44,
    ["WAVE 33"] = 44,
    ["WAVE 34"] = 44,
    ["WAVE 35"] = 44,
    ["WAVE 36"] = 125,   
    ["WAVE 37"] = 44,
    ["WAVE 38"] = 44,
    ["WAVE 39"] = 0,
    ["WAVE 40"] = 0
}

-- Load auto skip
loadstring(game:HttpGet(skipWaveURL))()

print("[🚀] TDX Script loaded with GitHub Session Management!")
print("[ℹ️] Session will auto-remove when script ends")