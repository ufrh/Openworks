-- Author -> lolokdev.
-- Last Edit -> September 13, 2026 8:44 AM CDT

local HttpService = game:GetService('HttpService')

local Config = require(game.ReplicatedStorage.FORGE.Kernel.Core.Config)
local SecurityCodec = require(game.ReplicatedStorage.FORGE.Kernel.Networking.SecurityCodec)

local SessionManager = {} do
	SessionManager.__index = SessionManager
	SessionManager.ClassName = 'SessionManager'

	-- new -> SessionManager
	-- Creates one server-instance session authority with a server-only secret.
	function SessionManager.new()
		local this = setmetatable({}, SessionManager)
		this.SessionId = HttpService:GenerateGUID(false)
		this._Secret = HttpService:GenerateGUID(false) .. HttpService:GenerateGUID(false)
		this._Sessions = setmetatable({}, {__mode = 'k'})
		return this;
	end

	-- RemoteName -> string
	-- Generates a per-server opaque remote name from the server-only secret.
	-- @param Label, string -> Transport label.
	function SessionManager:RemoteName(Label)
		return '_' .. string.sub(SecurityCodec.Hash(self._Secret .. '|' .. self.SessionId .. '|remote|' .. Label), 1, 20);
	end

	-- RouteId -> string
	-- Generates a stable per-server opaque route id for one Service endpoint or signal.
	-- @param RouteName, string -> Plain internal route name.
	function SessionManager:RouteId(RouteName)
		return string.sub(SecurityCodec.Hash(self._Secret .. '|' .. self.SessionId .. '|route|' .. RouteName), 1, 24);
	end

	-- Get -> table?
	-- Returns the current player session.
	-- @param Player, Player -> Session owner.
	function SessionManager:Get(Player)
		return self._Sessions[Player];
	end

	-- Handshake -> table
	-- Creates or refreshes the opaque per-player authentication token.
	-- @param Player, Player -> Player requesting a session.
	function SessionManager:Handshake(Player)
		local Session = self._Sessions[Player]

		if not Session then
			local Random = HttpService:GenerateGUID(false)
			local TokenSource = self._Secret .. '|' .. self.SessionId .. '|' .. tostring(Player.UserId) .. '|' .. Random
			Session = {Token = SecurityCodec.Hash(TokenSource) .. SecurityCodec.Hash(TokenSource .. '|2'); HighestClientNonce = 0; SeenClientNonces = {}; ServerNonce = 0; Created = os.clock();}
			self._Sessions[Player] = Session
		end

		return Session;
	end

	-- ValidateNonce -> boolean
	-- Rejects replayed or out-of-order client packets and advances the accepted nonce.
	-- @param Player, Player -> Session owner.
	-- @param Nonce, number -> Candidate client nonce.
	function SessionManager:ValidateNonce(Player, Nonce)
		local Session = self._Sessions[Player]
		if not Session or type(Nonce) ~= 'number' or Nonce % 1 ~= 0 or Nonce <= 0 then return false end

		local Window = Config.Network.NonceWindow or 64
		local Minimum = math.max(Session.HighestClientNonce - Window + 1, 1)
		if Nonce < Minimum or Session.SeenClientNonces[Nonce] then return false end

		Session.SeenClientNonces[Nonce] = true
		if Nonce > Session.HighestClientNonce then Session.HighestClientNonce = Nonce end

		local NewMinimum = math.max(Session.HighestClientNonce - Window + 1, 1)
		for SeenNonce in pairs(Session.SeenClientNonces) do if SeenNonce < NewMinimum then Session.SeenClientNonces[SeenNonce] = nil end end
		return true;
	end

	-- NextServerNonce -> number
	-- Allocates the next monotonic server-to-client packet nonce.
	-- @param Player, Player -> Session owner.
	function SessionManager:NextServerNonce(Player)
		local Session = self._Sessions[Player]
		if not Session then Session = self:Handshake(Player) end
		Session.ServerNonce += 1
		return Session.ServerNonce;
	end

	-- Remove -> nil
	-- Removes one departing player's session.
	-- @param Player, Player -> Session owner.
	function SessionManager:Remove(Player)
		self._Sessions[Player] = nil
	end

	-- Destroy -> nil
	-- Clears every active session and rotates the manager so a later bridge restart cannot reuse invalidated security state.
	function SessionManager:Destroy()
		table.clear(self._Sessions)
		self.SessionId = HttpService:GenerateGUID(false)
		self._Secret = HttpService:GenerateGUID(false) .. HttpService:GenerateGUID(false)
	end
end

return SessionManager;
