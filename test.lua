-- Kiểm tra executor có hỗ trợ writefile không
if not writefile then
    warn("writefile không được hỗ trợ bởi executor của bạn.")
    return
end

local output = {}
local function log(header, tbl)
    table.insert(output, "=== " .. header .. " ===")
    for k, v in pairs(tbl) do
        if typeof(v) == "function" then
            table.insert(output, tostring(k) .. " (" .. typeof(v) .. ")")
        end
    end
    table.insert(output, "") -- dòng trống giữa các block
end

-- Thu thập thông tin từ các môi trường
pcall(function() log("getgenv", getgenv()) end)
pcall(function() log("getrenv", getrenv()) end)
pcall(function() log("getfenv", getfenv()) end)
pcall(function() log("debug", debug or {}) end)
pcall(function() log("shared", shared or {}) end)
pcall(function() log("syn", syn or {}) end)
pcall(function() log("fluxus", fluxus or {}) end)
pcall(function() log("executor name", {Name = identifyexecutor and identifyexecutor() or getexecutorname and getexecutorname() or "Unknown"}))

-- Ghi vào file
local result = table.concat(output, "\n")
writefile("executor_functions.txt", result)

print("Đã ghi danh sách hàm vào file: executor_functions.txt")