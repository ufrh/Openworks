--!strict
return function(Manager)
	local manager = Manager.new()
	local enters, exits, cleanups = 0, 0, 0
	local old = {
		Enter = function()
			enters += 1
		end,
		Exit = function()
			exits += 1
		end,
	}
	manager:register("Assembly", old)
	manager:register("Failure", {
		Enter = function()
			error("invalid mechanism")
		end,
		Exit = function() end,
		CleanupFailedEnter = function()
			cleanups += 1
		end,
	})
	assert(manager:switch("Assembly"))
	assert(
		manager:switch("Assembly") and enters == 1 and exits == 0,
		"Same-mode request restarted the mode"
	)
	assert(not manager:switch("Failure"), "Failed entry reported success")
	assert(
		cleanups == 1 and enters == 2 and manager.currentName == "Assembly" and not manager.busy,
		"Entry failure did not clean up and restore"
	)
	old.Exit = function()
		error("validation in progress")
	end
	assert(
		not manager:switch("Failure") and manager.current == old and not manager.busy,
		"Exit rejection corrupted active mode"
	)
	old.Exit = function()
		exits += 1
	end
	local recovered, oldCleaned = 0, 0
	manager:register("Free", {
		Enter = function()
			recovered += 1
		end,
		Exit = function() end,
	})
	old.Enter = function()
		error("old workspace removed")
	end
	old.CleanupFailedEnter = function()
		oldCleaned += 1
	end
	assert(not manager:switch("Failure"), "Double failure reported success")
	assert(
		manager.currentName == "Free" and recovered == 1 and oldCleaned == 1 and not manager.busy,
		"Failed rollback did not clean up and recover to Free"
	)
	manager:destroy()
	assert(manager.current == nil and manager.currentName == nil, "Destroy retained mode state")
	return 8
end
