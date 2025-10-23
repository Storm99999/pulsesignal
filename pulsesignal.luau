--[[
	                                                                                                              
                          88                                    88                                        88  
                          88                                    ""                                        88  
                          88                                                                              88  
8b,dPPYba,   88       88  88  ,adPPYba,   ,adPPYba,  ,adPPYba,  88   ,adPPYb,d8  8b,dPPYba,   ,adPPYYba,  88  
88P'    "8a  88       88  88  I8[    ""  a8P_____88  I8[    ""  88  a8"    `Y88  88P'   `"8a  ""     `Y8  88  
88       d8  88       88  88   `"Y8ba,   8PP"""""""   `"Y8ba,   88  8b       88  88       88  ,adPPPPP88  88  
88b,   ,a8"  "8a,   ,a88  88  aa    ]8I  "8b,   ,aa  aa    ]8I  88  "8a,   ,d88  88       88  88,    ,88  88  
88`YbbdP"'    `"YbbdP'Y8  88  `"YbbdP"'   `"Ybbd8"'  `"YbbdP"'  88   `"YbbdP"Y8  88       88  `"8bbdP"Y8  88  
88                                                                   aa,    ,88                               
88                                                                    "Y8bbdP"                                

Benchmark results (w/o optimize 2 in pulsesignal, SignalPlus stayed unchanged):
  01:02:09.647  pulsesignal: listeners=100 fires=100 elapsed=0.0010 s completed=10000 memDelta=248.0KB
  01:02:09.752  SignalPlus: listeners=100 fires=100 elapsed=0.0407 s completed=10000 memDelta=11612.0KB 
  01:02:10.031  pulsesignal: listeners=1000 fires=100 elapsed=0.0097 s completed=100000 memDelta=2027.0KB 
  01:02:10.510  SignalPlus: listeners=1000 fires=100 elapsed=0.4119 s completed=100000 memDelta=104534.0KB 
  01:02:10.878  pulsesignal: listeners=1000 fires=1000 elapsed=0.0986 s completed=1000000 memDelta=16470.0KB
  01:02:15.218  SignalPlus: listeners=1000 fires=1000 elapsed=4.2719 s completed=1000000 memDelta=1038761.0KB
]]

--!strict
-- Methods:
--    :Connect(callback) -> Connection (with :Disconnect())
--    :Once(callback) -> Connection (auto-disconnects after first fire)
--    :Wait() -> waits until next Fire and returns all args
--    :Fire(...)
--    :Destroy()
--    :GetConnectionCount()
--    :IsDestroyed()

local Signal = {}
Signal.__index = Signal

-- Types
export type Listener = {
	id: number,
	callback: (...any) -> (),
	once: boolean,
}

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type SignalClass = {
	Connect: (self: SignalClass, callback: (...any) -> ()) -> Connection,
	Once: (self: SignalClass, callback: (...any) -> ()) -> Connection,
	Fire: (self: SignalClass, ...any) -> (),
	Wait: (self: SignalClass) -> ...any,
	Destroy: (self: SignalClass) -> (),
	GetConnectionCount: (self: SignalClass) -> number,
	IsDestroyed: (self: SignalClass) -> boolean,
}

function Signal.new(): SignalClass
	local self = setmetatable({
		_listeners = {} :: {[number]: Listener},
		_nextId = 0,
		_destroyed = false,
	}, Signal)

	return (self :: any) :: SignalClass
end

-- Connect: subscribe to the signal; Returns a Connection with :Disconnect()
function Signal:Connect(callback: (...any) -> ()): Connection
	assert(typeof(callback) == "function", "Signal:Connect expects a function")
	assert(not self._destroyed, "pulsesignal has been destroyed")

	self._nextId = self._nextId + 1
	local id = self._nextId
	local listener: Listener = { id = id, callback = callback, once = false }
	self._listeners[id] = listener

	local signalRef = self
	local connection: Connection = {
		Connected = true,
		Disconnect = function(conn: Connection)
			if not conn.Connected then
				return
			end
			conn.Connected = false
			if signalRef and signalRef._listeners then
				signalRef._listeners[id] = nil
			end
		end,
	}

	return connection
end

-- Once: connect for a single call
function Signal:Once(callback: (...any) -> ()): Connection
	assert(typeof(callback) == "function", "Signal:Once expects a function")
	assert(not self._destroyed, "pulsesignal has been destroyed")

	self._nextId = self._nextId + 1
	local id = self._nextId
	local listener: Listener = { id = id, callback = callback, once = true }
	self._listeners[id] = listener

	local signalRef = self
	local connection: Connection = {
		Connected = true,
		Disconnect = function(conn: Connection)
			if not conn.Connected then
				return
			end
			conn.Connected = false
			if signalRef and signalRef._listeners then
				signalRef._listeners[id] = nil
			end
		end,
	}

	return connection
end

-- Fire: call all listeners with the provided arg
function Signal:Fire(...: any)
	if self._destroyed then
		return
	end

	local snapshot: { Listener } = {}
	local snapN = 0
	for _, listener in pairs(self._listeners) do
		snapN = snapN + 1
		snapshot[snapN] = listener
	end

	for i = 1, snapN do
		local listener = snapshot[i]
		if listener and self._listeners[listener.id] == listener then
			local ok, err = pcall(listener.callback, ...)
			if not ok then
				warn(("[pulsesignal] callback error: %s"):format(tostring(err)))
			end
			if listener.once then
				self._listeners[listener.id] = nil
			end
		end
	end
end

function Signal:Wait()
	assert(not self._destroyed, "pulsesignal has been destroyed")
	local thread = coroutine.running()
	assert(thread ~= nil, "Signal:Wait() must be called from a coroutine")

	local resumed = false
	local values: { any } = {}

	local conn
	conn = self:Connect(function(...: any)
		if conn then
			conn:Disconnect()
		end
		if not resumed then
			resumed = true
			values = { ... }
			coroutine.resume(thread, table.unpack(values))
		end
	end)

	return coroutine.yield()
end

function Signal:Destroy()
	if self._destroyed then
		return
	end
	self._listeners = {}
	self._destroyed = true
end

function Signal:GetConnectionCount(): number
	local count = 0
	for _ in self._listeners do
		count = count + 1
	end

	return count
end

function Signal:IsDestroyed(): boolean
	return self._destroyed == true
end

Signal.ConnectOnce = Signal.Once

return Signal
