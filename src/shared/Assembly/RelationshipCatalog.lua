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
		model = "BoreSupportV1",
		name = "Sliding bearing",
		motion = "Rotate + slide",
		fixtures = 0,
		help = "Put a round shaft through a hole. It can spin and slide, including sliding all the way out.",
	},
	{
		model = "RetainedBoreV1",
		name = "Retained bearing",
		motion = "Spin, with a little room between the stops",
		fixtures = 2,
		help = "Put a shaft through a fixed housing. Add a fixed plate at each end to keep it from sliding out.",
	},
	{
		model = "LinearGuideV1",
		name = "Linear guide",
		motion = "Slide only",
		fixtures = 4,
		help = "Surround a rectangular moving block with four fixed rails. It slides along the rails without turning.",
	},
	{
		model = "LimitedGuideV1",
		name = "Linear guide + stops",
		motion = "Slide between two stops",
		fixtures = 6,
		help = "Choose the moving block. Add four fixed side rails, then a fixed plate at each end to stop its travel.",
	},
}
