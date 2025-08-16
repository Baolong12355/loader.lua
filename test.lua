-- Load Rayfield Library
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Services
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- Variables
local LocalPlayer = Players.LocalPlayer
local PLACE_ID = 119078961994407

-- Create Window
local Window = Rayfield:CreateWindow({
   Name = "Script GUI",
   Icon = 0,
   LoadingTitle = "Đang tải GUI...",
   LoadingSubtitle = "Vui lòng đợi",
   ShowText = "Script GUI",
   Theme = "Default",
   
   ToggleUIKeybind = "K",
   
   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false,
   
   ConfigurationSaving = {
      Enabled = false
   },
   
   KeySystem = false
})

-- Create Main Tab
local MainTab = Window:CreateTab("Chức năng chính", "star")

-- Create Section
local TeleportSection = MainTab:CreateSection("Teleport")

-- Chức năng 1: Teleport Button
local TeleportButton = MainTab:CreateButton({
   Name = "Teleport đến Place ID",
   Callback = function()
      Rayfield:Notify({
         Title = "Đang teleport...",
         Content = "Đang chuyển đến Place ID: " .. PLACE_ID,
         Duration = 3,
         Image = "airplane"
      })
      
      -- Teleport to the specified place
      local success, errorMessage = pcall(function()
         TeleportService:Teleport(PLACE_ID, LocalPlayer)
      end)
      
      if not success then
         Rayfield:Notify({
            Title = "Lỗi Teleport",
            Content = "Không thể teleport: " .. tostring(errorMessage),
            Duration = 5,
            Image = "alert-circle"
         })
      end
   end,
})

-- Create GUI Management Section
local GuiSection = MainTab:CreateSection("Quản lý GUI")

-- Chức năng 2: Delete QuickTimeEvent GUI khi nhấn Delete
local DeleteGuiToggle = MainTab:CreateToggle({
   Name = "Xóa QuickTimeEvent GUI (Delete)",
   CurrentValue = false,
   Flag = "DeleteGui",
   Callback = function(Value)
      if Value then
         Rayfield:Notify({
            Title = "Chức năng kích hoạt",
            Content = "Nhấn phím Delete để xóa QuickTimeEvent GUI",
            Duration = 4,
            Image = "trash-2"
         })
      else
         Rayfield:Notify({
            Title = "Chức năng tắt",
            Content = "Đã tắt chức năng xóa GUI",
            Duration = 3,
            Image = "x"
         })
      end
   end,
})

-- Handle Delete key press
UserInputService.InputBegan:Connect(function(input, gameProcessed)
   if gameProcessed then return end
   
   if input.KeyCode == Enum.KeyCode.Delete and Rayfield.Flags.DeleteGui then
      local success, errorMessage = pcall(function()
         local playerGui = LocalPlayer.PlayerGui
         local quickTimeEvent = playerGui:FindFirstChild("QuickTimeEvent")
         
         if quickTimeEvent then
            quickTimeEvent:Destroy()
            Rayfield:Notify({
               Title = "Thành công",
               Content = "Đã xóa QuickTimeEvent GUI",
               Duration = 3,
               Image = "check"
            })
         else
            Rayfield:Notify({
               Title = "Không tìm thấy",
               Content = "Không tìm thấy QuickTimeEvent GUI",
               Duration = 3,
               Image = "search"
            })
         end
      end)
      
      if not success then
         Rayfield:Notify({
            Title = "Lỗi",
            Content = "Không thể xóa GUI: " .. tostring(errorMessage),
            Duration = 4,
            Image = "alert-triangle"
         })
      end
   end
end)

-- Info Section
local InfoSection = MainTab:CreateSection("Thông tin")

local InfoLabel = MainTab:CreateLabel("🔹 Nhấn nút để teleport đến Place ID", "info")
local InfoLabel2 = MainTab:CreateLabel("🔹 Bật toggle và nhấn Delete để xóa GUI", "info")

-- Initial notification
Rayfield:Notify({
   Title = "GUI đã sẵn sàng!",
   Content = "Tất cả chức năng đã được tải thành công",
   Duration = 4,
   Image = "check-circle"
})