--!strict

local Signal = require("../src")
local Task = require("./Task")

type Signal<Args...> = Signal.Signal<Args...>
type Connection<Args...> = Signal.Connection<Args...>

local moduleGlobals: any = getfenv(Signal.new)
moduleGlobals.task = Task

local passed = 0
local failed = 0

local function test(name: string, body: () -> ()): ()
	table.clear(Task.errors)

	local finished, problem = pcall(body)
	if finished then
		passed += 1
	else
		failed += 1
		print(`FAIL {name}: {problem}`)
	end
end

local function expect(condition: boolean, message: string): ()
	if not condition then
		error(message, 2)
	end
end

test("Fire passes every argument to every handler in connection order", function()
	local changed: Signal<number, string> = Signal.new()
	local seen: { string } = {}

	changed:connect(function(amount: number, source: string): ()
		table.insert(seen, `first {amount} {source}`)
	end)
	changed:connect(function(amount: number, source: string): ()
		table.insert(seen, `second {amount} {source}`)
	end)
	changed:fire(5, "Lava")

	expect(#seen == 2, "both handlers should run")
	expect(seen[1] == "first 5 Lava", "first handler should run first")
	expect(seen[2] == "second 5 Lava", "second handler should run second")
end)

test("Fire keeps nil arguments and their count", function()
	local changed: Signal<number?, number?> = Signal.new()
	local count = 0
	local second: number? = nil

	changed:connect(function(...: number?): ()
		count = select("#", ...)
		second = select(2, ...)
	end)
	changed:fire(nil, 2)

	expect(count == 2, "the handler should get two arguments")
	expect(second == 2, "the second argument should be 2")
end)

test("Disconnect stops a handler and is safe to call twice", function()
	local changed: Signal<> = Signal.new()
	local runs = 0

	local Connection = changed:connect(function(): ()
		runs += 1
	end)
	changed:fire()
	Connection:disconnect()
	Connection:disconnect()
	changed:fire()

	expect(runs == 1, "the handler should run once")
	expect(Connection.connected == false, "Connected should be false")
end)

test("A handler can disconnect itself during Fire", function()
	local changed: Signal<> = Signal.new()
	local seen: { string } = {}

	local first: Connection<>
	first = changed:connect(function(): ()
		table.insert(seen, "first")
		first:disconnect()
	end)
	changed:connect(function(): ()
		table.insert(seen, "second")
	end)
	changed:fire()
	changed:fire()

	expect(table.concat(seen, " ") == "first second second", "the second handler should keep running")
end)

test("A handler can disconnect the next handler during Fire", function()
	local changed: Signal<> = Signal.new()
	local seen: { string } = {}

	local second: Connection<>
	changed:connect(function(): ()
		table.insert(seen, "first")
		second:disconnect()
	end)
	second = changed:connect(function(): ()
		table.insert(seen, "second")
	end)
	changed:connect(function(): ()
		table.insert(seen, "third")
	end)
	changed:fire()

	expect(table.concat(seen, " ") == "first third", "the disconnected handler should not run")
end)

test("A handler connected during Fire first runs on the next Fire", function()
	local changed: Signal<> = Signal.new()
	local seen: { string } = {}
	local hasConnected = false

	changed:connect(function(): ()
		table.insert(seen, "first")
		if hasConnected then
			return
		end
		hasConnected = true
		changed:connect(function(): ()
			table.insert(seen, "late")
		end)
	end)
	changed:fire()

	expect(table.concat(seen, " ") == "first", "the late handler should wait for the next Fire")

	changed:fire()

	expect(table.concat(seen, " ") == "first first late", "the late handler should run on the next Fire")
end)

test("Connecting after the tail was disconnected keeps the order", function()
	local changed: Signal<> = Signal.new()
	local seen: { string } = {}

	changed:connect(function(): ()
		table.insert(seen, "a")
	end)
	local tail = changed:connect(function(): ()
		table.insert(seen, "b")
	end)
	tail:disconnect()
	changed:connect(function(): ()
		table.insert(seen, "c")
	end)
	changed:fire()

	expect(table.concat(seen, " ") == "a c", "handlers should run as a then c")
end)

test("Once runs a single time and reports itself disconnected", function()
	local changed: Signal<number> = Signal.new()
	local total = 0

	local Connection = changed:once(function(amount: number): ()
		total += amount
	end)
	changed:fire(3)
	changed:fire(4)

	expect(total == 3, "the handler should only see the first Fire")
	expect(Connection.connected == false, "Connected should be false after it ran")
end)

test("Wait resumes the waiting thread with the fired arguments", function()
	local changed: Signal<number, string> = Signal.new()
	local gotAmount: number? = nil
	local gotSource: string? = nil

	local waiter = coroutine.create(function(): ()
		gotAmount, gotSource = changed:wait()
	end)
	coroutine.resume(waiter)

	expect(coroutine.status(waiter) == "suspended", "the waiter should be suspended before Fire")

	changed:fire(7, "Spike")

	expect(gotAmount == 7 and gotSource == "Spike", "the waiter should get both arguments")
	expect(coroutine.status(waiter) == "dead", "the waiter should have finished")
	expect(changed.head == nil, "the Wait connection should be gone")
end)

test("An error in one handler does not stop the others", function()
	local changed: Signal<> = Signal.new()
	local runs = 0

	changed:connect(function(): ()
		runs += 1
	end)
	changed:connect(function(): ()
		error("broken handler")
	end)
	changed:connect(function(): ()
		runs += 1
	end)
	changed:fire()
	changed:fire()

	expect(runs == 4, "both working handlers should run on both fires")
	expect(#Task.errors == 2, "each error should be reported")
	expect(string.find(Task.errors[1], "broken handler", 1, true) ~= nil, "the report should hold the message")
end)

test("Handlers reuse one runner thread", function()
	local changed: Signal<> = Signal.new()
	local threads: { thread } = {}

	changed:connect(function(): ()
		table.insert(threads, coroutine.running())
	end)
	changed:connect(function(): ()
		table.insert(threads, coroutine.running())
	end)
	changed:fire()
	changed:fire()

	expect(#threads == 4, "every handler should run")
	expect(threads[1] == threads[2], "handlers in one Fire should share the runner")
	expect(threads[1] == threads[4], "the next Fire should reuse the runner")
end)

test("A yielding handler gets its own runner and the next Fire still runs", function()
	local changed: Signal<> = Signal.new()
	local seen: { string } = {}
	local yielded: thread? = nil

	changed:connect(function(): ()
		if yielded then
			table.insert(seen, "again")
			return
		end
		yielded = coroutine.running()
		coroutine.yield()
		table.insert(seen, "resumed")
	end)
	changed:fire()
	changed:fire()

	local held = yielded :: thread
	coroutine.resume(held)

	expect(table.concat(seen, " ") == "again resumed", "both runs should finish")
	expect(coroutine.status(held) == "suspended", "the resumed runner should wait for more work")
end)

test("DisconnectAll during Fire stops the rest and marks every connection", function()
	local changed: Signal<> = Signal.new()
	local seen: { string } = {}

	local first = changed:connect(function(): ()
		table.insert(seen, "first")
		changed:disconnectAll()
	end)
	local second = changed:connect(function(): ()
		table.insert(seen, "second")
	end)
	changed:fire()
	changed:fire()

	expect(table.concat(seen, " ") == "first", "only the first handler should run")
	expect(not first.connected and not second.connected, "both connections should be disconnected")
end)

test("Destroy disconnects every handler", function()
	local changed: Signal<> = Signal.new()
	local runs = 0

	local Connection = changed:connect(function(): ()
		runs += 1
	end)
	changed:destroy()
	changed:fire()

	expect(runs == 0, "no handler should run after Destroy")
	expect(Connection.connected == false, "Connected should be false")
end)

test("Connect refuses something that is not a function", function()
	local changed: Signal<> = Signal.new()

	local connected = pcall(function(): ()
		changed:connect(5 :: any)
	end)

	expect(not connected, "Connect should error")
	expect(changed.head == nil, "nothing should be connected")
end)

print(`{passed} passed, {failed} failed`)

if failed > 0 then
	error(`{failed} Signal tests failed`)
end
