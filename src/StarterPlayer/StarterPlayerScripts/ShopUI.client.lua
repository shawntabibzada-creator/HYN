-- Shop panel: lists the game passes and developer products from
-- ShopConfig and prompts a real Roblox purchase when clicked. Items whose
-- id is still the 0 placeholder show as "not set up yet" instead of
-- prompting, since Roblox would reject a purchase for id 0.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local ShopConfig = require(ReplicatedStorage.Modules.ShopConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local screenGui = playerGui:WaitForChild("CodeDuelUI")

local shopButton = Instance.new("TextButton")
shopButton.Size = UDim2.new(0, 90, 0, 36)
shopButton.Position = UDim2.new(0, 10, 1, -100)
shopButton.Text = "SHOP"
shopButton.Font = Enum.Font.GothamBold
shopButton.TextScaled = true
shopButton.BackgroundColor3 = Color3.fromRGB(70, 160, 90)
shopButton.TextColor3 = Color3.new(1, 1, 1)
shopButton.ZIndex = 5
shopButton.Parent = screenGui

local shopFrame = Instance.new("Frame")
shopFrame.Size = UDim2.new(0, 360, 0, 420)
shopFrame.Position = UDim2.new(0.5, -180, 0.5, -210)
shopFrame.BackgroundColor3 = Color3.fromRGB(24, 24, 27)
shopFrame.BackgroundTransparency = 0.05
shopFrame.Visible = false
shopFrame.ZIndex = 6
shopFrame.Parent = screenGui

local titleBar = Instance.new("TextLabel")
titleBar.Size = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
titleBar.Text = "CODE DUEL SHOP"
titleBar.Font = Enum.Font.GothamBold
titleBar.TextScaled = true
titleBar.TextColor3 = Color3.new(1, 1, 1)
titleBar.ZIndex = 6
titleBar.Parent = shopFrame

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 32, 0, 32)
closeButton.Position = UDim2.new(1, -36, 0, 4)
closeButton.Text = "X"
closeButton.Font = Enum.Font.GothamBold
closeButton.TextScaled = true
closeButton.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.ZIndex = 7
closeButton.Parent = shopFrame

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -12, 1, -50)
scrollFrame.Position = UDim2.new(0, 6, 0, 46)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel = 0
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.ScrollBarThickness = 6
scrollFrame.ZIndex = 6
scrollFrame.Parent = shopFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scrollFrame

shopButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = not shopFrame.Visible
end)
closeButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = false
end)

local function addEntry(kind, name, description, priceRobux, onBuy, configured)
	local entry = Instance.new("Frame")
	entry.Size = UDim2.new(1, -6, 0, 84)
	entry.BackgroundColor3 = Color3.fromRGB(34, 34, 38)
	entry.ZIndex = 6
	entry.Parent = scrollFrame

	local kindLabel = Instance.new("TextLabel")
	kindLabel.Size = UDim2.new(0.6, 0, 0, 18)
	kindLabel.Position = UDim2.new(0, 8, 0, 4)
	kindLabel.BackgroundTransparency = 1
	kindLabel.Text = kind
	kindLabel.Font = Enum.Font.Gotham
	kindLabel.TextScaled = true
	kindLabel.TextXAlignment = Enum.TextXAlignment.Left
	kindLabel.TextColor3 = Color3.fromRGB(150, 200, 255)
	kindLabel.ZIndex = 6
	kindLabel.Parent = entry

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(0.6, 0, 0, 22)
	nameLabel.Position = UDim2.new(0, 8, 0, 20)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = name
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.ZIndex = 6
	nameLabel.Parent = entry

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(0.6, 0, 0, 36)
	descLabel.Position = UDim2.new(0, 8, 0, 44)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = description
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextScaled = true
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	descLabel.ZIndex = 6
	descLabel.Parent = entry

	local buyButton = Instance.new("TextButton")
	buyButton.Size = UDim2.new(0, 110, 0, 60)
	buyButton.Position = UDim2.new(1, -118, 0, 12)
	buyButton.Font = Enum.Font.GothamBold
	buyButton.TextScaled = true
	buyButton.ZIndex = 6
	buyButton.Parent = entry

	if configured then
		buyButton.Text = string.format("BUY\n%d R$", priceRobux)
		buyButton.BackgroundColor3 = Color3.fromRGB(80, 170, 90)
		buyButton.TextColor3 = Color3.new(1, 1, 1)
		buyButton.MouseButton1Click:Connect(onBuy)
	else
		buyButton.Text = string.format("NOT SET UP\n(%d R$)", priceRobux)
		buyButton.BackgroundColor3 = Color3.fromRGB(70, 70, 74)
		buyButton.TextColor3 = Color3.fromRGB(180, 180, 180)
		buyButton.AutoButtonColor = false
	end
end

for _, pass in ipairs(ShopConfig.GamePasses) do
	addEntry(pass.kind, pass.name, pass.description, pass.priceRobux, function()
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	end, pass.id ~= 0)
end

for _, product in ipairs(ShopConfig.DeveloperProducts) do
	addEntry(product.kind, product.name, product.description, product.priceRobux, function()
		MarketplaceService:PromptProductPurchase(player, product.id)
	end, product.id ~= 0)
end
