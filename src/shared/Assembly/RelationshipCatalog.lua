--!strict
return {
	{
		model = "RetainedPivotV1",
		name = "Pin pivot",
		motion = "Revolute · 1 DOF",
		fixtures = 3,
		help = "Two through-bores, one clearance pin, and two end caps. The pin is retained; the links rotate relative to one another.",
	},
	{
		model = "DualPinRigidV1",
		name = "Dual-pin rigid coupling",
		motion = "Rigid · 0 DOF",
		fixtures = 6,
		help = "Two manufactured through-pins at separate bore centers, each retained by two end caps. Both links become rigidly connected.",
	},
	{
		model = "BoreSupportV1",
		name = "Sliding bearing",
		motion = "Rotate + slide",
		fixtures = 0,
		help = "Unretained clearance shaft in a through-bore. Permits axial translation and rotation.",
	},
	{
		model = "RetainedBoreV1",
		name = "Retained bearing",
		motion = "Spin, with a little room between the stops",
		fixtures = 2,
		help = "Shaft in a grounded through-bore with manufactured axial stop plates.",
	},
	{
		model = "LinearGuideV1",
		name = "Linear guide",
		motion = "Slide only",
		fixtures = 4,
		help = "Four grounded rectangular rails constrain carriage rotation; permits one translational DOF.",
	},
	{
		model = "LimitedGuideV1",
		name = "Linear guide + stops",
		motion = "Slide between two stops",
		fixtures = 6,
		help = "Prismatic guide with four rails and two grounded, physically positioned end stops.",
	},
}
