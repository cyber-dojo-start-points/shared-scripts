#!/usr/bin/env bash

# Runs every case in a start-point's test/fixtures/ dir.
#
# One dir per case, named for the outcome it should reach, holding the source
# and test files a learner would have. cyber-dojo.sh is never one of them: a
# learner does not edit it, and it is the thing several of these cases put
# under test. Each case is handed to image_hiker, which sends its files to
# the runner with the manifest, so the outcome is reached exactly as it is
# for a learner, timed_out and faulty included.
#
# A case asserts more than its outcome by holding an expected.json, which is
# data rather than code so that a start-point holds no test code at all:
#
#   {
#     "matches":          [ "^ok 1 " ],
#     "match_counts":     { "^1\\.\\.3$": 1 },
#     "max_output_lines": 10,
#     "truncated":        true
#   }
#
# red_amber_green_test.sh starts the services these need and exports the
# env-vars below, so this runs from there rather than on its own.

readonly repo_dir="${CYBER_DOJO_START_POINT_REPO_DIR}"
readonly network="${CYBER_DOJO_TRAFFIC_LIGHT_NETWORK}"
readonly image_hiker="${CYBER_DOJO_IMAGE_HIKER}"
readonly shared_dir="${CYBER_DOJO_SHARED_DIR}"
readonly fixtures_dir="${repo_dir}/test/fixtures"

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# running one case

# Runs the named fixture and records image_hiker's JSON, its stderr, and its
# exit status.
#
# The volume-mount is what lets image_hiker read the fixture's files. It is
# read-only, so a case can never write to its own fixture, and it is mounted
# at the path it already has, so the path needs no translating.
run_fixture()
{
  local -r name="${1}"
  docker run \
    --env NO_PROMETHEUS=true \
    --env SRC_DIR="${repo_dir}" \
    --init \
    --network "${network}" \
    --read-only \
    --restart no \
    --rm \
    --tmpfs /tmp \
    --user nobody \
    --volume "${repo_dir}:${repo_dir}:ro" \
      "${image_hiker}" \
        --fixture "${fixtures_dir}/${name}" > "${stdoutF}" 2> "${stderrF}"
  echo $? > "${statusF}"
}

# Echoes one value from image_hiker's JSON.
hiked()
{
  jq --raw-output "${1}" "${stdoutF}"
}

# Echoes everything cyber-dojo.sh printed, on stdout and on stderr both,
# which is what the rag-lambda reads.
hiked_output()
{
  hiked '.["cyber-dojo.sh"].stdout.content + .["cyber-dojo.sh"].stderr.content | join("")'
}

# Echoes how many lines of that output matched an extended regex.
#
# The pattern is given with --regexp= because a case may well want to match a
# compiler command line, and a pattern starting with a dash would otherwise be
# read as options rather than as the thing to look for.
#
# It is an extended regex in the POSIX sense, which has no escape for a tab.
# What \t means there is left to the implementation: BSD grep reads it as a
# tab and GNU grep as the letter t, so a pattern using it passes on a mac and
# fails in CI. Write [[:space:]] for an indented line.
output_match_count()
{
  hiked_output | grep --count --extended-regexp --regexp="${1}"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# assertions

# Fails unless the case reached the outcome its dir name declares.
#
# image_hiker reads the name and compares, so the convention lives in one
# place rather than being spelled out again here.
assert_fixture_passed()
{
  local -r result="$(hiked '.summary.result')"
  if [ "${result}" != 'PASSED' ]; then
    dump_sss
    fail "expected PASSED, got $(hiked '.summary.result'), reaching $(hiked '.summary.colour')"
  fi
}

# Applies whatever the case's expected.json asks for. A case without one
# asserts its outcome and nothing else.
assert_expectations()
{
  local -r file="${fixtures_dir}/${1}/expected.json"
  if [ ! -f "${file}" ]; then
    return 0
  fi
  assert_matches "${file}"
  assert_match_counts "${file}"
  assert_max_output_lines "${file}"
  assert_truncated "${file}"
}

# Fails unless every regex in "matches" matches at least one line.
#
# The loop reads from a process substitution rather than a pipe because a
# pipe would run it in a subshell, where a failure shunit2 recorded would be
# thrown away with that subshell and the case would pass.
assert_matches()
{
  local regex
  while read -r regex; do
    if [ "$(output_match_count "${regex}")" == '0' ]; then
      dump_sss
      fail "expected the output to match ${regex}"
    fi
  done < <(jq --raw-output '.matches // [] | .[]' "${1}")
}

# Fails unless every regex in "match_counts" matches exactly its number of
# lines. A count is what distinguishes a test file that really ran from one
# that was gathered and skipped, and one summary line from several.
assert_match_counts()
{
  local count regex
  while IFS=$'\t' read -r count regex; do
    assertEquals "lines matching ${regex}:$(dump_sss)" \
      "${count}" "$(output_match_count "${regex}")"
  done < <(jq --raw-output '.match_counts // {} | to_entries[] | "\(.value)\t\(.key)"' "${1}")
}

# Fails if the output runs longer than "max_output_lines".
#
# A learner who mistypes a name wants the file and the line it is on. A page
# of the framework's own stack frames scrolls that away, and every frame in
# it is inside machinery they did not write and cannot fix.
assert_max_output_lines()
{
  local -r expected="$(jq --raw-output '.max_output_lines // empty' "${1}")"
  if [ -z "${expected}" ]; then
    return 0
  fi
  local -r actual="$(hiked '.["cyber-dojo.sh"].stdout.content + .["cyber-dojo.sh"].stderr.content | length')"
  if [ "${actual}" -gt "${expected}" ]; then
    dump_sss
    fail "expected at most ${expected} lines of output, got ${actual}"
  fi
}

# Fails unless the runner cut the output short, or left it whole, as
# "truncated" says. It keeps the first 50K of each stream and drops the rest,
# so a learner printing inside a loop loses the summary line that came after
# it.
#
# Either stream counts. Which one carries the decisive line belongs to the
# language rather than to the case: a C assert writes to stderr and a TAP
# summary to stdout, and the case is the same one either way.
assert_truncated()
{
  # A case saying nothing about truncation skips the check. Asking whether the
  # key is there is what tells that apart from a case saying false, which is a
  # claim worth making: it says the summary the colour rests on survived.
  if [ "$(jq 'has("truncated")' "${1}")" == 'false' ]; then
    return 0
  fi
  local -r expected="$(jq --raw-output '.truncated' "${1}")"
  local -r actual="$(hiked '.["cyber-dojo.sh"].stdout.truncated or .["cyber-dojo.sh"].stderr.truncated')"
  assertEquals "output-truncated:$(dump_sss)" "${expected}" "${actual}"
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# the suite

# Runs one case: its outcome, then whatever else it asks for.
check_fixture()
{
  local -r name="${1}"
  run_fixture "${name}"
  assert_fixture_passed
  assert_expectations "${name}"
}

# Makes one shunit2 test per fixture dir.
#
# shunit2 finds tests by reading the script file, which cannot see functions
# that do not exist until it runs, so the tests are named here instead. A
# test per case is what makes a failure name the case that failed.
suite()
{
  local dir name
  for dir in "${fixtures_dir}"/*; do
    if [ ! -d "${dir}" ]; then
      continue
    fi
    name="$(basename "${dir}")"
    eval "test_${name}() { check_fixture ${name}; }"
    suite_addTest "test_${name}"
  done
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# shunit2 plumbing

oneTimeSetUp()
{
  outputDir="${SHUNIT_TMPDIR}/output"
  mkdir "${outputDir}"
  stdoutF="${outputDir}/stdout"
  stderrF="${outputDir}/stderr"
  statusF="${outputDir}/status"
}

# Prints everything image_hiker said, which names the fixture, what
# cyber-dojo.sh wrote on each stream, whether that output was truncated, the
# exit status, and the outcome reached.
dump_sss()
{
  echo
  echo '<stdout>'
  cat "${stdoutF}"
  echo '</stdout>'
  echo
  echo '<stderr>'
  cat "${stderrF}"
  echo '</stderr>'
  echo
  echo '<status>'
  cat "${statusF}"
  echo '</status>'
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

if [ -z "$(ls -A "${fixtures_dir}" 2> /dev/null)" ]; then
  >&2 echo "ERROR: ${fixtures_dir} holds no cases"
  exit 42
fi

echo "::$(basename "${0}")"
. "${shared_dir}/shunit2"
