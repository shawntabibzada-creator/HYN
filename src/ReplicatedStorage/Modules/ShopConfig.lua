-- Central registry of monetized items. The `id` fields are placeholders
-- (0). Before this goes live, create the matching Game Passes and
-- Developer Products for this experience in the Creator Dashboard
-- (Monetization tab) and paste their real ids in here. Anything left at 0
-- is skipped by MonetizationService and shown as "not configured" in the
-- shop UI instead of prompting a purchase.
--
-- `priceRobux` is a SUGGESTED price shown in the shop UI for reference -
-- it is not read by Roblox and does not set the actual charge. The real
-- price is whatever you set on the Game Pass / Developer Product itself
-- in the Creator Dashboard; keep this number in sync with that so the UI
-- doesn't show a stale figure.
local ShopConfig = {}

-- Game passes: one-time purchase per player, owned forever.
ShopConfig.GamePasses = {
	{
		key = "FastFlashbang",
		id = 0, -- TODO: your Game Pass id
		name = "Quick Fuse",
		description = "Flashbang cooldown drops from 6s to 4s, permanently.",
		kind = "Convenience perk",
		priceRobux = 149,
	},
	{
		key = "GoldSign",
		id = 0, -- TODO: your Game Pass id
		name = "Gold Code Sign",
		description = "Your code sign glows gold instead of yellow. Cosmetic only.",
		kind = "Cosmetic",
		priceRobux = 79,
	},
	{
		key = "CrimsonSign",
		id = 0, -- TODO: your Game Pass id
		name = "Crimson Code Sign",
		description = "Your code sign glows red instead of yellow. Cosmetic only.",
		kind = "Cosmetic",
		priceRobux = 79,
	},
}

-- Developer products: consumable, can be bought repeatedly. Must be
-- fulfilled through MarketplaceService.ProcessReceipt (see
-- MonetizationService) or Roblox will keep re-offering the purchase.
ShopConfig.DeveloperProducts = {
	{
		key = "ExtraFlashbang",
		id = 0, -- TODO: your Developer Product id
		name = "Extra Flashbang Charge",
		description = "Instantly refills your flashbang for the current round.",
		kind = "Round boost",
		priceRobux = 25,
	},
	{
		key = "PickMapTown",
		id = 0, -- TODO: your Developer Product id
		name = "Play Town Next",
		description = "The next round is guaranteed to be the Town map.",
		kind = "Pick next map",
		mapKey = "Town",
		priceRobux = 49,
	},
	{
		key = "PickMapCompound",
		id = 0, -- TODO: your Developer Product id
		name = "Play Compound Next",
		description = "The next round is guaranteed to be the Compound map.",
		kind = "Pick next map",
		mapKey = "Compound",
		priceRobux = 49,
	},
	{
		key = "PickMapDesert",
		id = 0, -- TODO: your Developer Product id
		name = "Play Desert Next",
		description = "The next round is guaranteed to be the Desert map.",
		kind = "Pick next map",
		mapKey = "Desert",
		priceRobux = 49,
	},
}

return ShopConfig
