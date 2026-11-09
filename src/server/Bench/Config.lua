--!strict
-- OPENWORKS constraint scale laboratory. All dimensions are reference dimensions in studs.
-- Bench configuration is intentionally independent of the live construction game.
return {
	ReferenceScale = 0.75,
	Scales = { 0.375, 0.50, 0.75, 1.00, 1.50 },
	Trials = 3,
	SecondsPerPhase = 7,
	SampleInterval = 0.10,
	Phases = { "idle", "normal", "heavy", "extreme" },
	-- 1* reference parts track candidate scales; thinner rods are sub-unit geometry.
	Tests = {
		{ "01", "Hinged pendulum" },
		{ "02", "Motorized flywheel" },
		{ "03", "Linear carriage" },
		{ "04", "Telescoping spindle" },
		{ "05", "Ball socket arm" },
		{ "06", "Spring and damper" },
		{ "07", "Torsion return lever" },
		{ "08", "Rope winch hoist" },
		{ "09", "Dual rod linkage" },
		{ "10", "Rigid cantilever" },
		{ "11", "Universal joint drive" },
		{ "12", "Planar platform" },
		{ "13", "Four-bar linkage" },
		{ "14", "Slider crank" },
		{ "15", "Suspension module" },
		{ "16", "Double bearing shaft" },
		{ "17", "Connected crank network" },
	},
}
