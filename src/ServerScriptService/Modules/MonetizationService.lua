-- Wraps Game Pass ownership checks and Developer Product fulfillment
-- (MarketplaceService.ProcessReceipt) behind a small API the rest of the
-- server uses, so GameServer doesn't need to know about receipts directly.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Modules.ShopConfig)

local MonetizationService = {}

local ownershipCache = {} -- [Player] = { [passKey] = true }

local extraFlashbangSignal = Instance.new("BindableEvent")
MonetizationService.ExtraFlashbangGranted = extraFlashbangSignal.Event

local function findPassById(id)
	for _, pass in ipairs(ShopConfig.GamePasses) do
		if pass.id == id then
			return pass
		end
	end
	return nil
end

local function findProductById(id)
	for _, product in ipairs(ShopConfig.DeveloperProducts) do
		if product.id == id then
			return product
		end
	end
	return nil
end

local function refreshOwnership(player)
	local owned = {}
	for _, pass in ipairs(ShopConfig.GamePasses) do
		if pass.id ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			owned[pass.key] = ok and owns or false
		end
	end
	ownershipCache[player] = owned
end

function MonetizationService.Init(player)
	task.spawn(refreshOwnership, player)
end

function MonetizationService.Cleanup(player)
	ownershipCache[player] = nil
end

function MonetizationService.Owns(player, passKey)
	local owned = ownershipCache[player]
	return owned ~= nil and owned[passKey] == true
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if wasPurchased then
		local pass = findPassById(gamePassId)
		if pass then
			ownershipCache[player] = ownershipCache[player] or {}
			ownershipCache[player][pass.key] = true
		end
	end
end)

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local product = findProductById(receiptInfo.ProductId)
	if product and product.key == "ExtraFlashbang" then
		extraFlashbangSignal:Fire(player)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

return MonetizationService
