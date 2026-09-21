-- Central registry of monetized items. The `id` fields are placeholders
-- (0). Before this goes live, create the matching Game Passes and
-- Developer Products for this experience in the Creator Dashboard
-- (Monetization tab) and paste their real ids in here. Anything left at 0
-- is skipped by MonetizationService and shown as "not configured" in the
-- shop UI instead of prompting a purchase.
local ShopConfig = {}

-- Game passes: one-time purchase per player, owned forever.
ShopConfig.GamePasses = {
	{
		key = "FastFlashbang",
		id = 0, -- TODO: your Game Pass id
		name = "Quick Fuse",
		description = "Flashbang cooldown drops from 6s to 4s, permanently.",
		kind = "Convenience perk",
	},
	{
		key = "GoldSign",
		id = 0, -- TODO: your Game Pass id
		name = "Gold Code Sign",
		description = "Your code sign glows gold instead of yellow. Cosmetic only.",
		kind = "Cosmetic",
	},
	{
		key = "CrimsonSign",
		id = 0, -- TODO: your Game Pass id
		name = "Crimson Code Sign",
		description = "Your code sign glows red instead of yellow. Cosmetic only.",
		kind = "Cosmetic",
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
	},
	{
		key = "PickMapTown",
		id = 0, -- TODO: your Developer Product id
		name = "Play Town Next",
		description = "The next round is guaranteed to be the Town map.",
		kind = "Pick next map",
		mapKey = "Town",
	},
	{
		key = "PickMapCompound",
		id = 0, -- TODO: your Developer Product id
		name = "Play Compound Next",
		description = "The next round is guaranteed to be the Compound map.",
		kind = "Pick next map",
		mapKey = "Compound",
	},
	{
		key = "PickMapDesert",
		id = 0, -- TODO: your Developer Product id
		name = "Play Desert Next",
		description = "The next round is guaranteed to be the Desert map.",
		kind = "Pick next map",
		mapKey = "Desert",
	},
}

return ShopConfig
