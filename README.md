# TestAgent.jl

A Julia package for managing test infrastructure with file watching and dual-format logging.

## Features

- **Pure Julia** - No Bash dependencies, works on all platforms including Windows
- **Dual-Format Logging** - JSONL for AI agents, human-readable plain text for interactive use
- **File Watching** - Integrates with Revise.jl to automatically run tests when source files change
- **Fail-Fast Error Handling** - Parse errors exit immediately, runtime errors continue watching
- **Clean API** - Simple keyword arguments, no complex configuration structs
- **Type-Safe** - Explicit type signatures throughout, no `Any` types

## Installation

Since TestAgent.jl is under development, install it using:

```julia
using Pkg
Pkg.develop(path="/path/to/TestAgent.jl")
```

Or add it to your dev environment:

```bash
julia --project=@. -e 'using Pkg; Pkg.develop(path="/path/to/TestAgent.jl")'
```

## Quick Start

### 1. Add TestAgent to Your Project

Add TestAgent to your test dependencies in `Project.toml`:

```toml
[extras]
TestAgent = "8f3b4e5a-1c2d-4e5f-8a9b-0c1d2e3f4a5b"
# ... other test dependencies

[targets]
test = ["TestAgent", "Test", ...]
```

### 2. Update Your test/runtests.jl

```julia
# Load test modules into LOAD_PATH
for submodule in filter(item -> isdir(joinpath(@__DIR__, item)), readdir(@__DIR__))
    push!(LOAD_PATH, joinpath(@__DIR__, submodule))
end

using EmptyPackage
using EmptyPackageUnitTests
using Test

# Test suites to run (must have run() method)
test_suites = [EmptyPackageUnitTests]

# Manual test execution (for CI/CD via Pkg.test)
# Watch mode is handled by start_tests.jl directly
for mod in test_suites
    mod.run()
end
```

### 3. Create a Test Launcher Script

Create `start_tests.jl` in your project root:

```julia
#!/usr/bin/env julia --project=@.

# Add test modules to LOAD_PATH
push!(LOAD_PATH, joinpath(@__DIR__, "test", "MyPackageUnitTests"))

using TestAgent
using MyPackage
using MyPackageUnitTests

# Parse command line arguments
output_file = length(ARGS) >= 1 ? abspath(ARGS[1]) : nothing
format = isnothing(output_file) ? TestAgent.Plain : TestAgent.JSONL

# Display startup message
if isnothing(output_file)
    println("Starting test watcher in interactive mode...")
    println("Press Ctrl+C to stop.")
else
    println("Starting test watcher with output to: $output_file")
    println("Press Ctrl+C to stop.")
end

# Run watch loop directly
watch_and_run([MyPackageUnitTests], [MyPackage];
              output_file=output_file, format=format)
```

Make it executable:
```bash
chmod +x start_tests.jl
```

### 4. Run Your Tests

**Interactive mode** (plain text output):
```bash
./start_tests.jl
```

**File mode** (JSONL output for AI agents):
```bash
./start_tests.jl test/output.log
```

**CI/CD mode** (via Pkg.test):
```julia
using Pkg
Pkg.test()
```

## API Reference

### `watch_and_run`

Main entry point for test watching and execution.

```julia
watch_and_run(test_modules::Vector{Module}, track_modules::Vector{Module};
              output_file::Union{String,Nothing}=nothing,
              format::LogFormat=JSONL)::Nothing
```

**Arguments:**
- `test_modules`: Vector of test modules to execute (must have `run()` method)
- `track_modules`: Vector of source modules to watch for changes
- `output_file`: Optional path to output file (truncated on each test run). If `nothing`, writes to stdout.
- `format`: Output format - `JSONL` for structured logs, `Plain` for human-readable

**Behavior:**
- Never returns (runs until killed or fatal error)
- Uses `Revise.entr` to watch files for changes
- Automatically triggers tests when files change
- Handles 2 types of errors:
  1. Parse Error → Exit with `EXIT_PARSE_ERROR` (fatal)
  2. Runtime Error → Log and continue watching

**Example:**
```julia
using TestAgent
using MyPackage
using MyPackageUnitTests

watch_and_run([MyPackageUnitTests], [MyPackage];
              output_file="test/output.log", format=JSONL)
```

### Exit Codes

TestAgent uses named constants instead of magic numbers:

```julia
EXIT_SUCCESS = 0          # Normal, successful exit
EXIT_PARSE_ERROR = 1      # Parse/syntax error - fatal
```

These constants are exported and can be used in your code:

```julia
using TestAgent

if exit_code == EXIT_SUCCESS
    # Clean exit
elseif exit_code == EXIT_PARSE_ERROR
    # Parse error - fix syntax and retry
end
```

## Log Formats

TestAgent supports two output formats via the `LogFormat` enum:

```julia
using TestAgent

# Human-readable format (interactive use)
watch_and_run(tests, targets; format=Plain)

# JSON Lines format (AI agents, structured logging)
watch_and_run(tests, targets; format=JSONL)
```

The enum values are:
- `Plain` - Human-readable text with Unicode symbols (✓ ✗ ⏳ 🔄)
- `JSONL` - Structured JSON Lines, one event per line

The enum provides type safety - the compiler will catch typos and invalid format values at compile time rather than runtime.

## Output Formats

### JSONL Format (for AI Agents)

Structured JSON Lines format, one event per line:

```json
{"event":"test_run_start","timestamp":"2026-02-14T16:11:05.099"}
{"event":"test_result","passed":4,"status":"success","module":"MyTests","broken":0,"timestamp":"2026-02-14T16:11:05.182","failed":0,"errored":0}
{"duration":0.083,"event":"test_run_end","status":"success","timestamp":"2026-02-14T16:11:05.182"}
{"event":"system","message":"Waiting for changes...","timestamp":"2026-02-14T16:11:05.182","state":"idle"}
```

### Plain Text Format (for Humans)

Human-readable format with Unicode symbols:

```
ℹ️  Watcher started. Output to terminal.

🔄 Running tests...
Test Summary:    | Pass  Total  Time
MyTests          |    4      4  0.0s

MyTests: ✓ (4 passed, 0 failed, 0 errored, 0 broken)

✅ All tests passed (0.083s)

⏳ Waiting for changes...
```

## Error Handling

TestAgent implements a 2-tier error response system:

### 1. Parse Errors (Exit Code 1)

Syntax errors are fatal and cannot be recovered automatically.

**What happens:**
- Test runner detects parse error
- Logs critical error with details
- Exits with code 1

**Solution:** Fix the syntax error and restart the watcher.

### 2. Runtime Errors (No Exit)

Test failures and runtime errors are logged but don't stop the watch loop.

**What happens:**
- Error is caught and logged
- Watch loop continues
- Tests run again on next file change

## Requirements

- Julia 1.6 or later
- Revise.jl 3.x
- JSON.jl 0.21 or 1.x
- Test.jl (stdlib)
- Dates.jl (stdlib)

## Design Philosophy

TestAgent follows these principles:

1. **No Magic Numbers** - All exit codes are named constants
2. **Strict Typing** - Explicit type signatures, no `Any` types
3. **Minimal API** - Direct keyword arguments, no complex config structs
4. **Clean Separation** - Launcher manages lifecycle, runner manages tests
5. **Fail-Fast** - Parse errors are fatal
6. **Graceful Degradation** - Runtime errors don't stop the watch loop

## License

This project is licensed under the Mozilla Public License 2.0 (MPL-2.0).

## Contributing

Contributions are welcome! Please ensure:
- All functions have explicit type signatures
- No `Any` types in public API or critical paths
- Exit codes use named constants
- Code is documented with docstrings

## Acknowledgments

Inspired by:
- [Revise.jl watching patterns](https://gist.github.com/torfjelde/62c1281d5fc486d3a404e5de6cf285d4)
- [Coluna.jl test infrastructure](https://github.com/atoptima/Coluna.jl/blob/master/test/revise.jl)
