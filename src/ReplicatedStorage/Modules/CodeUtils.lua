-- Shared helpers for generating and validating the 4-digit player codes.
local CodeUtils = {}

function CodeUtils.GenerateCode(rng)
	rng = rng or Random.new()
	local n = rng:NextInteger(0, 9999)
	return string.format("%04d", n)
end

function CodeUtils.IsValidCode(code)
	return type(code) == "string" and code:match("^%d%d%d%d$") ~= nil
end

return CodeUtils
