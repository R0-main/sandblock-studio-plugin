--!strict

-- Sandblock's semantic Studio theme. Components consume these tokens instead
-- of hard-coding colors so the dock widget and future ScreenGui surfaces stay
-- visually consistent.

local Theme = {}

local function font(weight: Enum.FontWeight): Font
	return Font.new(
		"rbxasset://fonts/families/BuilderSans.json",
		weight,
		Enum.FontStyle.Normal
	)
end

function Theme.get()
	return {
		Color = {
			Canvas = Color3.fromHex("11110F"),
			Surface = Color3.fromHex("191816"),
			SurfaceElevated = Color3.fromHex("22211D"),
			SurfaceMuted = Color3.fromHex("2B2924"),
			SurfaceHover = Color3.fromHex("343129"),

			TextPrimary = Color3.fromHex("F5F1E8"),
			TextSecondary = Color3.fromHex("B8B2A7"),
			TextMuted = Color3.fromHex("817C72"),

			Border = Color3.fromHex("3B3831"),
			BorderStrong = Color3.fromHex("5A5447"),
			Focus = Color3.fromHex("F6C944"),

			Accent = Color3.fromHex("F6C944"),
			AccentHover = Color3.fromHex("FFD866"),
			AccentPressed = Color3.fromHex("D9AE32"),
			OnAccent = Color3.fromHex("17140A"),

			Success = Color3.fromHex("68D391"),
			SuccessSurface = Color3.fromHex("183326"),
			Warning = Color3.fromHex("F6C944"),
			WarningSurface = Color3.fromHex("3B3115"),
			Error = Color3.fromHex("FF7770"),
			ErrorSurface = Color3.fromHex("3A201F"),
			Info = Color3.fromHex("78B7FF"),
			InfoSurface = Color3.fromHex("192C42"),
		},

		Font = {
			Regular = font(Enum.FontWeight.Regular),
			Medium = font(Enum.FontWeight.Medium),
			Semibold = font(Enum.FontWeight.SemiBold),
			Bold = font(Enum.FontWeight.Bold),
			Code = Font.new(
				"rbxasset://fonts/families/RobotoMono.json",
				Enum.FontWeight.Regular,
				Enum.FontStyle.Normal
			),
		},

		TextSize = {
			Caption = 11,
			Small = 12,
			Body = 14,
			Medium = 16,
			Title = 20,
			Display = 26,
			Code = 13,
		},

		Spacing = {
			XSmall = 4,
			Small = 8,
			Medium = 12,
			Large = 16,
			XLarge = 24,
		},

		Radius = {
			Small = 5,
			Medium = 8,
			Large = 12,
			Pill = 999,
		},

		Control = {
			Compact = 28,
			Regular = 34,
			Large = 40,
		},
	}
end

return Theme
