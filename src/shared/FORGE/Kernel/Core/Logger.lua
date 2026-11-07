-- Author -> lolokdev.
-- Last Edit -> September 14, 2026 7:26 PM CDT

local Config = require(script.Parent.Config)

local Logger = {} do
	Logger.__index = Logger
	Logger.ClassName = 'Logger'

	-- prefix -> string
	-- Creates a consistent framework log prefix.
	-- @param Scope, string? -> Log scope or component name.
	local function prefix(Scope)
		return string.format('[FORGE:%s]', tostring(Scope or 'Runtime'));
	end

	-- Debug -> nil
	-- Prints development-only framework diagnostics when runtime debugging is enabled.
	-- @param Scope, string -> Log scope.
	-- @param Message, any -> Message payload.
	function Logger.Debug(Scope, Message)
		if not Config.Runtime or not Config.Runtime.Debug then return end
		print(prefix(Scope), Message)
	end

	-- Info -> nil
	-- Prints an informational framework message.
	-- @param Scope, string -> Log scope.
	-- @param Message, any -> Message payload.
	function Logger.Info(Scope, Message)
		print(prefix(Scope), Message)
	end

	-- Log -> nil
	-- Preserves compatibility with older FORGE builds that used Logger.Log instead of Logger.Info.
	-- @param Scope, string -> Log scope.
	-- @param Message, any -> Message payload.
	function Logger.Log(Scope, Message)
		Logger.Info(Scope, Message)
	end

	-- Warn -> nil
	-- Prints a recoverable framework warning.
	-- @param Scope, string -> Log scope.
	-- @param Message, any -> Warning payload.
	function Logger.Warn(Scope, Message)
		warn(prefix(Scope), Message)
	end

	-- Error -> nil
	-- Raises a framework error with a consistent scope prefix.
	-- @param Scope, string -> Log scope.
	-- @param Message, any -> Error payload.
	function Logger.Error(Scope, Message)
		error(prefix(Scope) .. ' ' .. tostring(Message), 2)
	end
end

return Logger;
