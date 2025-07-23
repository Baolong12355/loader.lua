local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Cấu hình
local FILENAME = "tower_upgrades_log.txt"
local TIMEOUT = 2 -- Thời gian chờ xác nhận (giây)

-- Khởi tạo file log
if isfile(FILENAME) then delfile(FILENAME) end
writefile(FILENAME, "=== LOG NÂNG CẤP TOWER ===\n")

-- Biến lưu trữ
local lastLevels = {} -- { [hash] = {path1, path2} }
local pendingRequests = {} -- Các yêu cầu đang chờ xác nhận

-- Hàm ghi log chi tiết
local function log(message)
    appendfile(FILENAME, os.date("[%H:%M:%S] ") .. message .. "\n")
end

-- Xử lý khi nhận thông báo nâng cấp từ server
ReplicatedStorage.Remotes.TowerUpgradeQueueUpdated.OnClientEvent:Connect(function(data)
    if not data or not data[1] then return end
    
    local towerData = data[1]
    local hash = towerData.Hash
    local newLevels = towerData.LevelReplicationData
    
    -- Tìm path nào thực sự thay đổi
    local changedPaths = {}
    if lastLevels[hash] then
        for path = 1, 2 do
            if (newLevels[path] or 0) > (lastLevels[hash][path] or 0) then
                table.insert(changedPaths, path)
            end
        end
    end
    
    -- Xử lý yêu cầu đang chờ
    for i, req in ipairs(pendingRequests) do
        if req.hash == hash then
            if #changedPaths > 0 then
                -- Phát hiện path không khớp
                if not table.find(changedPaths, req.path) then
                    local actualPath = changedPaths[1]
                    log(string.format("PHÁT HIỆN KHÔNG KHỚP: Yêu cầu path %d | Server nâng path %d", req.path, actualPath))
                    
                    -- Ghi lại path thực tế từ server
                    log(string.format("THỰC TẾ: upgradeTower(%d, %d, 1) - Từ level %d → %d", 
                        hash, actualPath, 
                        lastLevels[hash][actualPath] or 0, 
                        newLevels[actualPath]))
                    
                    -- Thực hiện lại với path từ server (nếu cần)
                    -- ReplicatedStorage.Remotes.TowerUpgradeRequest:FireServer(hash, actualPath, 1)
                else
                    -- Trường hợp bình thường
                    log(string.format("THÀNH CÔNG: upgradeTower(%d, %d, 1)", hash, req.path))
                end
            else
                log(string.format("LỖI: Yêu cầu path %d nhưng không path nào được nâng", req.path))
            end
            
            table.remove(pendingRequests, i)
            break
        end
    end
    
    -- Cập nhật level mới nhất
    lastLevels[hash] = newLevels
end)

-- Hook hàm FireServer
local originalFireServer
originalFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, function(self, ...)
    local args = {...}
    
    if self.Name == "TowerUpgradeRequest" and #args >= 3 then
        local hash, requestedPath, count = args[1], args[2], args[3]
        
        -- Kiểm tra tính hợp lệ
        if typeof(hash) == "number" and (requestedPath == 1 or requestedPath == 2) and count > 0 then
            -- Lưu yêu cầu vào hàng đợi chờ xác nhận
            table.insert(pendingRequests, {
                hash = hash,
                path = requestedPath,
                count = count,
                time = os.time()
            })
            
            log(string.format("GỬI YÊU CẦU: upgradeTower(%d, %d, %d)", hash, requestedPath, count))
        end
    end
    
    return originalFireServer(self, ...)
end)

-- Hook __namecall để bắt các gọi remote
local originalNamecall
originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    if getnamecallmethod() == "FireServer" and self.Name == "TowerUpgradeRequest" then
        local args = {...}
        if #args >= 3 then
            local hash, requestedPath, count = args[1], args[2], args[3]
            
            if typeof(hash) == "number" and (requestedPath == 1 or requestedPath == 2) and count > 0 then
                table.insert(pendingRequests, {
                    hash = hash,
                    path = requestedPath,
                    count = count,
                    time = os.time()
                })
                
                log(string.format("GỬI YÊU CẦU (namecall): upgradeTower(%d, %d, %d)", hash, requestedPath, count))
            end
        end
    end
    return originalNamecall(self, ...)
end)

-- Xóa các yêu cầu quá hạn
task.spawn(function()
    while true do
        task.wait(1)
        local now = os.time()
        
        for i = #pendingRequests, 1, -1 do
            if now - pendingRequests[i].time > TIMEOUT then
                local req = pendingRequests[i]
                log(string.format("HẾT HẠN: upgradeTower(%d, %d, %d) không được xác nhận", 
                    req.hash, req.path, req.count))
                table.remove(pendingRequests, i)
            end
        end
    end
end)

print("✅ Script đã sẵn sàng - Luôn ưu tiên path từ server khi có không khớp")