# Tests must run in a single process

## The setup

A start-point's `manifest.json` names a `rag_lambda` (eg `red_amber_green.rb`).
That lambda is a pure function of text:

    lamb.call(stdout, stderr, status) -> :red | :amber | :green

It never runs the tests. It only inspects the combined stdout/stderr that
`cyber-dojo.sh` produced, and parses that text to pick a colour. So the
classification is only ever as good as the structure of that text, and that
structure is decided entirely by how `cyber-dojo.sh` invokes the test runner.

## The two ways cyber-dojo.sh can run N test files

Single process (eg one `ruby -Itest test/*_test.rb`, one rspec run): the
framework loads all files into one process, aggregates internally, and emits one
summary line that already reflects the worst case across every file
(`10 tests, 1 failure`). The lambda sees one coherent, authoritative summary and
classifies correctly. The colour precedence (amber beats red beats green) falls
out for free: any file with a load/syntax error aborts the whole run with
non-zero status plus an error on stderr (amber); any failing assertion makes the
single summary report a failure (red); otherwise green.

Multiple processes (a loop like `for f in test/*; do ruby "$f"; done`): each
file is its own process with its own summary, so stdout carries N summary lines:

    3 tests, 0 failures   # file A -> green
    2 tests, 1 failure    # file B -> red

A lambda written for single-summary output then misclassifies:

- First-line-only logic reads `3 tests, 0 failures` and returns green for a run
  that actually contained a failure (should be red).
- A broken file (syntax/load error) emits no summary line at all; it dies
  straight to stderr. A lambda that aggregates only the summary lines it can see
  has no line to read for that file and silently drops the amber. Aggregating
  summary lines is necessary but not sufficient; the lambda must also detect "a
  file produced no summary" from stderr/status.

## Why this is easy to miss

The obvious way to test a lambda is to run a single test file and check the
colour. One test file produces exactly one summary line, so a lambda that only
ever looks at the first summary line passes every single-file check. The bug
only surfaces with a kata that has several test files, run as several processes,
which is the case the single-file checks never exercise.

## Conclusion

The lambda's correctness silently depends on an invariant `cyber-dojo.sh` must
uphold: run all the tests in a single process so there is exactly one
authoritative summary. When `cyber-dojo.sh` runs each test file in its own
process instead, stdout gains one summary line per file, and a lambda written
for a single summary picks the wrong colour.

The fix is twofold: make `cyber-dojo.sh` run tests as a single process (so the
runner does the aggregation), and/or harden the lambda to aggregate across
multiple summaries and infer amber from a missing-summary-on-stderr rather than
trusting the first line.
