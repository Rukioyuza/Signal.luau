--!strict

local Task = {
	errors = {} :: { string },
}

function Task.spawn(target: thread | (...any) -> ...any, ...: any): thread
	local thread = if type(target) == "function" then coroutine.create(target) else target

	local resumed, problem = coroutine.resume(thread, ...)
	if not resumed then
		table.insert(Task.errors, tostring(problem))
	end

	return thread
end

return Task
