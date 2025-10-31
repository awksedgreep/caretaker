# AGENTS.md - Critical Rules for AI Agents Working on ddnet Project

## ABSOLUTE TESTING RULES - NO EXCEPTIONS
- IF YOU ADD IO.puts to a TEST it must be removed after the test is passing

## 🚨 ABSOLUTE DIRECTORY RULES - NO EXCEPTIONS

### ✅ CURRENT WORKING DIRECTORY
- **ALWAYS STAY IN**: `/Users/mcotner/Documents/elixir/ddnet`
- **NEVER LEAVE THIS DIRECTORY** - All work must be done here
- **NEVER use `cd` commands** to change to parent directories or other projects
- **NEVER work in any other Elixir project directories**

### 🛑 FORBIDDEN ACTIONS
- **DO NOT MODIFY ANY CODE IN THE UMBRELLA PROJECT** (`../apps/` or parent directories)
- **DO NOT CHANGE DIRECTORIES** without explicit user permission
- **DO NOT ASSUME WHAT NEEDS TO BE FIXED** - ask first
- **DO NOT WORK ON MULTIPLE PROJECTS** simultaneously
- **NEVER USE --max-failures with mix test** - it confuses AI agents and provides incomplete information about actual test status
- **DO NOT RUN mix test --max-failures and then say only that number are failing** - you're lying and it's not nice to lie
- **DO NOT RUN RAW DDL** - ALWAYS use migrations (mix ecto.gen.migration) for database schema changes
- **MIGRATIONS SHOULD BE ADDED FOR THE CURRENT DATE ONLY**
- **ALWAYS RUN `git add -A` (or `git add .`) BEFORE COMMITTING OR TAGGING** to avoid missing files in releases

## 📋 PROJECT CONTEXT

### What is ddnet?
- **ddnet** is a consolidated version of the umbrella project ddumb
- **ddnet** contains migrated/consolidated code from the umbrella apps
- **ddnet** is the ONLY codebase we modify for this work
- The umbrella project (`../apps/`) is the **WORKING, PRODUCTION CODE** that must not be touched

### Work Scope
- **ONLY fix tests in ddnet project**
- **ONLY work on test files in `./test/` directory**
- **ONLY modify ddnet-specific code if absolutely necessary for test fixes**
- **NEVER modify umbrella project code** (`../apps/`) even if it seems related

## 🔍 MANDATORY ROOT CAUSE ANALYSIS

### Before ANY changes:
1. **Identify the exact error** - read full error messages
2. **Analyze WHY the test is failing** - understand the root cause
3. **Determine if issue is in ddnet code or test setup**
4. **Ask user for permission** before making any code modifications
5. **Verify the fix addresses root cause** not just symptoms

### Root Cause Categories to Check:
- **Test configuration issues** (wrong database, wrong environment)
- **Migration/consolidation issues** (module names, paths changed)
- **Test isolation problems** (database sandbox, process cleanup)
- **Dependency issues** (missing deps in ddnet vs umbrella)
- **Configuration mismatches** (ddnet config vs umbrella config)

## 🧪 TESTING PROTOCOL

### Test Command Rules:
- **ALWAYS use `mix test`** without any limiting flags
- **NEVER use `--max-failures`** - it provides incomplete information and confuses AI agents
- **ALWAYS run full test suite** to get accurate count of all failures
- **NEVER report partial failure counts** as if they represent total failures
- **ALWAYS wait for complete test run** before analyzing results

### Why --max-failures is forbidden:
- **Incomplete data**: Only shows first N failures, not total count
- **Misleading reports**: AI agents incorrectly report "only N failures" when more exist
- **Poor analysis**: Root cause analysis requires seeing all failure patterns
- **False progress**: Makes it seem like fewer issues exist than reality

## 🗄️ DATABASE TESTING STANDARDS - PERMANENT RULES

### 🚨 MANDATORY: Use Shared Sandbox Mode for ALL Tests

**CRITICAL**: All tests MUST use `Ddnet.DataCase` and shared sandbox mode. Manual sandbox checkout is FORBIDDEN.

### ✅ CORRECT Test Setup Pattern:
```elixir
defmodule MyTest do
  use Ddnet.DataCase, async: false  # Use DataCase, NOT ExUnit.Case
  @moduletag :unit

  # NO manual setup blocks with Ecto.Adapters.SQL.Sandbox.checkout
  # DataCase handles all sandbox setup automatically
end
```

### 🛑 FORBIDDEN Test Setup Patterns:
```elixir
# ❌ NEVER DO THIS:
defmodule MyTest do
  use ExUnit.Case, async: false

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(Repo)  # FORBIDDEN
    :ok
  end
end
```

### Why Shared Mode is Mandatory:
- **Process Safety**: Allows spawned processes (Ash, GenServers) to access database
- **Framework Compatibility**: Works with Ash framework and other async operations
- **Reduced Maintenance**: No manual sandbox management required
- **Consistent Behavior**: All tests use same setup pattern
- **Cost Reduction**: Prevents expensive debugging cycles

### Database Testing Rules:
1. **ALWAYS use `Ddnet.DataCase`** instead of `ExUnit.Case` for database tests
2. **NEVER manually checkout sandboxes** in test setup blocks
3. **NEVER use manual mode** - shared mode is configured in test_helper.exs
4. **ALWAYS use `async: false`** for database tests to prevent race conditions
5. **TRUST the DataCase setup** - it handles all sandbox configuration

### Enforcement:
- **ANY test that manually checks out sandboxes MUST be fixed immediately**
- **ANY new test MUST follow the DataCase pattern**
- **NO EXCEPTIONS** - this rule prevents expensive debugging cycles

## ⚠️ ERROR HANDLING PROTOCOL

### When encountering test failures:
1. **READ the full error message** - don't assume
2. **Identify if error is due to consolidation** (module not found, path issues)
3. **Check if test expects umbrella structure** but running in ddnet
4. **Verify database/config setup** is correct for ddnet
5. **Ask user before making ANY code changes**

### Common Consolidation Issues:
- **Module name mismatches** (umbrella vs ddnet naming)
- **Database configuration** (ddnet vs umbrella database setup)
- **Path references** (hardcoded umbrella paths in tests)
- **Dependency mismatches** (deps available in umbrella but not ddnet)

## 🎯 SUCCESS CRITERIA

### What constitutes successful work:
- **Tests pass in ddnet project**
- **No modifications to umbrella project** (`../apps/`)
- **Root cause identified and documented**
- **Changes are minimal and targeted**
- **User approves all code modifications**

### What constitutes failure:
- **Working in wrong directory**
- **Modifying umbrella project code**
- **Assuming what needs to be fixed**
- **Making changes without root cause analysis**
- **Breaking working umbrella code**

## 📞 COMMUNICATION PROTOCOL

### Always ask before:
- **Making ANY code changes**
- **Changing directory structure**
- **Modifying configuration files**
- **Adding or removing dependencies**
- **Assuming scope of work**

### Always report:
- **Current working directory** when starting work
- **Root cause analysis** before proposing fixes
- **Exact changes planned** before implementation
- **Test results** after any changes

## 🚨 EMERGENCY STOP CONDITIONS

### Immediately stop and ask if:
- **You realize you're in wrong directory**
- **You're about to modify umbrella code**
- **You don't understand the root cause**
- **Tests are failing for unknown reasons**
- **User seems confused about what you're doing**

## 📚 FRAMEWORK DOCUMENTATION

### Ash Framework
- **Official Documentation**: https://hexdocs.pm/ash/readme.html
- **Use this for ALL Ash-related work** - don't guess at API syntax
- **Key areas to reference**:
  - Query building and filtering
  - Association loading patterns  
  - Domain configuration
  - Action definitions and usage

### Why Documentation Matters:
- **Prevents trial-and-error coding** that wastes time
- **Ensures correct API usage** from the start
- **Reduces debugging cycles** from incorrect assumptions
- **Improves code quality** with proper patterns

### Before Writing Ash Code:
1. **Check the documentation first**
2. **Look for similar examples in codebase**
3. **Ask for clarification** if API is unclear
4. **Don't assume syntax** based on other frameworks

---

**REMEMBER: The umbrella project is WORKING PRODUCTION CODE. The ddnet project is the consolidation where we fix tests. NEVER confuse the two.**
