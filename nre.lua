local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- THÊM: Universal compatibility functions
local function getGlobalEnv()
    if getgenv then return getgenv() end
    if getfenv then return getfenv() end
    return _G
end

local globalEnv = getGlobalEnv()

--==============================================================================
--=                           HÀM TIỆN ÍCH (HELPERS)                           =
--==============================================================================

-- Hàm log thông tin skip wave vote
local function logSkipWaveVote(voteValue)
    local timestamp = os.date("[%H:%M:%S]")
    local status = voteValue and "YES" or "NO"
    print(string.format("%s 🗳️ Skip Wave Vote Cast: %s", timestamp, status))
end

-- Hàm xử lý skip wave vote
local function handleSkipWaveVote(args)
    if args and args[1] ~= nil then
        local voteValue = args[1]
        logSkipWaveVote(voteValue)
        
        -- Có thể thêm logic khác ở đây, ví dụ:
        -- - Ghi vào file log
        -- - Gửi thông báo
        -- - Cập nhật UI custom
        
        -- Lưu trạng thái vote vào global environment nếu cần
        globalEnv.LAST_SKIP_WAVE_VOTE = {
            value = voteValue,
            timestamp = tick(),
            player = player.Name
        }
    end
end

--==============================================================================
--=                      XỬ LÝ SỰ KIỆN & HOOKS                                 =
--==============================================================================

-- Xử lý các lệnh gọi remote
local function handleRemote(name, args)
    if name == "SkipWaveVoteCast" then
        handleSkipWaveVote(args)
    end
end

-- Hook các hàm remote
local function setupHooks()
    if not hookfunction or not hookmetamethod or not checkcaller then
        warn("Executor không hỗ trợ đầy đủ các hàm hook cần thiết.")
        return
    end

    -- Hook FireServer
    local oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
        if not checkcaller() then
            handleRemote(self.Name, {...})
        end
        return oldFireServer(self, ...)
    end)

    -- Hook InvokeServer (nếu cần thiết)
    local oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, function(self, ...)
        if not checkcaller() then
            handleRemote(self.Name, {...})
        end
        return oldInvokeServer(self, ...)
    end)

    -- Hook namecall - QUAN TRỌNG NHẤT
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if not checkcaller() then
            local method = getnamecallmethod()
            if method == "FireServer" or method == "InvokeServer" then
                handleRemote(self.Name, {...})
            end
        end
        return oldNamecall(self, ...)
    end)
end

--==============================================================================
--=                    OPTIONAL: SỰ KIỆN RESPONSE HANDLER                      =
--==============================================================================

-- Lắng nghe response từ server (nếu có)
pcall(function()
    local skipWaveRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SkipWaveVoteCast")
    
    -- Nếu có event response từ server
    if ReplicatedStorage.Remotes:FindFirstChild("SkipWaveVoteResponse") then
        ReplicatedStorage.Remotes.SkipWaveVoteResponse.OnClientEvent:Connect(function(data)
            local timestamp = os.date("[%H:%M:%S]")
            print(string.format("%s 📊 Skip Wave Vote Result: %s", timestamp, tostring(data)))
        end)
    end
end)

--==============================================================================
--=                           KHỞI TẠO                                         =
--==============================================================================

-- Khởi tạo hooks
setupHooks()

print("✅ SkipWave Vote Hook đã hoạt động!")
print("🗳️ Sẽ log tất cả skip wave votes")

-- Thêm hàm tiện ích để test (optional)
globalEnv.TDX_SKIP_WAVE = function(vote)
    vote = vote ~= false -- default true nếu không truyền gì
    local args = { vote }
    game:GetService("ReplicatedStorage"):WaitForChild("Remotes"):WaitForChild("SkipWaveVoteCast"):FireServer(unpack(args))
end

print("💡 Sử dụng: TDX_SKIP_WAVE(true) hoặc TDX_SKIP_WAVE(false) để test")