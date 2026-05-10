-- See https://wiki.hypr.land/Configuring/Basics/Monitors/

hl.monitor({
	output = "DP-1",
	mode = "3840x2160@240.00",
	position = "0x0",
	scale = "1",
	vrr = 1,
	cm = "srgb",
	bitdepth = 8,
	sdrbrightness = 1.20,
})

hl.monitor({
	output = "DP-2",
	disabled = true,
})
