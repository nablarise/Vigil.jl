# Vigil.jl

A Julia package for managing test infrastructure with file watching and dual-format logging.

## Features

- **File Watching** - Integrates with Revise.jl to automatically run tests when source files change
- **Fail-Fast Error Handling** - Parse errors exit immediately, runtime errors continue watching

## Quick Start

### 1. Add Vigil to Your Project

Vigil is an unregistered private package.
Add Vigil in your project by doing.
```julia
using Pkg
Pkg.add(url="git@github.com:nablarise/Vigil.jl.git")
```

Add Vigil to your test dependencies in `Project.toml`:

```toml
[extras]
Vigil = "8f3b4e5a-1c2d-4e5f-8a9b-0c1d2e3f4a5b"
# ... other test dependencies

[targets]
test = ["Vigil", "Test", ...]
```

### 2. Organize your tests

Tests are organized in modules (one per test suite) and must be loaded into your LOAD_PATH.
Each test module must have a `run()` function.

### 3. Create a Test Launcher Script

Create `vigil.jl` in your project root:

```julia
# Add test modules to LOAD_PATH
for submodule in filter(item -> isdir(joinpath(@__DIR__, item)), readdir(joinpath(@__DIR__, "test")))
    push!(LOAD_PATH, joinpath(@__DIR__, submodule))
end

using Vigil
using MyPackage
using MyPackageUnitTests

# Parse command line arguments
output_file = length(ARGS) >= 1 ? abspath(ARGS[1]) : nothing
format = isnothing(output_file) ? Vigil.Plain : Vigil.JSONL

# Display startup message
if isnothing(output_file)
    println("Starting test watcher in interactive mode...")
    println("Press Ctrl+C to stop.")
else
    println("Starting test watcher with output to: $output_file")
    println("Press Ctrl+C to stop.")
end

# Run watch loop directly
watch_and_run(
    [MyPackageUnitTests], 
    [MyPackage];
    output_file=output_file, 
    format=format
)
```

### 4. Run Your Tests with Vigil

**Interactive mode** (plain text output):
```bash
julia --project=. vigil.jl
```

**File mode** (JSONL output for AI agents):
```bash
julia --project=. vigil.jl test/output.log
```

## License

This project is licensed under the Mozilla Public License 2.0 (MPL-2.0).

## Prompt to install Vigil in your project with Claude code

> I want to install Vigil, a Julia package for managing test infrastructure, in my current prokject. 
> Use your bash tools to clone the private repository at git@github.com:nablarise/Vigil.jl.git into a temporary directory like /tmp/vigil_pkg, read the README.md file inside it to find the specific installation instructions.
> Copy and paste the exact following instructions to use Vigil into the CLAUDE.md file in my current working directory for future reference :
> > > Please start the Vigil.jl test watcher in the background by running nohup `julia --project=. vigil.jl test_results.jsonl > vigil_system.log 2>&1 &.` This will start the watcher and output the AI-friendly JSONL results into `test_results.jsonl`. Once you verify the background process has started, we will begin editing the source code. Whenever you make a change, you can just read `test_results.jsonl` to automatically see the latest test results without needing to manually run the test command again.
> At the end, delete the temporary folder to clean up.




