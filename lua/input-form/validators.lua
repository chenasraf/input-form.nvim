--- Validators for form inputs.
---
--- A validator is a function `fun(value): string|nil`. It receives the
--- current input value and returns a non-empty error message string when
--- invalid, or `nil` / `""` when valid.
---
--- This module exposes factory functions for common validators plus a
--- `chain` combinator that runs several validators in order and returns the
--- first error.
---
---@tag input-form.validators

local M = {}

--- Require the field to have a non-empty value.
---@param msg string|nil Override error message.
---@return function
function M.non_empty(msg)
  msg = msg or "This field is required"
  return function(value)
    if value == nil then
      return msg
    end
    if type(value) == "string" and value == "" then
      return msg
    end
    return nil
  end
end

--- Require the value's length to be at least `n` characters.
---@param n integer
---@param msg string|nil
---@return function
function M.min_length(n, msg)
  return function(value)
    local s = type(value) == "string" and value or tostring(value or "")
    if vim.fn.strchars(s) < n then
      return msg or ("Must be at least " .. n .. " characters")
    end
    return nil
  end
end

--- Require the value's length to be at most `n` characters.
---@param n integer
---@param msg string|nil
---@return function
function M.max_length(n, msg)
  return function(value)
    local s = type(value) == "string" and value or tostring(value or "")
    if vim.fn.strchars(s) > n then
      return msg or ("Must be at most " .. n .. " characters")
    end
    return nil
  end
end

--- Require the value to match a Lua pattern.
---@param pattern string Lua pattern (not PCRE).
---@param msg string|nil
---@return function
function M.matches(pattern, msg)
  return function(value)
    local s = type(value) == "string" and value or tostring(value or "")
    if not s:match(pattern) then
      return msg or "Invalid format"
    end
    return nil
  end
end

--- Require the value to parse as a number.
---@param msg string|nil
---@return function
function M.is_number(msg)
  return function(value)
    if value == nil or value == "" or tonumber(value) == nil then
      return msg or "Must be a number"
    end
    return nil
  end
end

--- Require the value to be one of the given choices (useful for text inputs
--- that must match a fixed allowlist; select inputs should use their
--- `options` list instead).
---@param choices table List of allowed values.
---@param msg string|nil
---@return function
function M.one_of(choices, msg)
  return function(value)
    for _, c in ipairs(choices) do
      if c == value then
        return nil
      end
    end
    return msg or "Value is not allowed"
  end
end

--- Wrap a predicate `fun(value): boolean` as a validator.
---@param predicate function
---@param msg string Error message to return when the predicate is false.
---@return function
function M.custom(predicate, msg)
  return function(value)
    if predicate(value) then
      return nil
    end
    return msg
  end
end

--- Combine multiple validators. Runs them in order and returns the first
--- non-empty error. Accepts either a list table or a varargs list.
---@param ... function|table
---@return function
function M.chain(...)
  local validators = { ... }
  if
    #validators == 1
    and type(validators[1]) == "table"
    and type(validators[1][1]) == "function"
  then
    validators = validators[1]
  end
  return function(value)
    for _, v in ipairs(validators) do
      local err = v(value)
      if err and err ~= "" then
        return err
      end
    end
    return nil
  end
end

return M
