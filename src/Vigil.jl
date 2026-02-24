# Copyright (c) 2026 Nablarise
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

"""
    Vigil

A Julia package for managing test infrastructure with file watching and dual-format logging.

Provides:
- `watch_and_run`: Main test runner with Revise.jl integration
- Exit code constants for process management

# Exit Codes
- `EXIT_SUCCESS` (0): Normal exit
- `EXIT_PARSE_ERROR` (1): Parse/syntax error - fatal

# Example
```julia
using Vigil

# Run watch loop with file output (JSONL)
watch_and_run([MyTestModule], [MyPackage]; output_file="test/output.log", format=JSONL)

# Or interactive mode (plain text)
watch_and_run([MyTestModule], [MyPackage]; format=Plain)
```
"""
module Vigil

using Revise, Test, JSON, Dates

# Exit code constants - replace magic numbers throughout the codebase
const EXIT_SUCCESS = 0        # Normal, successful exit
const EXIT_PARSE_ERROR = 1    # Parse/syntax error - fatal

# Log format enumeration
@enum LogFormat begin
    Plain = 1   # Human-readable format with Unicode symbols
    JSONL = 2   # JSON Lines format for AI agents
end

# Include submodules
include("runner.jl")

# Export public API
export watch_and_run
export EXIT_SUCCESS, EXIT_PARSE_ERROR
export LogFormat, Plain, JSONL

end # module Vigil
