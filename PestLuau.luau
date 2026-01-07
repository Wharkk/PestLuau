--!strict
--[[
    ===========================================================================
    
      Pest for Luau
      The elegant testing framework
    
      Inspired by PestPHP - A testing framework with a focus on simplicity
    
      Usage:
          local Pest = require(path.to.Pest)
          local test, it, describe, expect = Pest.test, Pest.it,
              Pest.describe, Pest.expect
    
          describe("Calculator", function()
              it("adds numbers", function()
                  expect(1 + 1):toBe(2)
              end)
          end)
    
          Pest.run()
    
    ===========================================================================
]]

-- ===============================================================================
-- Type Definitions
-- ===============================================================================

export type TestFn = () -> ()

export type TestCase = {
	description: string,
	fn: TestFn?,
	skip: boolean,
	only: boolean,
	tags: {string},
	timeout: number,
}

export type HooksContainer = {
	beforeEach: {() -> ()},
	afterEach: {() -> ()},
	beforeAll: {() -> ()},
	afterAll: {() -> ()},
}

export type TestSuite = {
	name: string,
	tests: {TestCase},
	children: {TestSuite},
	hooks: HooksContainer,
	parent: TestSuite?,
	only: boolean,
	skip: boolean,
}

export type TestResult = {
	description: string,
	suite: string,
	passed: boolean,
	skipped: boolean,
	duration: number,
	error: string?,
}

export type TestSummary = {
	passed: number,
	failed: number,
	skipped: number,
	duration: number,
	results: {TestResult},
}

export type ReporterConfig = {
	verbose: boolean,
	colors: boolean,
	stopOnFirstFailure: boolean,
}

-- ===============================================================================
-- Utility Functions
-- ===============================================================================

local function deepEqual(a: any, b: any): boolean
	if typeof(a) ~= typeof(b) then
		return false
	end

	if typeof(a) == "table" then
		local tableA = a :: {[any]: any}
		local tableB = b :: {[any]: any}

		for key, value in tableA do
			if not deepEqual(value, tableB[key]) then
				return false
			end
		end

		for key, _ in tableB do
			if tableA[key] == nil then
				return false
			end
		end

		return true
	end

	return a == b
end

local function formatValue(value: any): string
	local valueType = typeof(value)

	if value == nil then
		return "nil"
	elseif valueType == "string" then
		return `"{value}"`
	elseif valueType == "table" then
		local parts: {string} = {}
		local isArray = true
		local maxIndex = 0

		for key, _ in value :: {[any]: any} do
			if typeof(key) ~= "number" then
				isArray = false
				break
			end
			maxIndex = math.max(maxIndex, key)
		end

		if isArray and maxIndex > 0 then
			local arr = value :: {any}
			for i = 1, math.min(maxIndex, 5) do
				table.insert(parts, formatValue(arr[i]))
			end
			if maxIndex > 5 then
				table.insert(parts, `... +{maxIndex - 5} more`)
			end
			return `\{{table.concat(parts, ", ")}\}`
		else
			local count = 0
			for key, val in value :: {[any]: any} do
				if count < 3 then
					table.insert(parts, `{tostring(key)}: {formatValue(val)}`)
				end
				count += 1
			end
			if count > 3 then
				table.insert(parts, `... +{count - 3} more`)
			end
			return `\{{table.concat(parts, ", ")}\}`
		end
	elseif valueType == "Instance" then
		local inst = value :: Instance
		return `<{inst.ClassName} "{inst.Name}">`
	elseif valueType == "function" then
		return "<function>"
	else
		return tostring(value)
	end
end

local function getTableLength(t: {[any]: any}): number
	local count = 0
	for _ in t do
		count += 1
	end
	return count
end

local function formatDuration(seconds: number): string
	if seconds < 0.001 then
		return `{math.floor(seconds * 1000000)}µs`
	elseif seconds < 1 then
		return `{math.floor(seconds * 1000)}ms`
	else
		return `{string.format("%.2f", seconds)}s`
	end
end

-- ===============================================================================
-- Colors & Symbols
-- ===============================================================================

local Colors = {
	reset = "\27[0m",
	bold = "\27[1m",
	dim = "\27[2m",
	red = "\27[31m",
	green = "\27[32m",
	yellow = "\27[33m",
	cyan = "\27[36m",
	white = "\27[37m",
	gray = "\27[90m",
}

local Symbols = {
	pass = "+",
	fail = "x",
	skip = "o",
	arrow = "->",
}

-- ===============================================================================
-- Expectation API
-- ===============================================================================

local customMatchers: {[string]: (any, ...any) -> any} = {}

export type Expectation<T> = {
	value: T,
	isNot: boolean,

	not_: (self: Expectation<T>) -> Expectation<T>,
	never: (self: Expectation<T>) -> Expectation<T>,
	toBe: (self: Expectation<T>, expected: T) -> Expectation<T>,
	toEqual: (self: Expectation<T>, expected: T) -> Expectation<T>,
	toStrictEqual: (self: Expectation<T>, expected: T) -> Expectation<T>,
	toBeTruthy: (self: Expectation<T>) -> Expectation<T>,
	toBeFalsy: (self: Expectation<T>) -> Expectation<T>,
	toBeNil: (self: Expectation<T>) -> Expectation<T>,
	toBeDefined: (self: Expectation<T>) -> Expectation<T>,
	toBeTrue: (self: Expectation<T>) -> Expectation<T>,
	toBeFalse: (self: Expectation<T>) -> Expectation<T>,
	toBeGreaterThan: (self: Expectation<T>, expected: number) -> Expectation<T>,
	toBeGreaterThanOrEqual: (self: Expectation<T>, expected: number) -> Expectation<T>,
	toBeLessThan: (self: Expectation<T>, expected: number) -> Expectation<T>,
	toBeLessThanOrEqual: (self: Expectation<T>, expected: number) -> Expectation<T>,
	toBeCloseTo: (self: Expectation<T>, expected: number, precision: number?) -> Expectation<T>,
	toBeBetween: (self: Expectation<T>, min: number, max: number) -> Expectation<T>,
	toBePositive: (self: Expectation<T>) -> Expectation<T>,
	toBeNegative: (self: Expectation<T>) -> Expectation<T>,
	toBeInteger: (self: Expectation<T>) -> Expectation<T>,
	toBeNaN: (self: Expectation<T>) -> Expectation<T>,
	toBeA: (self: Expectation<T>, expectedType: string) -> Expectation<T>,
	toBeType: (self: Expectation<T>, expectedType: string) -> Expectation<T>,
	toBeInstanceOf: (self: Expectation<T>, className: string) -> Expectation<T>,
	toStartWith: (self: Expectation<T>, prefix: string) -> Expectation<T>,
	toEndWith: (self: Expectation<T>, suffix: string) -> Expectation<T>,
	toContainString: (self: Expectation<T>, substring: string) -> Expectation<T>,
	toMatch: (self: Expectation<T>, pattern: string) -> Expectation<T>,
	toHaveLength: (self: Expectation<T>, length: number) -> Expectation<T>,
	toBeEmpty: (self: Expectation<T>) -> Expectation<T>,
	toBeUpperCase: (self: Expectation<T>) -> Expectation<T>,
	toBeLowerCase: (self: Expectation<T>) -> Expectation<T>,
	toContain: (self: Expectation<T>, item: any) -> Expectation<T>,
	toContainEqual: (self: Expectation<T>, item: any) -> Expectation<T>,
	toContainKey: (self: Expectation<T>, key: any) -> Expectation<T>,
	toHaveKey: (self: Expectation<T>, key: any, value: any?) -> Expectation<T>,
	toMatchObject: (self: Expectation<T>, subset: {[any]: any}) -> Expectation<T>,
	toBeArray: (self: Expectation<T>) -> Expectation<T>,
	toBeTable: (self: Expectation<T>) -> Expectation<T>,
	toThrow: (self: Expectation<T>, expectedError: string?) -> Expectation<T>,
	toThrowError: (self: Expectation<T>, expectedError: string?) -> Expectation<T>,
	toBeA_Instance: (self: Expectation<T>) -> Expectation<T>,
	toBeDescendantOf: (self: Expectation<T>, ancestor: Instance) -> Expectation<T>,
	toBeAncestorOf: (self: Expectation<T>, descendant: Instance) -> Expectation<T>,
	toHaveProperty: (self: Expectation<T>, property: string, value: any?) -> Expectation<T>,
	toHaveAttribute: (self: Expectation<T>, attribute: string, value: any?) -> Expectation<T>,
	property: (self: Expectation<T>, name: string) -> Expectation<any>,
}

local function assert_(
	expectation: Expectation<any>,
	condition: boolean,
	messageOnFail: string,
	messageOnFailNegated: string
)
	local shouldPass = if expectation.isNot then not condition else condition

	if not shouldPass then
		local message = if expectation.isNot then messageOnFailNegated else messageOnFail
		error(message, 4)
	end
end

local ExpectationMethods = {} :: {[string]: any}

function ExpectationMethods.not_(self: Expectation<any>): Expectation<any>
	self.isNot = true
	return self
end

ExpectationMethods.never = ExpectationMethods.not_

-- Equality
function ExpectationMethods.toBe<T>(self: Expectation<T>, expected: T): Expectation<T>
	assert_(
		self,
		self.value == expected,
		`Expected {formatValue(self.value)} to be {formatValue(expected)}`,
		`Expected {formatValue(self.value)} not to be {formatValue(expected)}`
	)
	return self
end

function ExpectationMethods.toEqual<T>(self: Expectation<T>, expected: T): Expectation<T>
	assert_(
		self,
		deepEqual(self.value, expected),
		`Expected {formatValue(self.value)} to equal {formatValue(expected)}`,
		`Expected {formatValue(self.value)} not to equal {formatValue(expected)}`
	)
	return self
end

function ExpectationMethods.toStrictEqual<T>(self: Expectation<T>, expected: T): Expectation<T>
	local sameType = typeof(self.value) == typeof(expected)
	local sameValue = deepEqual(self.value, expected)

	assert_(
		self,
		sameType and sameValue,
		`Expected {formatValue(self.value)} to strictly equal {formatValue(expected)}`,
		`Expected {formatValue(self.value)} not to strictly equal {formatValue(expected)}`
	)
	return self
end

-- Truthiness
function ExpectationMethods.toBeTruthy<T>(self: Expectation<T>): Expectation<T>
	assert_(
		self,
		self.value ~= nil and self.value ~= false,
		`Expected {formatValue(self.value)} to be truthy`,
		`Expected {formatValue(self.value)} not to be truthy`
	)
	return self
end

function ExpectationMethods.toBeFalsy<T>(self: Expectation<T>): Expectation<T>
	assert_(
		self,
		self.value == nil or self.value == false,
		`Expected {formatValue(self.value)} to be falsy`,
		`Expected {formatValue(self.value)} not to be falsy`
	)
	return self
end

function ExpectationMethods.toBeNil<T>(self: Expectation<T>): Expectation<T>
	assert_(
		self,
		self.value == nil,
		`Expected {formatValue(self.value)} to be nil`,
		`Expected value not to be nil`
	)
	return self
end

function ExpectationMethods.toBeDefined<T>(self: Expectation<T>): Expectation<T>
	assert_(
		self,
		self.value ~= nil,
		`Expected value to be defined, got nil`,
		`Expected {formatValue(self.value)} to be nil`
	)
	return self
end

function ExpectationMethods.toBeTrue<T>(self: Expectation<T>): Expectation<T>
	assert_(
		self,
		self.value == true,
		`Expected {formatValue(self.value)} to be true`,
		`Expected value not to be true`
	)
	return self
end

function ExpectationMethods.toBeFalse<T>(self: Expectation<T>): Expectation<T>
	assert_(
		self,
		self.value == false,
		`Expected {formatValue(self.value)} to be false`,
		`Expected value not to be false`
	)
	return self
end

-- Numbers
function ExpectationMethods.toBeGreaterThan<T>(self: Expectation<T>, expected: number): Expectation<T>
	local value = self.value :: number
	assert_(
		self,
		value > expected,
		`Expected {value} to be greater than {expected}`,
		`Expected {value} not to be greater than {expected}`
	)
	return self
end

function ExpectationMethods.toBeGreaterThanOrEqual<T>(self: Expectation<T>, expected: number): Expectation<T>
	local value = self.value :: number
	assert_(
		self,
		value >= expected,
		`Expected {value} to be greater than or equal to {expected}`,
		`Expected {value} not to be greater than or equal to {expected}`
	)
	return self
end

function ExpectationMethods.toBeLessThan<T>(self: Expectation<T>, expected: number): Expectation<T>
	local value = self.value :: number
	assert_(
		self,
		value < expected,
		`Expected {value} to be less than {expected}`,
		`Expected {value} not to be less than {expected}`
	)
	return self
end

function ExpectationMethods.toBeLessThanOrEqual<T>(self: Expectation<T>, expected: number): Expectation<T>
	local value = self.value :: number
	assert_(
		self,
		value <= expected,
		`Expected {value} to be less than or equal to {expected}`,
		`Expected {value} not to be less than or equal to {expected}`
	)
	return self
end

function ExpectationMethods.toBeCloseTo<T>(self: Expectation<T>, expected: number, precision: number?): Expectation<T>
	local value = self.value :: number
	local numDigits = precision or 2
	local epsilon = 10 ^ -numDigits / 2

	assert_(
		self,
		math.abs(value - expected) < epsilon,
		`Expected {value} to be close to {expected} (precision: {numDigits})`,
		`Expected {value} not to be close to {expected} (precision: {numDigits})`
	)
	return self
end

function ExpectationMethods.toBeBetween<T>(self: Expectation<T>, min: number, max: number): Expectation<T>
	local value = self.value :: number
	assert_(
		self,
		value >= min and value <= max,
		`Expected {value} to be between {min} and {max}`,
		`Expected {value} not to be between {min} and {max}`
	)
	return self
end

function ExpectationMethods.toBePositive<T>(self: Expectation<T>): Expectation<T>
	local value = self.value :: number
	assert_(
		self,
		value > 0,
		`Expected {value} to be positive`,
		`Expected {value} not to be positive`
	)
	return self
end

function ExpectationMethods.toBeNegative<T>(self: Expectation<T>): Expectation<T>
	local value = self.value :: number
	assert_(
		self,
		value < 0,
		`Expected {value} to be negative`,
		`Expected {value} not to be negative`
	)
	return self
end

function ExpectationMethods.toBeInteger<T>(self: Expectation<T>): Expectation<T>
	local value = self.value :: number
	assert_(
		self,
		value == math.floor(value),
		`Expected {value} to be an integer`,
		`Expected {value} not to be an integer`
	)
	return self
end

function ExpectationMethods.toBeNaN<T>(self: Expectation<T>): Expectation<T>
	local value = self.value :: number
	assert_(
		self,
		value ~= value,
		`Expected {formatValue(self.value)} to be NaN`,
		`Expected value not to be NaN`
	)
	return self
end

-- Types
function ExpectationMethods.toBeA<T>(self: Expectation<T>, expectedType: string): Expectation<T>
	local actualType = typeof(self.value)
	assert_(
		self,
		actualType == expectedType,
		`Expected {formatValue(self.value)} to be a {expectedType}, got {actualType}`,
		`Expected {formatValue(self.value)} not to be a {expectedType}`
	)
	return self
end

ExpectationMethods.toBeType = ExpectationMethods.toBeA

function ExpectationMethods.toBeInstanceOf<T>(self: Expectation<T>, className: string): Expectation<T>
	local value = self.value
	local isInstance = typeof(value) == "Instance"
	local matches = isInstance and (value :: Instance):IsA(className)

	assert_(
		self,
		matches,
		`Expected {formatValue(self.value)} to be an instance of {className}`,
		`Expected {formatValue(self.value)} not to be an instance of {className}`
	)
	return self
end

-- Strings
function ExpectationMethods.toStartWith<T>(self: Expectation<T>, prefix: string): Expectation<T>
	local value = self.value :: string
	assert_(
		self,
		string.sub(value, 1, #prefix) == prefix,
		`Expected "{value}" to start with "{prefix}"`,
		`Expected "{value}" not to start with "{prefix}"`
	)
	return self
end

function ExpectationMethods.toEndWith<T>(self: Expectation<T>, suffix: string): Expectation<T>
	local value = self.value :: string
	assert_(
		self,
		string.sub(value, -#suffix) == suffix,
		`Expected "{value}" to end with "{suffix}"`,
		`Expected "{value}" not to end with "{suffix}"`
	)
	return self
end

function ExpectationMethods.toContainString<T>(self: Expectation<T>, substring: string): Expectation<T>
	local value = self.value :: string
	assert_(
		self,
		string.find(value, substring, 1, true) ~= nil,
		`Expected "{value}" to contain "{substring}"`,
		`Expected "{value}" not to contain "{substring}"`
	)
	return self
end

function ExpectationMethods.toMatch<T>(self: Expectation<T>, pattern: string): Expectation<T>
	local value = self.value :: string
	assert_(
		self,
		string.match(value, pattern) ~= nil,
		`Expected "{value}" to match pattern "{pattern}"`,
		`Expected "{value}" not to match pattern "{pattern}"`
	)
	return self
end

function ExpectationMethods.toHaveLength<T>(self: Expectation<T>, length: number): Expectation<T>
	local value = self.value
	local actualLength: number

	if typeof(value) == "string" then
		actualLength = #(value :: string)
	elseif typeof(value) == "table" then
		actualLength = getTableLength(value :: {[any]: any})
	else
		actualLength = 0
	end

	assert_(
		self,
		actualLength == length,
		`Expected length {actualLength} to be {length}`,
		`Expected length {actualLength} not to be {length}`
	)
	return self
end

function ExpectationMethods.toBeEmpty<T>(self: Expectation<T>): Expectation<T>
	local value = self.value
	local isEmpty: boolean

	if typeof(value) == "string" then
		isEmpty = (value :: string) == ""
	elseif typeof(value) == "table" then
		isEmpty = next(value :: {[any]: any}) == nil
	else
		isEmpty = false
	end

	assert_(
		self,
		isEmpty,
		`Expected {formatValue(self.value)} to be empty`,
		`Expected {formatValue(self.value)} not to be empty`
	)
	return self
end

function ExpectationMethods.toBeUpperCase<T>(self: Expectation<T>): Expectation<T>
	local value = self.value :: string
	assert_(
		self,
		value == string.upper(value),
		`Expected "{value}" to be uppercase`,
		`Expected "{value}" not to be uppercase`
	)
	return self
end

function ExpectationMethods.toBeLowerCase<T>(self: Expectation<T>): Expectation<T>
	local value = self.value :: string
	assert_(
		self,
		value == string.lower(value),
		`Expected "{value}" to be lowercase`,
		`Expected "{value}" not to be lowercase`
	)
	return self
end

-- Tables/Arrays
function ExpectationMethods.toContain<T>(self: Expectation<T>, item: any): Expectation<T>
	local value = self.value :: {any}
	local found = false

	for _, v in value do
		if v == item then
			found = true
			break
		end
	end

	assert_(
		self,
		found,
		`Expected array to contain {formatValue(item)}`,
		`Expected array not to contain {formatValue(item)}`
	)
	return self
end

function ExpectationMethods.toContainEqual<T>(self: Expectation<T>, item: any): Expectation<T>
	local value = self.value :: {any}
	local found = false

	for _, v in value do
		if deepEqual(v, item) then
			found = true
			break
		end
	end

	assert_(
		self,
		found,
		`Expected array to contain equal {formatValue(item)}`,
		`Expected array not to contain equal {formatValue(item)}`
	)
	return self
end

function ExpectationMethods.toContainKey<T>(self: Expectation<T>, key: any): Expectation<T>
	local value = self.value :: {[any]: any}
	assert_(
		self,
		value[key] ~= nil,
		`Expected table to contain key {formatValue(key)}`,
		`Expected table not to contain key {formatValue(key)}`
	)
	return self
end

function ExpectationMethods.toHaveKey<T>(self: Expectation<T>, key: any, expectedValue: any?): Expectation<T>
	local value = self.value :: {[any]: any}
	local hasKey = value[key] ~= nil
	local matchesValue = expectedValue == nil or deepEqual(value[key], expectedValue)

	if expectedValue ~= nil then
		assert_(
			self,
			hasKey and matchesValue,
			`Expected table to have key {formatValue(key)} with value {formatValue(expectedValue)}, got {formatValue(value[key])}`,
			`Expected table not to have key {formatValue(key)} with value {formatValue(expectedValue)}`
		)
	else
		assert_(
			self,
			hasKey,
			`Expected table to have key {formatValue(key)}`,
			`Expected table not to have key {formatValue(key)}`
		)
	end
	return self
end

function ExpectationMethods.toMatchObject<T>(self: Expectation<T>, subset: {[any]: any}): Expectation<T>
	local value = self.value :: {[any]: any}
	local matches = true

	for key, expectedValue in subset do
		if not deepEqual(value[key], expectedValue) then
			matches = false
			break
		end
	end

	assert_(
		self,
		matches,
		`Expected {formatValue(self.value)} to match object {formatValue(subset)}`,
		`Expected {formatValue(self.value)} not to match object {formatValue(subset)}`
	)
	return self
end

function ExpectationMethods.toBeArray<T>(self: Expectation<T>): Expectation<T>
	local value = self.value
	local isArray = typeof(value) == "table"

	if isArray then
		local tbl = value :: {[any]: any}
		for key, _ in tbl do
			if typeof(key) ~= "number" then
				isArray = false
				break
			end
		end
	end

	assert_(
		self,
		isArray,
		`Expected {formatValue(self.value)} to be an array`,
		`Expected {formatValue(self.value)} not to be an array`
	)
	return self
end

function ExpectationMethods.toBeTable<T>(self: Expectation<T>): Expectation<T>
	assert_(
		self,
		typeof(self.value) == "table",
		`Expected {formatValue(self.value)} to be a table`,
		`Expected {formatValue(self.value)} not to be a table`
	)
	return self
end

-- Functions/Errors
function ExpectationMethods.toThrow<T>(self: Expectation<T>, expectedError: string?): Expectation<T>
	local fn = self.value :: () -> ()
	local success, err = pcall(fn)
	local didThrow = not success

	if expectedError and didThrow then
		local errStr = tostring(err)
		local matches = string.find(errStr, expectedError, 1, true) ~= nil
		assert_(
			self,
			matches,
			`Expected function to throw error containing "{expectedError}", got "{errStr}"`,
			`Expected function not to throw error containing "{expectedError}"`
		)
	else
		assert_(
			self,
			didThrow,
			`Expected function to throw an error`,
			`Expected function not to throw an error`
		)
	end

	return self
end

ExpectationMethods.toThrowError = ExpectationMethods.toThrow

-- Roblox-specific
function ExpectationMethods.toBeA_Instance<T>(self: Expectation<T>): Expectation<T>
	assert_(
		self,
		typeof(self.value) == "Instance",
		`Expected {formatValue(self.value)} to be an Instance`,
		`Expected {formatValue(self.value)} not to be an Instance`
	)
	return self
end

function ExpectationMethods.toBeDescendantOf<T>(self: Expectation<T>, ancestor: Instance): Expectation<T>
	local value = self.value :: Instance
	assert_(
		self,
		value:IsDescendantOf(ancestor),
		`Expected {formatValue(self.value)} to be a descendant of {ancestor.Name}`,
		`Expected {formatValue(self.value)} not to be a descendant of {ancestor.Name}`
	)
	return self
end

function ExpectationMethods.toBeAncestorOf<T>(self: Expectation<T>, descendant: Instance): Expectation<T>
	local value = self.value :: Instance
	assert_(
		self,
		value:IsAncestorOf(descendant),
		`Expected {formatValue(self.value)} to be an ancestor of {descendant.Name}`,
		`Expected {formatValue(self.value)} not to be an ancestor of {descendant.Name}`
	)
	return self
end

function ExpectationMethods.toHaveProperty<T>(self: Expectation<T>, property: string, expectedValue: any?): Expectation<T>
	local value = self.value :: Instance
	local success, propValue = pcall(function()
		return (value :: any)[property]
	end)

	if not success then
		assert_(
			self,
			false,
			`Expected {formatValue(self.value)} to have property "{property}"`,
			`Expected {formatValue(self.value)} not to have property "{property}"`
		)
	elseif expectedValue ~= nil then
		assert_(
			self,
			deepEqual(propValue, expectedValue),
			`Expected property "{property}" to be {formatValue(expectedValue)}, got {formatValue(propValue)}`,
			`Expected property "{property}" not to be {formatValue(expectedValue)}`
		)
	else
		assert_(
			self,
			propValue ~= nil,
			`Expected {formatValue(self.value)} to have property "{property}"`,
			`Expected {formatValue(self.value)} not to have property "{property}"`
		)
	end

	return self
end

function ExpectationMethods.toHaveAttribute<T>(self: Expectation<T>, attribute: string, expectedValue: any?): Expectation<T>
	local value = self.value :: Instance
	local attrValue = value:GetAttribute(attribute)

	if expectedValue ~= nil then
		assert_(
			self,
			deepEqual(attrValue, expectedValue),
			`Expected attribute "{attribute}" to be {formatValue(expectedValue)}, got {formatValue(attrValue)}`,
			`Expected attribute "{attribute}" not to be {formatValue(expectedValue)}`
		)
	else
		assert_(
			self,
			attrValue ~= nil,
			`Expected {formatValue(self.value)} to have attribute "{attribute}"`,
			`Expected {formatValue(self.value)} not to have attribute "{attribute}"`
		)
	end

	return self
end

-- Higher order expectations
function ExpectationMethods.property<T>(self: Expectation<T>, name: string): Expectation<any>
	local value = self.value :: any
	local propValue = value[name]
	-- Forward declaration issue - we'll call the factory directly
	local newExp = {
		value = propValue,
		isNot = false,
	}
	for n, method in ExpectationMethods do
		(newExp :: any)[n] = method
	end
	return newExp :: any
end

-- Expectation factory
local function expect<T>(value: T): Expectation<T>
	local expectation = {
		value = value,
		isNot = false,
	}

	for name, method in ExpectationMethods do
		(expectation :: any)[name] = method
	end

	for name, matcher in customMatchers do
		(expectation :: any)[name] = matcher
	end

	return expectation :: any
end

local function extendExpect(name: string, matcher: (any, ...any) -> any)
	customMatchers[name] = matcher
end

-- ===============================================================================
-- Test Registry & Runner
-- ===============================================================================

local config = {
	stopOnFirstFailure = false,
	verbose = true,
	colors = false, -- Disabled by default (Roblox output doesn't support ANSI)
	timeout = 5,
}

local function newHooks(): HooksContainer
	return {
		beforeEach = {},
		afterEach = {},
		beforeAll = {},
		afterAll = {},
	}
end

local rootSuite: TestSuite = {
	name = "Root",
	tests = {},
	children = {},
	hooks = newHooks(),
	parent = nil,
	only = false,
	skip = false,
}

local currentSuite: TestSuite? = nil

local function getActiveSuite(): TestSuite
	return currentSuite or rootSuite
end

-- Test functions
local function test(description: string, fn: TestFn?): TestCase
	local suite = getActiveSuite()

	local testCase: TestCase = {
		description = description,
		fn = fn,
		skip = false,
		only = false,
		tags = {},
		timeout = config.timeout,
	}

	table.insert(suite.tests, testCase)
	return testCase
end

local function it(description: string, fn: TestFn?): TestCase
	return test(description, fn)
end

local function describe(name: string, fn: () -> ()): TestSuite
	local parentSuite = getActiveSuite()

	local suite: TestSuite = {
		name = name,
		tests = {},
		children = {},
		hooks = newHooks(),
		parent = parentSuite,
		only = false,
		skip = false,
	}

	table.insert(parentSuite.children, suite)

	currentSuite = suite
	local success, err = pcall(fn)
	currentSuite = parentSuite

	if not success then
		warn(`[Pest] Error in describe block "{name}": {err}`)
	end

	return suite
end

-- Test modifiers
local function testSkip(description: string, fn: TestFn?): TestCase
	local testCase = test(description, fn)
	testCase.skip = true
	return testCase
end

local function testOnly(description: string, fn: TestFn?): TestCase
	local testCase = test(description, fn)
	testCase.only = true
	return testCase
end

local function testTodo(description: string): TestCase
	local testCase = test(description, nil)
	testCase.skip = true
	testCase.tags = {"todo"}
	return testCase
end

local function testEach<T>(datasets: {T}): (string, (T) -> ()) -> ()
	return function(description: string, fn: (T) -> ())
		for i, data in datasets do
			local desc = description
			if typeof(data) == "table" then
				local dataTable = data :: {any}
				for _, value in dataTable do
					desc = string.gsub(desc, "%%[dsfq]", tostring(value), 1)
				end
			end

			test(`{desc} (dataset #{i})`, function()
				fn(data)
			end)
		end
	end
end

-- Create callable test with modifiers
local testWithModifiers = setmetatable({
	skip = testSkip,
	only = testOnly,
	each = testEach,
	todo = testTodo,
}, {
	__call = function(_, description: string, fn: TestFn?): TestCase
		return test(description, fn)
	end,
})

local itWithModifiers = setmetatable({
	skip = testSkip,
	only = testOnly,
	each = testEach,
	todo = testTodo,
}, {
	__call = function(_, description: string, fn: TestFn?): TestCase
		return it(description, fn)
	end,
})

-- Hooks
local function beforeEach(fn: () -> ())
	local suite = getActiveSuite()
	table.insert(suite.hooks.beforeEach, fn)
end

local function afterEach(fn: () -> ())
	local suite = getActiveSuite()
	table.insert(suite.hooks.afterEach, fn)
end

local function beforeAll(fn: () -> ())
	local suite = getActiveSuite()
	table.insert(suite.hooks.beforeAll, fn)
end

local function afterAll(fn: () -> ())
	local suite = getActiveSuite()
	table.insert(suite.hooks.afterAll, fn)
end

-- ===============================================================================
-- Reporter
-- ===============================================================================

local function color(useColors: boolean, code: string, text: string): string
	if useColors then
		return `{code}{text}{Colors.reset}`
	end
	return text
end

local function reportStart()
	local header = [[

 +------------------------------------------+
 |                                          |
 |   Pest for Luau                          |
 |   The elegant testing framework          |
 |                                          |
 +------------------------------------------+
]]

	if config.colors then
		print(color(true, Colors.cyan, header))
	else
		print(header)
	end
end

local currentReportSuite: string? = nil

local function reportTest(result: TestResult, suite: TestSuite)
	local useColors = config.colors

	if suite.name ~= currentReportSuite and suite.name ~= "Root" then
		currentReportSuite = suite.name
		print("")
		print(color(useColors, Colors.bold .. Colors.white, `  {suite.name}`))
	end

	local symbol: string
	local textColor: string

	if result.skipped then
		symbol = Symbols.skip
		textColor = Colors.yellow
	elseif result.passed then
		symbol = Symbols.pass
		textColor = Colors.green
	else
		symbol = Symbols.fail
		textColor = Colors.red
	end

	local durationStr = ""
	if result.duration > 0 and config.verbose then
		durationStr = color(useColors, Colors.gray, ` ({formatDuration(result.duration)})`)
	end

	local prefix = if result.description:sub(1, 3) == "it " then "" else "it "
	local line = `    {color(useColors, textColor, symbol)} {color(useColors, Colors.gray, prefix)}{result.description}{durationStr}`
	print(line)

	if not result.passed and not result.skipped and result.error then
		print("")
		print(color(useColors, Colors.red, `      {Symbols.arrow} {result.error}`))
		print("")
	end
end

local function reportSummary(data: TestSummary)
	local useColors = config.colors

	print("")
	print(color(useColors, Colors.dim, `  {string.rep("-", 50)}`))
	print("")

	local passedText = color(useColors, Colors.green .. Colors.bold, `{data.passed} passed`)
	local failedText = if data.failed > 0 
		then color(useColors, Colors.red .. Colors.bold, `{data.failed} failed`)
		else color(useColors, Colors.gray, "0 failed")
	local skippedText = if data.skipped > 0
		then color(useColors, Colors.yellow, `{data.skipped} skipped`)
		else ""

	local countParts = {passedText, failedText}
	if data.skipped > 0 then
		table.insert(countParts, skippedText)
	end

	print(`  Tests:    {table.concat(countParts, color(useColors, Colors.gray, ", "))}`)
	print(`  Duration: {color(useColors, Colors.cyan, formatDuration(data.duration))}`)
	print("")

	if data.failed == 0 then
		local successBanner = [[
  +----------------------------------------+
  |  ** All tests passed!                  |
  +----------------------------------------+
]]
		print(color(useColors, Colors.green, successBanner))
	else
		local failBanner = [[
  +----------------------------------------+
  |  !! Some tests failed                  |
  +----------------------------------------+
]]
		print(color(useColors, Colors.red, failBanner))

		if config.verbose then
			print(color(useColors, Colors.red .. Colors.bold, "  Failed Tests:"))
			print("")

			for _, result in data.results do
				if not result.passed and not result.skipped then
					print(color(useColors, Colors.red, `    - {result.suite} > {result.description}`))
					if result.error then
						local errMsg = result.error
						if #errMsg > 100 then
							errMsg = string.sub(errMsg, 1, 100) .. "..."
						end
						print(color(useColors, Colors.gray, `      {errMsg}`))
					end
				end
			end
			print("")
		end
	end
end

-- ===============================================================================
-- Test Execution
-- ===============================================================================

local function hasOnlyTests(suite: TestSuite): boolean
	for _, testCase in suite.tests do
		if testCase.only then
			return true
		end
	end
	for _, child in suite.children do
		if child.only or hasOnlyTests(child) then
			return true
		end
	end
	return false
end

local function shouldRunTest(testCase: TestCase, hasOnly: boolean): boolean
	if testCase.skip then
		return false
	end
	if hasOnly and not testCase.only then
		return false
	end
	return true
end

local function collectHooks(suite: TestSuite, hookType: string): {() -> ()}
	local hooks: {() -> ()} = {}

	local current: TestSuite? = suite
	local chain: {TestSuite} = {}

	while current do
		table.insert(chain, 1, current)
		current = current.parent
	end

	for _, s in chain do
		local suiteHooks = s.hooks :: any
		local hookList = suiteHooks[hookType]
		if hookList then
			for _, hook in hookList do
				table.insert(hooks, hook)
			end
		end
	end

	return hooks
end

local function runTest(testCase: TestCase, suite: TestSuite): TestResult
	local result: TestResult = {
		description = testCase.description,
		suite = suite.name,
		passed = false,
		skipped = false,
		duration = 0,
		error = nil,
	}

	if testCase.skip or testCase.fn == nil then
		result.skipped = true
		return result
	end

	local beforeHooks = collectHooks(suite, "beforeEach")
	for _, hook in beforeHooks do
		local success, err = pcall(hook)
		if not success then
			result.error = `beforeEach hook failed: {err}`
			return result
		end
	end

	local startTime = os.clock()
	local success, err = pcall(testCase.fn :: TestFn)
	result.duration = os.clock() - startTime

	if success then
		result.passed = true
	else
		result.error = tostring(err)
	end

	local afterHooks = collectHooks(suite, "afterEach")
	for _, hook in afterHooks do
		pcall(hook)
	end

	return result
end

local function runSuite(suite: TestSuite, hasOnly: boolean): {TestResult}
	local results: {TestResult} = {}

	for _, hook in suite.hooks.beforeAll do
		local success, err = pcall(hook)
		if not success then
			warn(`[Pest] beforeAll hook failed in "{suite.name}": {err}`)
		end
	end

	for _, testCase in suite.tests do
		if shouldRunTest(testCase, hasOnly) then
			local result = runTest(testCase, suite)
			table.insert(results, result)
			reportTest(result, suite)

			if not result.passed and not result.skipped and config.stopOnFirstFailure then
				break
			end
		elseif testCase.skip then
			local result: TestResult = {
				description = testCase.description,
				suite = suite.name,
				passed = false,
				skipped = true,
				duration = 0,
				error = nil,
			}
			table.insert(results, result)
			reportTest(result, suite)
		end
	end

	for _, child in suite.children do
		local childResults = runSuite(child, hasOnly)
		for _, result in childResults do
			table.insert(results, result)
		end
	end

	for _, hook in suite.hooks.afterAll do
		pcall(hook)
	end

	return results
end

local function run(options: {
	stopOnFirstFailure: boolean?,
	verbose: boolean?,
	colors: boolean?,
	}?): {passed: number, failed: number, skipped: number, duration: number}

	if options then
		if options.stopOnFirstFailure ~= nil then
			config.stopOnFirstFailure = options.stopOnFirstFailure
		end
		if options.verbose ~= nil then
			config.verbose = options.verbose
		end
		if options.colors ~= nil then
			config.colors = options.colors
		end
	end

	reportStart()
	currentReportSuite = nil

	local hasOnly = hasOnlyTests(rootSuite)
	local startTime = os.clock()
	local results = runSuite(rootSuite, hasOnly)
	local totalDuration = os.clock() - startTime

	local passed, failed, skipped = 0, 0, 0
	for _, result in results do
		if result.skipped then
			skipped += 1
		elseif result.passed then
			passed += 1
		else
			failed += 1
		end
	end

	reportSummary({
		passed = passed,
		failed = failed,
		skipped = skipped,
		duration = totalDuration,
		results = results,
	})

	-- Reset for next run
	rootSuite.tests = {}
	rootSuite.children = {}
	rootSuite.hooks = newHooks()

	return {
		passed = passed,
		failed = failed,
		skipped = skipped,
		duration = totalDuration,
	}
end

local function configure(options: {
	stopOnFirstFailure: boolean?,
	verbose: boolean?,
	colors: boolean?,
	timeout: number?,
	})
	if options.stopOnFirstFailure ~= nil then
		config.stopOnFirstFailure = options.stopOnFirstFailure
	end
	if options.verbose ~= nil then
		config.verbose = options.verbose
	end
	if options.colors ~= nil then
		config.colors = options.colors
	end
	if options.timeout ~= nil then
		config.timeout = options.timeout
	end
end

-- ===============================================================================
-- Module Export
-- ===============================================================================

return {
	-- Core test functions
	test = testWithModifiers :: any,
	it = itWithModifiers :: any,
	describe = describe,

	-- Expectation
	expect = expect,

	-- Hooks
	beforeEach = beforeEach,
	afterEach = afterEach,
	beforeAll = beforeAll,
	afterAll = afterAll,

	-- Runner
	run = run,
	configure = configure,

	-- Extensions
	extendExpect = extendExpect,
}
