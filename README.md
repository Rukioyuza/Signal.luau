<h1 align="left">Signal</h1>

<p align="left">
  <img src="https://img.shields.io/badge/Roblox-181717?style=for-the-badge&logo=roblox&logoColor=white" />
  <img src="https://img.shields.io/badge/Luau-181717?style=for-the-badge&logo=luau&logoColor=00A2FF" />
  <img src="https://img.shields.io/badge/Types-Strict-181717?style=for-the-badge" />
</p>

A typed event signal for Roblox. Handlers can disconnect while it fires, they share a reused thread, and an error in one handler does not stop the rest.

---

### API

- **`Signal.new()`** makes a signal. Annotate the local to type its arguments.
- **`Signal:connect(handler)`** runs `handler` on every `fire` and returns a connection.
- **`Signal:once(handler)`** runs `handler` on the next `fire` only.
- **`Signal:wait()`** yields until the next `fire` and returns its arguments.
- **`Signal:fire(...)`** runs every connected handler with the arguments.
- **`Signal:disconnectAll()`** disconnects every handler.
- **`Signal:destroy()`** is `disconnectAll`, so cleanup helpers that call `destroy` work.
- **`Connection:disconnect()`** stops one handler. **`Connection.connected`** says whether it is still connected.

---

### Usage

```luau
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Signal)

local damaged: Signal.Signal<number, string> = Signal.new()

local connection = damaged:connect(function(amount: number, source: string)
	print(amount, source)
end)

damaged:once(function(amount: number)
	print("first hit", amount)
end)

damaged:fire(10, "Lava") -- 10 Lava, then first hit 10
damaged:fire(5, "Spike") -- 5 Spike

connection:disconnect()
print(connection.connected) -- false

task.delay(1, function()
	damaged:fire(20, "Fall")
end)
print(damaged:wait()) -- 20 Fall
```

---

### Behaviour

- **Order.** Handlers run in the order they were connected.
- **Safe disconnects.** Connections are a linked list, so a handler can disconnect itself, another handler or everything while `fire` is running.
- **Late connections.** A handler connected during a `fire` first runs on the next `fire`.
- **Reused thread.** Handlers run on one runner thread that is kept between fires. A new one is made only while the last is still held by a handler that yielded or errored.
- **Errors.** Each handler is started with `task.spawn`, so an error is reported in the output and the other handlers still run.

---

### Install

- **Rojo.** Sync `src` with the included `default.project.json`; it builds a ModuleScript named `Signal`.
- **By hand.** Copy `src/init.luau` into a ModuleScript named `Signal`.

---

### Tests

From the repo root:

```bash
luau tests/Signal.test.luau
```

The standalone `luau` CLI has no `task` library, so the tests put a small stand-in from `tests/Task.luau` into the module's globals before they run. The test file throws when a test fails, so the process exits with an error code.
