# Location Parsing Implementation - Developer Guide

## Table of content

  - [Overview](#overview)
  - [Architecture](#architecture)
    - [Core Module: `lua/gopath/util/location.lua`](#core-module-luagopathutillocationlua)
  - [Supported Formats](#supported-formats)
    - [Format Matrix](#format-matrix)
    - [Parsing Logic Flow](#parsing-logic-flow)
  - [Implementation Details](#implementation-details)
    - [1. Parse Location Function](#1-parse-location-function)
    - [2. Range Normalization](#2-range-normalization)
    - [3. Range Merging Strategy](#3-range-merging-strategy)
  - [Integration Points](#integration-points)
    - [A. Resolvers](#a-resolvers)
    - [B. LSP Provider](#b-lsp-provider)
    - [C. Openers](#c-openers)
  - [Testing Strategy](#testing-strategy)
    - [Unit Tests (Conceptual)](#unit-tests-conceptual)
    - [Manual Testing](#manual-testing)
  - [Error Handling](#error-handling)
    - [Defensive Programming](#defensive-programming)
    - [Edge Cases](#edge-cases)
  - [Performance Considerations](#performance-considerations)
    - [Pattern Matching Efficiency](#pattern-matching-efficiency)
    - [Caching (Future)](#caching-future)
  - [Future Enhancements](#future-enhancements)
    - [1. Custom Format Support](#1-custom-format-support)
    - [2. Range Parsing](#2-range-parsing)
    - [3. Relative Line Numbers](#3-relative-line-numbers)
  - [Common Pitfalls](#common-pitfalls)
    - [❌ Don't: Mix 0-indexed and 1-indexed](#dont-mix-0-indexed-and-1-indexed)
    - [❌ Don't: Assume range exists](#dont-assume-range-exists)
    - [❌ Don't: Parse location multiple times](#dont-parse-location-multiple-times)
  - [Summary](#summary)
    - [Key Takeaways](#key-takeaways)
    - [Integration Checklist](#integration-checklist)

---

## Overview

The location parsing system provides a centralized, consistent way to handle file paths with optional line and column information across all resolvers and openers in gopath.nvim.

---

## Architecture

### Core Module: `lua/gopath/util/location.lua`

This module serves as the single source of truth for parsing and normalizing location information.

**Key Functions:**

1. **`parse_location(str)`** - Parse various location formats
2. **`merge_ranges(parsed, existing)`** - Merge location information
3. **`create_range(line, col)`** - Create normalized range
4. **`normalize_range(range)`** - Ensure valid range values

---

## Supported Formats

### Format Matrix

| Format | Example | Line | Col | Notes |
|--------|---------|------|-----|-------|
| `:line:col` | `file.lua:42:15` | 42 | 15 | Most common |
| `:line` | `file.lua:42` | 42 | 1 | Default col=1 |
| `(line)` | `file.lua(42)` | 42 | 1 | Error message style |
| `(line:col)` | `file.lua(42:15)` | 42 | 15 | Rare variant |
| `+line` | `file.lua +42` | 42 | 1 | Vim command style |

### Parsing Logic Flow

```
Input: "path/to/file.lua:42:15"
         ↓
parse_location()
         ↓
Try patterns in order:
  1. path:line:col → Match ✓
  2. path:line → Skip
  3. path(line) → Skip
  ...
         ↓
Return: { path = "path/to/file.lua", line = 42, col = 15 }
```

---

## Implementation Details

### 1. Parse Location Function

```lua
function M.parse_location(str)
  -- Input validation
  if not str or str == "" then
    return { path = "", line = nil, col = nil }
  end

  -- Format 1: path:line:col (highest priority)
  local path, line, col = str:match("^(.+):(%d+):(%d+)$")
  if path then
    return {
      path = path,
      line = tonumber(line),
      col = tonumber(col),
    }
  end

  -- Format 2: path:line (common fallback)
  path, line = str:match("^(.+):(%d+)$")
  if path then
    return {
      path = path,
      line = tonumber(line),
      col = 1,  -- Default column
    }
  end

  -- Additional formats...
  -- (See full implementation)

  -- No location info found
  return {
    path = str,
    line = nil,
    col = nil,
  }
end
```

**Design Decisions:**

- **Order matters**: Most specific patterns first (`path:line:col` before `path:line`)
- **Greedy matching**: `(.+)` captures everything before location suffix
- **Defaults**: Column defaults to 1 when not specified
- **Type safety**: Always returns table with `path`, `line`, `col` keys

---

### 2. Range Normalization

```lua
function M.normalize_range(range)
  if not range or not range.line then
    return nil
  end

  return {
    line = math.max(1, range.line),  -- Ensure >= 1
    col = math.max(1, range.col or 1),
  }
end
```

**Why Normalize?**

- **LSP compatibility**: LSP uses 0-indexed positions, must convert to 1-indexed
- **Validation**: Prevent invalid positions (line 0, negative columns)
- **Consistency**: Unified format for all downstream consumers

---

### 3. Range Merging Strategy

```lua
function M.merge_ranges(parsed, existing)
  -- Parsed location takes precedence
  if parsed.line then
    return {
      line = parsed.line,
      col = parsed.col or 1,
    }
  end

  -- Fallback to existing range
  if existing and existing.line then
    return {
      line = existing.line,
      col = existing.col or 1,
    }
  end

  return nil  -- No location info available
end
```

**Use Case:**

When a resolver finds a file path with embedded location info (e.g., from `<cfile>`), but also has semantic information (e.g., from LSP), merge the two intelligently.

**Priority Order:**
1. Parsed location (from user input/text)
2. Existing range (from resolver/LSP)
3. nil (no location information)

---

## Integration Points

### A. Resolvers

All resolvers that produce file paths should use location utilities:

```lua
-- lua/gopath/resolvers/common/filetoken.lua

local LOC = require("gopath.util.location")

function M.resolve()
  local raw = expand_cfile()
  local parsed = LOC.parse_location(raw)

  -- Search for file using parsed.path (without :line:col)
  local abs = find_file(parsed.path)

  return {
    path = abs,
    range = LOC.create_range(parsed.line, parsed.col),
    -- ...
  }
end
```

**Benefits:**
- Single parsing logic (DRY principle)
- Consistent handling across all resolvers
- Easy to add new formats (change one place)

---

### B. LSP Provider

LSP returns 0-indexed positions that must be converted:

```lua
-- lua/gopath/providers/lsp.lua

local LOC = require("gopath.util.location")

function M.definition_at_cursor(timeout_ms)
  -- LSP request...

  for _, loc in ipairs(locations) do
    local range = loc.range

    -- Convert LSP 0-indexed to 1-indexed
    local normalized = LOC.normalize_range({
      line = range.start.line + 1,
      col = range.start.character + 1,
    })

    results[#results + 1] = {
      path = path,
      range = normalized,
    }
  end
end
```

**Critical:** Always normalize LSP ranges before storing in results!

---

### C. Openers

All openers must respect and apply range information:

```lua
-- lua/gopath/open/edit.lua

local LOC = require("gopath.util.location")

function M.open(res)
  vim.cmd.edit(vim.fn.fnameescape(res.path))

  if res.range then
    local normalized = LOC.normalize_range(res.range)
    if normalized then
      local l = normalized.line
      local c = normalized.col - 1  -- nvim_win_set_cursor uses 0-indexed cols

      pcall(vim.api.nvim_win_set_cursor, 0, { l, c })
      vim.cmd("normal! zz")  -- Center line in window
    end
  end
end
```

**Important:**
- `nvim_win_set_cursor` expects `{ line, col }` where:
  - `line` is 1-indexed
  - `col` is 0-indexed (subtract 1 from normalized value)
- Always use `pcall` to prevent errors on invalid positions
- Center line with `zz` for better UX

---

## Testing Strategy

### Unit Tests (Conceptual)

```lua
describe("location.parse_location", function()
  it("parses path:line:col format", function()
    local result = LOC.parse_location("file.lua:42:15")
    assert.equals("file.lua", result.path)
    assert.equals(42, result.line)
    assert.equals(15, result.col)
  end)

  it("defaults column to 1 for path:line", function()
    local result = LOC.parse_location("file.lua:42")
    assert.equals(1, result.col)
  end)

  it("handles parenthesis format", function()
    local result = LOC.parse_location("file.lua(42)")
    assert.equals(42, result.line)
  end)

  it("returns path-only when no location info", function()
    local result = LOC.parse_location("file.lua")
    assert.equals("file.lua", result.path)
    assert.is_nil(result.line)
    assert.is_nil(result.col)
  end)
end)
```

### Manual Testing

```lua
-- In Neovim command line
:lua local LOC = require("gopath.util.location")
:lua print(vim.inspect(LOC.parse_location("file.lua:42:15")))
-- Expected: { path = "file.lua", line = 42, col = 15 }

:lua print(vim.inspect(LOC.parse_location("init.lua(100)")))
-- Expected: { path = "init.lua", line = 100, col = 1 }
```

---

## Error Handling

### Defensive Programming

```lua
-- Always validate inputs
if not str or str == "" then
  return { path = "", line = nil, col = nil }
end

-- Always validate before using
if res.range then
  local normalized = LOC.normalize_range(res.range)
  if normalized then  -- Check normalization succeeded
    -- Use normalized values
  end
end
```

### Edge Cases

| Input | Expected Behavior |
|-------|-------------------|
| `""` (empty) | Return `{ path = "", line = nil, col = nil }` |
| `"file.lua:"` | Return `{ path = "file.lua:", line = nil, col = nil }` (no digits) |
| `"file.lua:0"` | Parse as line 0, normalize to line 1 |
| `"file.lua:-5"` | No match (negative not in pattern), return path only |
| `"file.lua:99999"` | Parse as line 99999 (Vim handles invalid lines gracefully) |

---

## Performance Considerations

### Pattern Matching Efficiency

Patterns are tried in **descending specificity order**:
1. Most specific: `path:line:col`
2. Common: `path:line`
3. Less common: `path(line)`
4. Rare: `path(line:col)`, `path +line`

**Why?**
- Early exit on match (most formats are `:line` or `:line:col`)
- Avoids unnecessary pattern attempts

### Caching (Future)

Currently no caching. Future optimization:

```lua
-- Cache parsed results for repeated calls on same string
local cache = setmetatable({}, { __mode = "k" })

function M.parse_location(str)
  if cache[str] then
    return cache[str]
  end

  local result = do_parse(str)
  cache[str] = result
  return result
end
```

**When to add?** Only if profiling shows `parse_location` is a bottleneck.

---

## Future Enhancements

### 1. Custom Format Support

Allow users to register custom location patterns:

```lua
-- User config
opts = {
  location = {
    custom_formats = {
      { pattern = "^(.+)%s*@%s*(%d+)$", line_group = 2 },  -- file @ line
    },
  },
}
```

### 2. Range Parsing

Support range selections (start:end):

```lua
"file.lua:10-20"  -- Lines 10 to 20
"file.lua:10:5-20:15"  -- Line 10 col 5 to line 20 col 15
```

### 3. Relative Line Numbers

Support relative jumps:

```lua
"file.lua:+10"  -- Jump 10 lines down from current
"file.lua:-5"   -- Jump 5 lines up from current
```

---

## Common Pitfalls

### ❌ Don't: Mix 0-indexed and 1-indexed

```lua
-- BAD
local line = range.line  -- Might be 0-indexed from LSP
vim.api.nvim_win_set_cursor(0, { line, col })  -- Expects 1-indexed!
```

```lua
-- GOOD
local normalized = LOC.normalize_range(range)  -- Always 1-indexed
vim.api.nvim_win_set_cursor(0, { normalized.line, normalized.col - 1 })
```

### ❌ Don't: Assume range exists

```lua
-- BAD
vim.api.nvim_win_set_cursor(0, { res.range.line, res.range.col })
-- Crashes if res.range is nil!
```

```lua
-- GOOD
if res.range then
  local normalized = LOC.normalize_range(res.range)
  if normalized then
    vim.api.nvim_win_set_cursor(0, { normalized.line, normalized.col - 1 })
  end
end
```

### ❌ Don't: Parse location multiple times

```lua
-- BAD (inefficient)
local parsed1 = LOC.parse_location(str)
-- ... some code ...
local parsed2 = LOC.parse_location(str)  -- Redundant!
```

```lua
-- GOOD
local parsed = LOC.parse_location(str)
-- Use parsed multiple times
```

---

## Summary

### Key Takeaways

1. **Centralized parsing** prevents inconsistencies
2. **Normalization** ensures valid, consistent ranges
3. **LSP conversion** is critical (0-indexed → 1-indexed)
4. **Defensive checks** prevent crashes on invalid data
5. **Pattern order** matters for performance

### Integration Checklist

When adding a new resolver or opener:

- [ ] Import `gopath.util.location`
- [ ] Use `parse_location()` for any string with potential location info
- [ ] Use `normalize_range()` before using range values
- [ ] Handle nil ranges gracefully
- [ ] Convert to 0-indexed columns for `nvim_win_set_cursor`
- [ ] Test with various location formats

---

