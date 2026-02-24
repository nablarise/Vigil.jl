# Copyright (c) 2026 Nablarise
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

###############################################################################
# LOGGING FUNCTIONS
###############################################################################
function _log_jsonl(io::IO, event::String, data::Pair...)
    # Construct the dictionary
    log_entry = Dict{String, Any}(
        "event" => event,
        "timestamp" => string(now()),
        data...
    )

    # Clean serialization via JSON.jl
    JSON.print(io, log_entry)
    println(io)
    flush(io)
end

function _log_plain(io::IO, event::String, data::Pair...)
    data_dict = Dict(data...)

    if event == "system"
        # System messages (e.g., "Waiting for changes...")
        message = get(data_dict, "message", "")
        state = get(data_dict, "state", "")
        if state == "idle"
            println(io, "\n⏳ $message")
        else
            println(io, "ℹ️  $message")
        end

    elseif event == "test_run_start"
        println(io, "\n🔄 Running tests...")

    elseif event == "test_result"
        # Test results for a module
        mod = get(data_dict, "module", "")
        status = get(data_dict, "status", "")
        passed = get(data_dict, "passed", 0)
        failed = get(data_dict, "failed", 0)
        errored = get(data_dict, "errored", 0)
        broken = get(data_dict, "broken", 0)

        icon = status == "success" ? "✓" : "✗"
        println(io, "\n$mod: $icon ($passed passed, $failed failed, $errored errored, $broken broken)")

    elseif event == "test_run_end"
        # Overall test run summary
        status = get(data_dict, "status", "")
        duration = get(data_dict, "duration", 0.0)

        if status == "success"
            println(io, "\n✅ All tests passed ($(duration)s)")
        else
            println(io, "\n❌ Some tests failed ($(duration)s)")
        end

    elseif event == "test_error"
        # Runtime test errors
        error_msg = get(data_dict, "error", "")
        println(io, "\n⚠️  Test Error:")
        println(io, error_msg)

    elseif event == "critical_error"
        # Critical errors (parse, etc.)
        error_type = get(data_dict, "type", "")
        action = get(data_dict, "action", "")
        error_msg = get(data_dict, "error", get(data_dict, "message", ""))

        println(io, "\n🚨 Critical Error ($error_type)")
        println(io, "Action: $action")
        println(io, error_msg)

    else
        # Fallback for unknown events
        println(io, "Event: $event")
        for (k, v) in data_dict
            println(io, "  $k: $v")
        end
    end

    flush(io)
end

function _log_event(io::IO, format::LogFormat, event::String, data::Pair...)
    if format == Plain
        _log_plain(io, event, data...)
    else
        _log_jsonl(io, event, data...)
    end
end

###############################################################################
# ERROR HANDLING
###############################################################################

function _handle_test_error(e::Exception, io::IO, format::LogFormat)
    # Capture full error with stacktrace as string
    error_str = sprint(showerror, e, catch_backtrace())

    # Case 1: Parse Error (Syntax) -> FATAL ERROR -> EXIT
    if e isa Base.Meta.ParseError
        _log_event(io, format, "critical_error",
            "type" => "parse_error",
            "action" => "exiting",
            "error" => error_str
        )
        exit(EXIT_PARSE_ERROR)

    # Case 2: Standard errors (Test failures, runtime bugs) -> Keep running
    else
        _log_event(io, format, "test_error",
            "type" => "runtime_error",
            "error" => error_str
        )
    end
end

###############################################################################
# TEST EXECUTION
###############################################################################

function _run_tests_core(test_modules::Vector{Module}, io::IO, format::LogFormat)
    _log_event(io, format, "test_run_start")
    start_time = time()

    try
        # Suppress Test.jl's default printing for JSONL, allow for plain text
        # Note: This is internal Julia API, might be fragile but necessary here.
        Test.TESTSET_PRINT_ENABLE[] = (format == Plain)

        all_passed = true
        for mod in test_modules
            ts = nothing
            exception_caught = false
            try
                ts = mod.run()  # Capture testset return value
            catch e
                if e isa Test.TestSetException
                    # TestSetException has fields: pass, fail, error, broken
                    exception_caught = true
                    all_passed = false

                    _log_event(io, format, "test_result",
                        "module" => string(mod),
                        "passed" => e.pass,
                        "failed" => e.fail,
                        "errored" => e.error,
                        "broken" => e.broken,
                        "status" => "failed"
                    )
                else
                    # Unexpected error - rethrow to outer handler
                    rethrow()
                end
            end

            # If no exception was caught, log successful testset results
            if !exception_caught && ts !== nothing
                # Count test results manually from the TestSet object
                n_failed = count(r -> r isa Test.Fail, ts.results)
                n_errored = count(r -> r isa Test.Error, ts.results)
                n_broken = count(r -> r isa Test.Broken, ts.results)

                _log_event(io, format, "test_result",
                    "module" => string(mod),
                    "passed" => ts.n_passed,
                    "failed" => n_failed,
                    "errored" => n_errored,
                    "broken" => n_broken,
                    "status" => (n_failed == 0 && n_errored == 0) ? "success" : "failed"
                )

                if n_failed > 0 || n_errored > 0
                    all_passed = false
                end
            end
        end

        duration = round(time() - start_time, digits=3)
        _log_event(io, format, "test_run_end",
            "status" => all_passed ? "success" : "failed",
            "duration" => duration
        )

    catch e
        _handle_test_error(e, io, format)
    end

    _log_event(io, format, "system", "state" => "idle", "message" => "Waiting for changes...")
end

###############################################################################
# WATCH LOOP
###############################################################################

"""
    watch_and_run(
        test_modules::Vector{Module}, 
        track_modules::Vector{Module};
        output_file::Union{String,Nothing}=nothing,
        format::LogFormat=JSONL
    ) -> Nothing

Main entry point for test watching and execution.

# Arguments
- `test_modules`: Vector of test modules to execute (must have `run()` method)
- `track_modules`: Vector of source modules to watch for changes
- `output_file`: Optional path to output file (truncated on each test run). If `nothing`, writes to stdout.
- `format`: Output format - JSONL for structured logs (AI agents), Plain for human-readable (interactive)

# Behavior
- Never returns (runs until killed or fatal error)
- Uses Revise.entr to watch files for changes
- Automatically triggers tests when files change
- Handles 2 types of errors differently:
  1. Parse Error → Exit with EXIT_PARSE_ERROR (fatal)
  2. Runtime Error → Log and continue watching

# Example
```julia
using Vigil
using MyPackage
using MyPackageUnitTests

# Watch and run tests, writing to file in JSONL format
watch_and_run([MyPackageUnitTests], [MyPackage];
              output_file="test/output.log", format=JSONL)

# Or run interactively with plain text output
watch_and_run([MyPackageUnitTests], [MyPackage]; format=Plain)
```
"""
function watch_and_run(
    test_modules::Vector{Module}, 
    track_modules::Vector{Module};
    output_file::Union{String,Nothing}=nothing,
    format::LogFormat=JSONL
)::Nothing
    # Initial startup message
    if !isnothing(output_file)
        touch(output_file)
        open(output_file, "a") do io
            _log_event(io, format, "system", "message" => "Watcher started. Logs redirected to file.")
        end
    else
        _log_event(stdout, format, "system", "message" => "Watcher started. Output to terminal.")
    end

    revise_errored = false

    while true
        try
            entr(
                [],
                [test_modules..., track_modules...];
                postpone = revise_errored,
                all = true,
            ) do
                if !isnothing(output_file)
                    # FILE MODE: Open, write/truncate, and redirect stdout/stderr
                    # We use "w" to clear the log file on each run, keeping it clean for the AI agent.
                    open(output_file, "w") do io
                        redirect_stdio(stdout=io, stderr=io) do
                            _run_tests_core(test_modules, io, format)
                        end
                    end
                else
                    # TERMINAL MODE: Write directly to stdout
                    # No redirection needed, Julia writes to stdout by default.
                    _run_tests_core(test_modules, stdout, format)
                end
            end
        catch e
            # Critical crash in Revise or the watcher itself
            io_target = isnothing(output_file) ? stdout : open(output_file, "a")
            try
                _log_event(io_target, format, "critical_error", "message" => sprint(showerror, e))
            finally
                if !isnothing(output_file)
                    close(io_target)
                end
            end
            # If the watcher itself crashes, we probably should exit too to be safe
            exit(EXIT_PARSE_ERROR)
        end
    end
end
