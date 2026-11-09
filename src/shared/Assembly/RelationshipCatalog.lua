--!strict
return {
	{
		model = "BoreSupportV1",
		name = "Sliding bearing",
		motion = "Rotate + slide",
		fixtures = 0,
		help = "A: cylindrical shaft. B: through-hole. Align and insert first. The shaft can rotate and slide out.",
	},
	{
		model = "RetainedBoreV1",
		name = "Retained bearing",
		motion = "Rotate + bounded endplay",
		fixtures = 2,
		help = "A: shaft. B: bore fixed to bench. Add two fixed rectangular end-stop plates covering the shaft ends.",
	},
	{
		model = "LinearGuideV1",
		name = "Linear guide",
		motion = "Slide only",
		fixtures = 4,
		help = "A: uncut rectangular carriage. Add four fixed rectangular rails around its local X/Z sides. Travel follows local Y.",
	},
	{
		model = "LimitedGuideV1",
		name = "Linear guide + stops",
		motion = "Bounded slide",
		fixtures = 6,
		help = "A: rectangular carriage. Add four side rails first, then two end-stop plates. All six fixtures must be fixed to bench.",
	},
}
