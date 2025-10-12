-- gui text logger
-- tìm và log mọi thuộc tính text + path vào file json
-- lowercase strings và comment theo yêu cầu người dùng

local http = game:GetService("HttpService")
local players = game:GetService("Players")

local file_name = "gui_text_log.json"
local roots = {
    game:GetService("CoreGui"),
    players.LocalPlayer and players.LocalPlayer:FindFirstChild("PlayerGui"),
    game:GetService("StarterGui"),
    game:GetService("Workspace"),
    game:GetService("Lighting"),
}

-- helper: tạo đường dẫn từ game tới object
local function get_path(inst)
    local parts = {}
    local cur = inst
    while cur and cur.Name ~= "" do
        table.insert(parts, 1, cur.Name .. " (" .. cur.ClassName .. ")")
        cur = cur.Parent
    end
    if #parts == 0 then
        return inst.ClassName
    end
    return "game." .. table.concat(parts, ".")
end

-- helper: an toàn lấy text nếu có
local function safe_get_text(inst)
    local ok, value = pcall(function()
        return inst.Text
    end)
    if ok and value ~= nil then
        return tostring(value)
    end

    -- textmesh / textmesh3d (thường dùng .Text too) - pcall covers most
    return nil
end

-- lưu data vào file (json)
local function save_to_file(tbl)
    local content = http:JSONEncode(tbl)
    -- pretty print small
    local ok, err = pcall(function()
        if writefile then
            writefile(file_name, content)
        elseif syn and syn.write_file then
            syn.write_file(file_name, content)
        elseif write_file then
            -- some exploits have other api
            write_file(file_name, content)
        else
            error("no writefile available")
        end
    end)
    if not ok then
        -- fallback: in ra console
        warn("gui text logger: couldn't write file, printing to console. reason:", err)
        print(content)
    end
end

-- bảng chứa log: list of {path=..., text=..., class=..., ts=...}
local log_entries = {}

-- index lookup để cập nhật nhanh (path => index)
local index_by_path = {}

local function record_entry(inst, text)
    if not inst or text == nil then return end
    local path = get_path(inst)
    local class = inst.ClassName
    local ts = os.time()
    local existing = index_by_path[path]
    if existing then
        local e = log_entries[existing]
        if e.text ~= text then
            e.text = text
            e.ts = ts
        end
    else
        local entry = { path = path, text = text, class = class, ts = ts }
        table.insert(log_entries, entry)
        index_by_path[path] = #log_entries
    end
end

-- quét lần đầu: tìm descendants có thuộc tính text
local function scan_root(root)
    if not root then return end
    for _, inst in ipairs(root:GetDescendants()) do
        local ok, has = pcall(function() return inst:GetAttribute and inst:GetAttribute("__dummy_check") end) -- noop, just safe
        local text = safe_get_text(inst)
        if text then
            record_entry(inst, text)
        end
    end
end

-- lắng nghe cho thay đổi text trên một instance
local function watch_instance(inst)
    if not inst then return end
    -- nếu instance có thuộc tính text bây giờ thì connect changed
    local text = safe_get_text(inst)
    if text then
        record_entry(inst, text)
    end

    -- connect sự kiện changed cho thuộc tính text
    local con
    con = inst.Changed:Connect(function(prop)
        if prop == "Text" then
            local new = safe_get_text(inst)
            if new then
                record_entry(inst, new)
                -- lưu file mỗi khi có thay đổi (bạn có thể throttle nếu muốn)
                save_to_file(log_entries)
            end
        end
    end)
    -- trả về connection để có thể disconnect nếu cần
    return con
end

-- theo dõi khi có descendants mới được thêm vào root (ví dụ gui mới)
local watched_conns = {}

local function watch_root(root)
    if not root then return end
    -- watch hiện có
    for _, inst in ipairs(root:GetDescendants()) do
        -- connect changed nếu nó có text
        if safe_get_text(inst) then
            local c = watch_instance(inst)
            if c then table.insert(watched_conns, c) end
        end
    end

    -- lắng nghe object mới thêm
    local added_conn = root.DescendantAdded:Connect(function(desc)
        -- delay nhỏ để thuộc tính text có thể set
        task.defer(function()
            local text = safe_get_text(desc)
            if text then
                record_entry(desc, text)
                local c = watch_instance(desc)
                if c then table.insert(watched_conns, c) end
                save_to_file(log_entries)
            end
        end)
    end)
    table.insert(watched_conns, added_conn)
end

-- scan tất cả root ban đầu và watch
for _, r in ipairs(roots) do
    if r then
        scan_root(r)
        watch_root(r)
    end
end

-- thêm thêm player guis khi player gui thay đổi (đổi localplayer)
players.PlayerAdded:Connect(function(plr)
    if plr == players.LocalPlayer then
        task.wait(0.5)
        local pg = plr:FindFirstChild("PlayerGui")
        if pg then
            scan_root(pg)
            watch_root(pg)
            save_to_file(log_entries)
        end
    end
end)

-- cũng watch localplayer.playergui exist now
if players.LocalPlayer and players.LocalPlayer:FindFirstChild("PlayerGui") then
    scan_root(players.LocalPlayer.PlayerGui)
    watch_root(players.LocalPlayer.PlayerGui)
end

-- quét thêm theo khoảng (in case một số gui không ở trong roots)
task.spawn(function()
    while true do
        -- scan toàn game mỗi 30 giây để chắc chắn không bỏ sót (thay đổi khoảng nếu muốn)
        for _, service in ipairs({game:GetService("Workspace"), game:GetService("CoreGui"), game:GetService("StarterGui"), game:GetService("Lighting")}) do
            scan_root(service)
        end
        save_to_file(log_entries)
        task.wait(30)
    end
end)

-- lưu lần đầu
save_to_file(log_entries)

print("gui text logger: running. output ->", file_name)