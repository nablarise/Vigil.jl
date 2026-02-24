# Copyright (c) 2026 Nablarise
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

using TestAgent
using Test
using JSON

###############################################################################
# HELPER TEST MODULES
###############################################################################

"""
Mock test module that always passes all tests.
"""
module PassingTests
    using Test
    function run()
        @testset "PassingTests" begin
            @test 1 + 1 == 2
            @test true
            @test "hello" == "hello"
        end
    end
end

"""
Mock test module that has test failures.
"""
module FailingTests
    using Test
    function run()
        @testset "FailingTests" begin
            @test 1 + 1 == 2  # Pass
            @test 1 + 1 == 3  # Fail
        end
    end
end

"""
Mock test module that has errors.
"""
module ErrorTests
    using Test
    function run()
        @testset "ErrorTests" begin
            @test 1 + 1 == 2      # Pass
            @test error("boom")   # Error
        end
    end
end

"""
Mock test module with broken tests.
"""
module BrokenTests
    using Test
    function run()
        @testset "BrokenTests" begin
            @test 1 + 1 == 2                    # Pass
            @test_broken 1 + 1 == 3             # Broken (expected to fail)
        end
    end
end

###############################################################################
# TEST SUITE
###############################################################################

@testset "TestAgent.jl" begin

    ###########################################################################
    # BASIC API TESTS (Smoke Tests)
    ###########################################################################

    @testset "Module Structure" begin
        @testset "Exit Code Constants" begin
            @test EXIT_SUCCESS == 0
            @test EXIT_PARSE_ERROR == 1
            @test EXIT_SUCCESS != EXIT_PARSE_ERROR
        end

        @testset "LogFormat Enum" begin
            @test isdefined(TestAgent, :LogFormat)
            @test isdefined(TestAgent, :Plain)
            @test isdefined(TestAgent, :JSONL)
            @test Plain != JSONL
            @test typeof(Plain) == LogFormat
            @test typeof(JSONL) == LogFormat
            @test Integer(Plain) == 1
            @test Integer(JSONL) == 2
        end

        @testset "Exports" begin
            @test isdefined(TestAgent, :watch_and_run)
            @test isdefined(TestAgent, :EXIT_SUCCESS)
            @test isdefined(TestAgent, :EXIT_PARSE_ERROR)
            @test hasmethod(watch_and_run, (Vector{Module}, Vector{Module}))
        end
    end

    ###########################################################################
    # LOGGING BEHAVIOR TESTS
    ###########################################################################

    @testset "Logging Functions" begin
        @testset "JSONL Format" begin
            # Test that _log_jsonl produces valid JSON
            io = IOBuffer()
            TestAgent._log_jsonl(io, "test_event", "key1" => "value1", "key2" => 42)

            output = String(take!(io))
            lines = split(strip(output), '\n')

            @test length(lines) == 1  # Should be single line

            # Parse JSON to verify it's valid
            parsed = JSON.parse(lines[1])
            @test parsed["event"] == "test_event"
            @test parsed["key1"] == "value1"
            @test parsed["key2"] == 42
            @test haskey(parsed, "timestamp")
        end

        @testset "Plain Format - System Events" begin
            io = IOBuffer()
            TestAgent._log_plain(io, "system", "state" => "idle", "message" => "Waiting...")

            output = String(take!(io))
            @test occursin("⏳", output)
            @test occursin("Waiting...", output)
        end

        @testset "Plain Format - Test Run Start" begin
            io = IOBuffer()
            TestAgent._log_plain(io, "test_run_start")

            output = String(take!(io))
            @test occursin("🔄", output)
            @test occursin("Running tests", output)
        end

        @testset "Plain Format - Test Results" begin
            io = IOBuffer()
            TestAgent._log_plain(io, "test_result",
                "module" => "TestModule",
                "status" => "success",
                "passed" => 5,
                "failed" => 0,
                "errored" => 0,
                "broken" => 0
            )

            output = String(take!(io))
            @test occursin("TestModule", output)
            @test occursin("✓", output)  # Success icon
            @test occursin("5 passed", output)
        end

        @testset "Plain Format - Failed Tests" begin
            io = IOBuffer()
            TestAgent._log_plain(io, "test_result",
                "module" => "TestModule",
                "status" => "failed",
                "passed" => 3,
                "failed" => 2,
                "errored" => 1,
                "broken" => 0
            )

            output = String(take!(io))
            @test occursin("TestModule", output)
            @test occursin("✗", output)  # Failure icon
            @test occursin("2 failed", output)
            @test occursin("1 errored", output)
        end

        @testset "Plain Format - Test Run End" begin
            # Success case
            io = IOBuffer()
            TestAgent._log_plain(io, "test_run_end",
                "status" => "success",
                "duration" => 1.234
            )
            output = String(take!(io))
            @test occursin("✅", output)
            @test occursin("1.234", output)

            # Failure case
            io = IOBuffer()
            TestAgent._log_plain(io, "test_run_end",
                "status" => "failed",
                "duration" => 2.5
            )
            output = String(take!(io))
            @test occursin("❌", output)
            @test occursin("2.5", output)
        end

        @testset "Plain Format - Errors" begin
            # Test error
            io = IOBuffer()
            TestAgent._log_plain(io, "test_error",
                "error" => "Something went wrong"
            )
            output = String(take!(io))
            @test occursin("⚠️", output)
            @test occursin("Something went wrong", output)

            # Critical error
            io = IOBuffer()
            TestAgent._log_plain(io, "critical_error",
                "type" => "parse_error",
                "action" => "exiting",
                "error" => "Syntax error"
            )
            output = String(take!(io))
            @test occursin("🚨", output)
            @test occursin("parse_error", output)
            @test occursin("exiting", output)
        end

        @testset "Log Event Dispatch" begin
            # Test that _log_event correctly dispatches to format handlers
            io_jsonl = IOBuffer()
            TestAgent._log_event(io_jsonl, JSONL, "test_event", "key" => "value")
            jsonl_output = String(take!(io_jsonl))
            @test occursin("\"event\"", jsonl_output)
            @test occursin("\"key\"", jsonl_output)

            io_plain = IOBuffer()
            TestAgent._log_event(io_plain, Plain, "system", "message" => "Test")
            plain_output = String(take!(io_plain))
            @test occursin("Test", plain_output)
        end
    end

    ###########################################################################
    # ERROR HANDLING TESTS
    ###########################################################################

    @testset "Error Handling" begin
        @testset "Parse Errors Exit Immediately" begin
            io = IOBuffer()
            parse_error = Meta.ParseError("syntax error")

            # Should exit with EXIT_PARSE_ERROR
            @test_throws ProcessFailedException begin
                # Run in subprocess to capture exit
                run(`julia --project=. -e '
                    using TestAgent, Test
                    io = IOBuffer()
                    e = Meta.ParseError("test")
                    TestAgent._handle_test_error(e, io, TestAgent.JSONL)
                '`)
            end
        end

        @testset "Runtime Errors Don't Exit" begin
            io = IOBuffer()
            runtime_error = ErrorException("runtime error")

            # Should log error but NOT exit (no exception thrown)
            TestAgent._handle_test_error(runtime_error, io, JSONL)

            output = String(take!(io))
            @test occursin("test_error", output)
            @test occursin("runtime error", output)

            # Verify it's valid JSON
            parsed = JSON.parse(output)
            @test parsed["event"] == "test_error"
            @test occursin("runtime error", parsed["error"])
        end

        @testset "Error Messages Include Stack Traces" begin
            io = IOBuffer()
            error = ErrorException("test error with context")

            TestAgent._handle_test_error(error, io, JSONL)

            output = String(take!(io))
            parsed = JSON.parse(output)

            # Stack trace should be in error field
            @test haskey(parsed, "error")
            @test occursin("test error with context", parsed["error"])
        end
    end

    ###########################################################################
    # TEST EXECUTION TESTS
    ###########################################################################

    @testset "Test Execution" begin
        @testset "Passing Tests" begin
            io = IOBuffer()
            TestAgent._run_tests_core([PassingTests], io, JSONL)

            output = String(take!(io))
            lines = filter(!isempty, split(output, '\n'))

            # Should have: test_run_start, test_result, test_run_end, system
            @test length(lines) >= 4

            # Parse each line as JSON
            events = [JSON.parse(line) for line in lines if startswith(line, "{")]

            # Find test_result event
            result = findfirst(e -> e["event"] == "test_result", events)
            @test result !== nothing
            @test events[result]["status"] == "success"
            @test events[result]["passed"] == 3
            @test events[result]["failed"] == 0
            @test events[result]["errored"] == 0

            # Find test_run_end event
            run_end = findfirst(e -> e["event"] == "test_run_end", events)
            @test run_end !== nothing
            @test events[run_end]["status"] == "success"
            @test haskey(events[run_end], "duration")
        end

        @testset "Failing Tests" begin
            io = IOBuffer()
            TestAgent._run_tests_core([FailingTests], io, JSONL)

            output = String(take!(io))
            lines = filter(!isempty, split(output, '\n'))
            events = [JSON.parse(line) for line in lines if startswith(line, "{")]

            # Find test_result event
            result = findfirst(e -> e["event"] == "test_result", events)
            @test result !== nothing
            @test events[result]["status"] == "failed"
            @test events[result]["passed"] == 1
            @test events[result]["failed"] == 1

            # Overall run should fail
            run_end = findfirst(e -> e["event"] == "test_run_end", events)
            @test run_end !== nothing
            @test events[run_end]["status"] == "failed"
        end

        @testset "Error Tests" begin
            io = IOBuffer()
            TestAgent._run_tests_core([ErrorTests], io, JSONL)

            output = String(take!(io))
            lines = filter(!isempty, split(output, '\n'))
            events = [JSON.parse(line) for line in lines if startswith(line, "{")]

            # Find test_result event
            result = findfirst(e -> e["event"] == "test_result", events)
            @test result !== nothing
            @test events[result]["status"] == "failed"
            @test events[result]["passed"] == 1
            @test events[result]["errored"] == 1
        end

        @testset "Broken Tests" begin
            io = IOBuffer()
            TestAgent._run_tests_core([BrokenTests], io, JSONL)

            output = String(take!(io))
            lines = filter(!isempty, split(output, '\n'))
            events = [JSON.parse(line) for line in lines if startswith(line, "{")]

            # Find test_result event
            result = findfirst(e -> e["event"] == "test_result", events)
            @test result !== nothing
            @test events[result]["passed"] == 1
            @test events[result]["broken"] == 1
            # Broken tests don't count as failures
            @test events[result]["status"] == "success"
        end

        @testset "Multiple Test Modules" begin
            io = IOBuffer()
            TestAgent._run_tests_core([PassingTests, BrokenTests], io, JSONL)

            output = String(take!(io))
            lines = filter(!isempty, split(output, '\n'))
            events = [JSON.parse(line) for line in lines if startswith(line, "{")]

            # Should have test_result for each module
            results = filter(e -> e["event"] == "test_result", events)
            @test length(results) == 2
        end

        @testset "Duration Measurement" begin
            io = IOBuffer()
            start = time()
            TestAgent._run_tests_core([PassingTests], io, JSONL)
            elapsed = time() - start

            output = String(take!(io))
            lines = filter(!isempty, split(output, '\n'))
            events = [JSON.parse(line) for line in lines if startswith(line, "{")]

            run_end = findfirst(e -> e["event"] == "test_run_end", events)
            @test run_end !== nothing

            duration = events[run_end]["duration"]
            @test duration isa Number
            @test duration > 0
            @test duration <= elapsed + 0.1  # Should be close to actual time
        end

        @testset "Plain vs JSONL Output Suppression" begin
            # JSONL should suppress Test.jl output
            io_jsonl = IOBuffer()
            TestAgent._run_tests_core([PassingTests], io_jsonl, JSONL)
            jsonl_output = String(take!(io_jsonl))

            # Should NOT contain Test.jl's "Test Summary:" output
            @test !occursin("Test Summary:", jsonl_output)

            # Plain should allow Test.jl output
            io_plain = IOBuffer()
            TestAgent._run_tests_core([PassingTests], io_plain, Plain)
            plain_output = String(take!(io_plain))

            # Should contain Test.jl's default output
            @test occursin("Test Summary:", plain_output) || occursin("PassingTests", plain_output)
        end
    end

    ###########################################################################
    # INTEGRATION TESTS
    ###########################################################################

    @testset "Integration Tests" begin
        @testset "File Output" begin
            # Create temp file
            output_file = tempname()

            try
                # Run tests with file output
                io = open(output_file, "w")
                TestAgent._run_tests_core([PassingTests], io, JSONL)
                close(io)

                # Verify file was written
                @test isfile(output_file)
                @test filesize(output_file) > 0

                # Verify content is valid JSONL
                content = read(output_file, String)
                lines = filter(!isempty, split(content, '\n'))

                for line in lines
                    if startswith(line, "{")
                        @test_nowarn JSON.parse(line)
                    end
                end
            finally
                rm(output_file, force=true)
            end
        end

        @testset "Format Switching" begin
            # Test that format parameter correctly switches output
            io_jsonl = IOBuffer()
            TestAgent._run_tests_core([PassingTests], io_jsonl, JSONL)
            jsonl_out = String(take!(io_jsonl))

            io_plain = IOBuffer()
            TestAgent._run_tests_core([PassingTests], io_plain, Plain)
            plain_out = String(take!(io_plain))

            # Outputs should be different
            @test jsonl_out != plain_out

            # JSONL should have JSON format
            @test occursin("\"event\"", jsonl_out)

            # Plain should have Unicode symbols
            @test occursin("🔄", plain_out) || occursin("✓", plain_out)
        end
    end
end
