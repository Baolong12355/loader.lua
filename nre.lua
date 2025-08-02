-- COMPLETE MONITOR HOOK FOR SkipWaveVoteCast
-- Phiên bản đầy đủ với error handling và advanced features

-- =====================================================
-- KHỞI TẠO VARIABLES VÀ STORAGE
-- =====================================================

-- Lưu vote history
local voteHistory = {}

-- Thống kê
local stats = {
    totalVotes = 0,
    skipVotes = 0,
    continueVotes = 0,
    startTime = tick()
}

-- Config
local config = {
    enableLogging = true,
    enableFileLog = false,
    enableStats = true,
    logFileName = "skip_vote_monitor.log",
    maxHistorySize = 1000
}

-- =====================================================
-- UTILITY FUNCTIONS
-- =====================================================

-- Format timestamp thành readable string
local function formatTime(timestamp)
    local elapsed = timestamp - stats.startTime
    return string.format("[%.2fs]", elapsed)
end

-- Lưu vote vào history
local function saveVoteToHistory(vote, timestamp)
    if #voteHistory >= config.maxHistorySize then
        table.remove(voteHistory, 1) -- Remove oldest entry
    end
    
    table.insert(voteHistory, {
        time = timestamp,
        vote = vote,
        formattedTime = formatTime(timestamp)
    })
end

-- Update statistics
local function updateStats(vote)
    stats.totalVotes = stats.totalVotes + 1
    if vote then
        stats.skipVotes = stats.skipVotes + 1
    else
        stats.continueVotes = stats.continueVotes + 1
    end
end

-- Print statistics
local function printStats()
    print("📊 VOTE STATISTICS:")
    print(string.format("   Total Votes: %d", stats.totalVotes))
    print(string.format("   Skip Votes: %d (%.1f%%)", 
        stats.skipVotes, 
        stats.totalVotes > 0 and (stats.skipVotes / stats.totalVotes * 100) or 0))
    print(string.format("   Continue Votes: %d (%.1f%%)", 
        stats.continueVotes,
        stats.totalVotes > 0 and (stats.continueVotes / stats.totalVotes * 100) or 0))
    print(string.format("   Session Time: %.1fs", tick() - stats.startTime))
end

-- Write to file log
local function writeToFile(logEntry)
    if config.enableFileLog then
        local success, error = pcall(function()
            local existingContent = ""
            if isfile(config.logFileName) then
                existingContent = readfile(config.logFileName)
            end
            writefile(config.logFileName, existingContent .. logEntry .. "\n")
        end)
        
        if not success then
            warn("❌ Failed to write to log file:", error)
        end
    end
end

-- =====================================================
-- MAIN HOOK FUNCTION
-- =====================================================

local monitor_hook
monitor_hook = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    
    -- Kiểm tra nếu là FireServer call cho SkipWaveVoteCast
    if method == "FireServer" and self.Name == "SkipWaveVoteCast" then
        local args = {...}
        local timestamp = tick()
        local vote = args[1]
        
        -- Basic logging
        if config.enableLogging then
            local voteText = vote and "SKIP" or "CONTINUE"
            local logMessage = string.format(
                "%s SkipWave Vote: %s",
                formatTime(timestamp),
                voteText
            )
            print("🗳️ " .. logMessage)
        end
        
        -- Advanced logging with player info
        local player = game:GetService("Players").LocalPlayer
        if player then
            local detailedLog = string.format(
                "[%s] Player: %s | Vote: %s | Args: %s",
                os.date("%H:%M:%S", timestamp),
                player.Name,
                vote and "SKIP" or "CONTINUE",
                table.concat(args, ", ")
            )
            
            if config.enableLogging then
                print("📝 " .. detailedLog)
            end
            
            -- Write to file
            writeToFile(detailedLog)
        end
        
        -- Save to history
        saveVoteToHistory(vote, timestamp)
        
        -- Update statistics
        if config.enableStats then
            updateStats(vote)
        end
        
        -- Print recent votes (last 3)
        if #voteHistory >= 2 then
            print("📋 Recent votes:")
            local startIdx = math.max(1, #voteHistory - 2)
            for i = startIdx, #voteHistory do
                local entry = voteHistory[i]
                print(string.format("   %s %s", 
                    entry.formattedTime, 
                    entry.vote and "SKIP" or "CONTINUE"))
            end
        end
    end
    
    -- CRITICAL: Call original metamethod
    return monitor_hook(self, ...)
end)

-- =====================================================
-- CONTROL FUNCTIONS
-- =====================================================

-- Toggle logging
function toggleLogging()
    config.enableLogging = not config.enableLogging
    print("📝 Logging:", config.enableLogging and "ENABLED" or "DISABLED")
end

-- Toggle file logging
function toggleFileLog()
    config.enableFileLog = not config.enableFileLog
    print("💾 File logging:", config.enableFileLog and "ENABLED" or "DISABLED")
end

-- Toggle statistics
function toggleStats()
    config.enableStats = not config.enableStats
    print("📊 Statistics:", config.enableStats and "ENABLED" or "DISABLED")
end

-- Get vote history
function getVoteHistory()
    return voteHistory
end

-- Get statistics
function getStats()
    printStats()
    return stats
end

-- Clear history
function clearHistory()
    voteHistory = {}
    stats = {
        totalVotes = 0,
        skipVotes = 0,
        continueVotes = 0,
        startTime = tick()
    }
    print("🗑️ History and stats cleared!")
end

-- Export data
function exportData()
    local exportData = {
        history = voteHistory,
        stats = stats,
        config = config,
        exportTime = tick()
    }
    
    local success, result = pcall(function()
        local jsonString = game:GetService("HttpService"):JSONEncode(exportData)
        writefile("vote_export_" .. os.time() .. ".json", jsonString)
        return true
    end)
    
    if success then
        print("✅ Data exported successfully!")
    else
        warn("❌ Export failed:", result)
    end
end

-- =====================================================
-- INITIALIZATION
-- =====================================================

print("🚀 Complete Monitor Hook installed!")
print("📋 Available commands:")
print("   toggleLogging() - Toggle console logging")
print("   toggleFileLog() - Toggle file logging")
print("   toggleStats() - Toggle statistics")
print("   getStats() - Show current statistics")
print("   getVoteHistory() - Get vote history")
print("   clearHistory() - Clear all data")
print("   exportData() - Export data to JSON file")

-- Initial status
print("📊 Current settings:")
print("   Logging:", config.enableLogging and "ON" or "OFF")
print("   File Log:", config.enableFileLog and "ON" or "OFF")
print("   Statistics:", config.enableStats and "ON" or "OFF")

-- =====================================================
-- ERROR HANDLING WRAPPER
-- =====================================================

-- Wrap the main execution in error handling
local function safeExecute()
    local success, error = pcall(function()
        print("✅ Hook ready! Monitoring SkipWaveVoteCast...")
    end)
    
    if not success then
        warn("❌ Hook initialization error:", error)
    end
end

safeExecute()

--[[
USAGE EXAMPLES:

1. Basic monitoring:
   - Hook sẽ tự động log mọi vote
   - Xem console để theo dõi

2. Advanced usage:
   - getStats() -> Xem thống kê
   - toggleFileLog() -> Bật lưu file
   - exportData() -> Xuất dữ liệu

3. Testing:
   local args = {true}
   game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("SkipWaveVoteCast"):FireServer(unpack(args))

OUTPUT EXAMPLE:
🗳️ [15.23s] SkipWave Vote: SKIP
📝 [12:34:56] Player: YourName | Vote: SKIP | Args: true
📋 Recent votes:
   [10.45s] CONTINUE
   [15.23s] SKIP
]]