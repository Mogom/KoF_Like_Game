local Commands = {

	{
		Name = "Fireball",
		Input = {"Down","Right","Punch"},
		Priority = 10
	},

	{
		Name = "Punch",
		Input = {"Punch"},
		Priority = 1
	},
	
	{
		Name = "HeavyPunch",
		Input = {"HeavyPunch"},
		Priority = 1
	},
	
	{
		Name = "Dash",
		Input = {"Right","Right"},
		Priority = 5
	},

	{
		Name = "Uppercut",
		Input = {"Right","Down","Right","Punch"},
		Priority = 15
	}

}

return Commands