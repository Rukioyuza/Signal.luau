--!strict

type SignalImpl<Args...> = {
	__index: SignalImpl<Args...>,
	connect: (self: Signal<Args...>, handler: (Args...) -> ()) -> Connection<Args...>,
	once: (self: Signal<Args...>, handler: (Args...) -> ()) -> Connection<Args...>,
	wait: (self: Signal<Args...>) -> Args...,
	fire: (self: Signal<Args...>, Args...) -> (),
	disconnectAll: (self: Signal<Args...>) -> (),
	destroy: (self: Signal<Args...>) -> (),
}

type SignalData<Args...> = {
	head: Connection<Args...>?,
	tail: Connection<Args...>?,
	lastOrder: number,
}

export type Signal<Args...> = setmetatable<SignalData<Args...>, SignalImpl<Args...>>

type ConnectionImpl<Args...> = {
	__index: ConnectionImpl<Args...>,
	disconnect: (self: Connection<Args...>) -> (),
}

type ConnectionData<Args...> = {
	connected: boolean,
	signal: Signal<Args...>,
	handler: (Args...) -> (),
	order: number,
	previous: Connection<Args...>?,
	next: Connection<Args...>?,
}

export type Connection<Args...> = setmetatable<ConnectionData<Args...>, ConnectionImpl<Args...>>

type Statics = {
	new: <Args...>() -> Signal<Args...>,
}

local freeRunner: thread? = nil

local function runHandler<Args...>(handler: (Args...) -> (), ...: Args...): ()
	freeRunner = nil
	handler(...)
	freeRunner = coroutine.running()
end

local function runHandlers(): ()
	while true do
		runHandler(coroutine.yield())
	end
end

local function newRunner(): thread
	local runner = coroutine.create(runHandlers)
	coroutine.resume(runner)
	return runner
end

local Connection = {} :: ConnectionImpl<...any>
Connection.__index = Connection

local Signal = {} :: SignalImpl<...any> & Statics
Signal.__index = Signal

function Signal.new<Args...>(): Signal<Args...>
	local self: SignalData<Args...> = {
		head = nil,
		tail = nil,
		lastOrder = 0,
	}
	return setmetatable(self, Signal) :: any
end

function Signal.connect<Args...>(self: Signal<Args...>, handler: (Args...) -> ()): Connection<Args...>
	assert(type(handler) == "function", "Signal:connect expects a function, nothing was connected")

	self.lastOrder += 1

	local newConnection: ConnectionData<Args...> = {
		connected = true,
		signal = self,
		handler = handler,
		order = self.lastOrder,
		previous = self.tail,
		next = nil,
	}
	local connected: Connection<Args...> = setmetatable(newConnection, Connection) :: any

	local tail = self.tail
	if tail then
		tail.next = connected
	else
		self.head = connected
	end
	self.tail = connected

	return connected
end

function Signal.once<Args...>(self: Signal<Args...>, handler: (Args...) -> ()): Connection<Args...>
	assert(type(handler) == "function", "Signal:once expects a function, nothing was connected")

	local onceConnection: Connection<Args...>
	onceConnection = self:connect(function(...: Args...): ()
		onceConnection:disconnect()
		handler(...)
	end)

	return onceConnection
end

function Signal.wait<Args...>(self: Signal<Args...>): Args...
	local thread = coroutine.running()

	self:once(function(...: Args...): ()
		task.spawn(thread, ...)
	end)

	return coroutine.yield()
end

function Signal.fire<Args...>(self: Signal<Args...>, ...: Args...): ()
	local lastOrder = self.lastOrder
	local current = self.head

	while current and current.order <= lastOrder do
		if current.connected then
			local free = freeRunner
			local runner = if free then free else newRunner()
			task.spawn(runner, current.handler, ...)
		end
		current = current.next
	end
end

function Signal.disconnectAll<Args...>(self: Signal<Args...>): ()
	local current = self.head

	while current do
		current.connected = false
		current = current.next
	end

	self.head = nil
	self.tail = nil
end

function Signal.destroy<Args...>(self: Signal<Args...>): ()
	self:disconnectAll()
end

function Connection.disconnect<Args...>(self: Connection<Args...>): ()
	if not self.connected then
		return
	end
	self.connected = false

	local owner = self.signal
	local previous = self.previous
	local next = self.next

	if previous then
		previous.next = next
	else
		owner.head = next
	end

	if next then
		next.previous = previous
	else
		owner.tail = previous
	end
end

return Signal
