#!/bin/bash -Ee

# - - - - - - - - - - - - - - - - - - - - - - -
# Curl'd and run in CI scripts of all repos
# of the cyber-dojo-start-points GitHub organization.
#
# Note: TMP_DIR is off ~ and not /tmp because if we are
# not running on native Linux (eg on a Mac)
# then we need the TMP_DIR in a location which is visible
# (as a default volume-mount) inside the VM being used.
# - - - - - - - - - - - - - - - - - - - - - - -

readonly TMP_DIR=$(mktemp -d ~/tmp.cyber-dojo-start-point-test.XXXXXX)
remove_tmp_dir() { rm -rf "${TMP_DIR}" > /dev/null; }

# - - - - - - - - - - - - - - - - - - - - - - -
trap_handler()
{
  remove_tmp_dir
  remove_lsp_image
  remove_runner_container
  remove_lsp_container
  remove_docker_network
}
trap trap_handler EXIT

# - - - - - - - - - - - - - - - - - - - - - - -
# cyberdojo/start-points-base is published for linux/amd64 only, and a build
# resolving it as a FROM base fails outright on an arm64 host rather than
# falling back the way 'docker run' does. So the build has to be told which
# platform to use. That build happens inside the curl'd commander scripts,
# out of reach of a --platform flag, hence an env-var.
#
# It is set on that one command rather than exported for the whole run because
# an exported value would also reach the multi-arch language image named in
# manifest.json, and the red|amber|green durations collected by the
# cyber-dojo/languages-start-points repo are only meaningful when that image
# runs natively.
# - - - - - - - - - - - - - - - - - - - - - - -

# Echoes the docker platform architecture of the host cpu, eg arm64 on
# Apple Silicon. Pair it with linux/ to make a --platform argument.
host_docker_arch()
{
  case "$(uname -m)" in
    arm64|aarch64) echo arm64 ;;
    *)             echo amd64 ;;
  esac
}

# True when the host cpu is arm64, eg Apple Silicon.
host_is_arm64()
{
  [ "$(host_docker_arch)" = 'arm64' ]
}

# Echoes an env-var setting that builds the amd64-only base image, or nothing
# on a host that resolves it natively. Use unquoted after 'env' so it vanishes
# when empty.
amd64_platform_env()
{
  if host_is_arm64; then
    echo 'DOCKER_DEFAULT_PLATFORM=linux/amd64'
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - -
show_use_short()
{
  local -r my_name=$(basename ${BASH_SOURCE[0]})
  echo "Use: ${my_name} [GIT_REPO_DIR] [--lights-only|--matrix-only] [-h|--help]"
  echo ''
  echo '  GIT_REPO_DIR defaults to ${PWD}.'
  echo '  GIT_REPO_DIR must hold a git repo.'
  echo '  GIT_REPO_DIR/start_point/ must exist.'
  echo ''
  echo '  --lights-only  check the three traffic-lights and stop.'
  echo '  --matrix-only  run only GIT_REPO_DIR/test/fixtures/, the cases.'
  echo '                 Both groups run when neither flag is given.'
  echo ''
}

# - - - - - - - - - - - - - - - - - - - - - - -
show_use_long()
{
  show_use_short
  cat <<- EOF
  *) Verifies you can build a start-point image from \${GIT_REPO_DIR}.
      $ cyber-dojo start-point create ... --languages \${GIT_REPO_DIR}

  *) Checks the \${GIT_REPO_DIR}/start_point/ files run against the 'image_name'
      specified in \${GIT_REPO_DIR}/start_point/manifest.json are:
        o) RED   when unmodified
        o) AMBER when '6 * 9' is replaced by '6 * 9sd'
        o) GREEN when '6 * 9' is replaced by '6 * 7'
      If there is no \${GIT_REPO_DIR}/start_point/ file containing '6 * 9',
      looks for the file \${GIT_REPO_DIR}/start_point/options.json. For example, see:
      https://github.com/cyber-dojo-languages/nasm-assert/tree/main/start_point

EOF
}

# - - - - - - - - - - - - - - - - - - - - - - -
exit_zero_if_show_help()
{
  local arg
  for arg in "$@"; do
    if [ "${arg}" == '-h' ] || [ "${arg}" == '--help' ]; then
      show_use_long
      exit 0
    fi
  done
}

# - - - - - - - - - - - - - - - - - - - - - - -
# Reads the command line into SRC_DIR and the two switches saying which
# groups of checks to run. Both groups run unless a flag says otherwise.
set_options()
{
  SRC_DIR=''
  CHECK_TRAFFIC_LIGHTS=true
  RUN_FIXTURE_TESTS=true
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --lights-only) RUN_FIXTURE_TESTS=false ;;
      --matrix-only) CHECK_TRAFFIC_LIGHTS=false ;;
      -*)
        show_use_short
        stderr "ERROR: unknown option ${arg}"
        exit 42
        ;;
      *) SRC_DIR="${arg}" ;;
    esac
  done
  if [ "${CHECK_TRAFFIC_LIGHTS}" == 'false' ] && [ "${RUN_FIXTURE_TESTS}" == 'false' ]; then
    show_use_short
    stderr 'ERROR: --lights-only and --matrix-only cannot both be given'
    exit 42
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - -
exit_non_zero_unless_installed()
{
  for name in "$@"; do
    if ! installed "${name}"; then
      stderr "ERROR: ${name} is not installed"
      exit 42
    fi
  done
}

# - - - - - - - - - - - - - - - - - - - - - - -
installed()
{
  local -r name="${1}"
  if hash "${name}" 2> /dev/null ; then
    true
  else
    false
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - -
exit_non_zero_unless_good_GIT_REPO_DIR()
{
  local -r git_repo_dir="${1:-${PWD}}"
  if [ ! -d "${git_repo_dir}" ]; then
    show_use_short
    stderr "ERROR: ${git_repo_dir} does not exist."
    exit 42
  fi
  if [ ! -d "${git_repo_dir}/start_point" ]; then
    show_use_short
    stderr "ERROR: ${git_repo_dir}/start_point/ does not exist."
    exit 42
  fi
  if [ ! $(cd ${git_repo_dir} && git rev-parse HEAD 2> /dev/null) ]; then
    show_use_short
    stderr "ERROR: ${git_repo_dir} is not in a git repo."
    exit 42
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - -
set_git_repo_dir()
{
  local -r src_dir="${1:-${PWD}}"
  local -r abs_src_dir="$(cd "${src_dir}" && pwd)"
  echo "Checking ${abs_src_dir}"
  echo 'Looking for uncommitted changes'
  if [[ -z $(cd ${abs_src_dir} && git status --short) ]]; then
    echo 'Found none'
    echo "Using ${abs_src_dir}"
    GIT_REPO_DIR="${abs_src_dir}"
  else
    echo 'Found some'
    local -r url="${TMP_DIR}/$(basename ${abs_src_dir})"
    echo "So copying it to ${url}"
    cp -r "${abs_src_dir}" "${TMP_DIR}"
    echo "Committing the changes in ${url}"
    cd ${url}
    git config user.email 'cyber-dojo-machine-user@cyber-dojo.org'
    git config user.name 'CyberDojoMachineUser'
    git config commit.gpgsign false 
    git add .
    git commit -m 'Save'
    echo "Using ${url}"
    GIT_REPO_DIR="${url}"
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - -
set_git_repo_tag()
{
  local -r sha="$(cd ${GIT_REPO_DIR} && git rev-parse HEAD)"
  GIT_REPO_TAG="${sha:0:7}"
}

# - - - - - - - - - - - - - - - - - - - - - - -
stderr()
{
  >&2 echo "${1}"
}

# - - - - - - - - - - - - - - - - - - - - - - -
cyber_dojo()
{
  local -r name=cyber-dojo
  if [ -x "$(command -v ${name})" ]; then
    stderr "Found executable ${name} on the PATH"
    echo "${name}"
  else
    local -r url="https://raw.githubusercontent.com/cyber-dojo/commander/master/${name}"
    stderr "Did not find executable ${name} on the PATH"
    stderr "Curling it from ${url}"
    curl --fail --output "${TMP_DIR}/${name}" --silent "${url}"
    chmod 700 "${TMP_DIR}/${name}"
    echo "${TMP_DIR}/${name}"
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - -
# Starts the services a kata's files are run through. The traffic-lights and
# the start-point's own tests both go through them, so they start before
# either and come down in the trap afterwards.
start_services()
{
  local -r image_name="$(cat ${GIT_REPO_DIR}/start_point/manifest.json | jq --raw-output .image_name)"

  # The architecture of the local copy is what decides whether to pull.
  # 'docker run' accepts a cached image of any architecture and silently
  # emulates it, so a wrong-arch copy would inflate every duration, and a
  # pull naming the host platform replaces it. A copy already matching the
  # host is run as it stands, which keeps a locally built image testable
  # here and spares every run a trip to the registry.
  local -r arch="$(host_docker_arch)"
  local -r local_arch="$(docker image inspect --format '{{.Architecture}}' "${image_name}" 2> /dev/null)"
  if [ "${local_arch}" == "${arch}" ]; then
    echo "Found ${image_name} for ${arch} locally so not pulling"
  else
    echo "Pulling manifest.json's image_name for linux/${arch}"
    docker pull --platform "linux/${arch}" "${image_name}"
  fi

  create_docker_network
  # start runner service needed by image_hiker
  start_runner_container
  wait_until_ready "$(runner_container_name)" "${CYBER_DOJO_RUNNER_PORT}"
  # start languages-start-points service needed by image_hiker
  build_lsp_image
  start_lsp_container
  wait_until_ready "$(lsp_container_name)" "${CYBER_DOJO_LANGUAGES_START_POINTS_PORT}"
}

# - - - - - - - - - - - - - - - - - - - - - - -
# Uses image_hiker to check the three traffic-lights, and prints how long
# each took.
check_traffic_lights()
{
  echo 'Checking red|amber|green traffic-lights'
  # A duration depends on how many runs preceded it. Running one colour six
  # times against a single runner gave 0.83 0.66 0.59 0.58 0.61 0.62 seconds:
  # the first costs about 0.23s extra and the second about 0.06s, and from the
  # third onwards it is flat. Two untimed runs absorb that, so the three timed
  # below sit on the flat part and measure the language rather than its place
  # in the order. Their durations are thrown away, and the prefix is overridden
  # in a subshell so the run file they write cannot be read as a timed one.
  echo 'Warming up before timing the traffic-lights'
  local _
  for _ in 1 2; do
    ( export CYBER_DOJO_RAG_RUN_FILE_PREFIX=/tmp/warmup_light
      assert_traffic_light green ) > /dev/null 2>&1 || true
  done
  rm -f /tmp/warmup_light.green.json

  # Every light runs even when an earlier one fails, so the summary below shows
  # the whole picture. The exit status at the end is what reports a failure.
  assert_traffic_light red   | tee /tmp/light.red
  local -r red_status="${PIPESTATUS[0]}"
  assert_traffic_light amber | tee /tmp/light.amber
  local -r amber_status="${PIPESTATUS[0]}"
  assert_traffic_light green | tee /tmp/light.green
  local -r green_status="${PIPESTATUS[0]}"

  echo -e "light\treached\tresult\tduration"
  print_traffic_light_summary red
  print_traffic_light_summary amber
  print_traffic_light_summary green

  if [ "${red_status}" != '0' ] || [ "${amber_status}" != '0' ] || [ "${green_status}" != '0' ]; then
    stderr "ERROR: red|amber|green statuses were ${red_status}|${amber_status}|${green_status}"
    exit 42
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - -
# summary.colour is the colour the run reached, which is not necessarily the
# colour asked for, so both are printed.
print_traffic_light_summary()
{
  local -r colour="${1}" # red|amber|green
  local -r filename="/tmp/light.${colour}"
  local -r reached="$(jq --raw-output '.summary.colour'    "${filename}")"
  local -r result="$(jq --raw-output '.summary.result'     "${filename}")"
  local -r duration="$(jq --raw-output '.summary.duration' "${filename}")"
  echo -e "${colour}\t${reached}\t${result}\t${duration}"
}

# - - - - - - - - - - - - - - - - - - - - - - -
# network to host containers
# - - - - - - - - - - - - - - - - - - - - - - -
docker_network_name()
{
  echo traffic-light
}

create_docker_network()
{
  echo "Creating network $(docker_network_name)"
  local -r msg=$(docker network create $(docker_network_name))
}

remove_docker_network()
{
  docker network remove $(docker_network_name) > /dev/null 2>&1 || true
}

# - - - - - - - - - - - - - - - - - - - - - - -
# runner service to pass starting files to
# - - - - - - - - - - - - - - - - - - - - - - -
runner_container_name()
{
  echo traffic-light-runner
}

start_runner_container()
{
  local -r image="${CYBER_DOJO_RUNNER_IMAGE}:${CYBER_DOJO_RUNNER_TAG}"
  local -r port="${CYBER_DOJO_RUNNER_PORT}"
  echo 'Creating runner service'
  local -r cid=$(docker run \
     --detach \
     --env CYBER_DOJO_RUNNER_PORT=4597 \
     --init \
     --name $(runner_container_name) \
     --network $(docker_network_name) \
     --network-alias runner \
     --publish "${port}:${port}" \
     --read-only \
     --restart no \
     --tmpfs /tmp \
     --user root \
     --volume /var/run/docker.sock:/var/run/docker.sock \
       "${image}")
}

remove_runner_container()
{
  docker container rm --force $(runner_container_name) > /dev/null 2>&1 || true
}

# - - - - - - - - - - - - - - - - - - - - - - -
# language-start-points service to serve starting files
# - - - - - - - - - - - - - - - - - - - - - - -
lsp_image_name()
{
  echo traffic-light-start-points
}

build_lsp_image()
{
  local -r name=$(lsp_image_name)
  echo "Building ${name}"
  env $(amd64_platform_env) \
    "$(cyber_dojo)" start-point create "${name}" --languages "${GIT_REPO_TAG}@${GIT_REPO_DIR}"
}

remove_lsp_image()
{
  docker image remove --force $(lsp_image_name) > /dev/null 2>&1 || true
}

lsp_container_name()
{
  echo traffic-light-lsp
}

start_lsp_container()
{
  local -r port="${CYBER_DOJO_LANGUAGES_START_POINTS_PORT}"
  echo 'Creating languages-start-points service'
  local -r cid=$(docker run \
     --detach \
     --env NO_PROMETHEUS=true \
     --init \
     --name $(lsp_container_name) \
     --network $(docker_network_name) \
     --network-alias languages-start-point \
     --publish "${port}:${port}" \
     --read-only \
     --restart no \
     --tmpfs /tmp \
     --user root \
       "$(lsp_image_name)")
}

remove_lsp_container()
{
  docker container rm --force $(lsp_container_name) > /dev/null 2>&1 || true
}

# - - - - - - - - - - - - - - - - - - - - - - -
wait_until_ready()
{
  local -r name="${1}"
  local -r port="${2}"
  # Overridable from outside for callers that drive many start-points in a row,
  # where a cold start on a busy machine takes longer than usual.
  local -r max_tries="${CYBER_DOJO_START_POINT_READY_TRIES:-20}"
  printf "Waiting until ${name} is ready"
  for _ in $(seq ${max_tries})
  do
    if ready $(ip_address) ${port} ; then
      printf '.OK\n'
      return
    else
      printf .
      sleep 0.2
    fi
  done
  printf 'FAIL\n'
  echo "${name} not ready after ${max_tries} tries at 0.2s intervals"
  if [ -f "$(ready_filename)" ]; then
    echo "$(cat "$(ready_filename)")"
  fi
  docker logs ${name}
  exit 42
}

# - - - - - - - - - - - - - - - - - - - - - - -
ip_address()
{
  echo localhost
}

# - - - - - - - - - - - - - - - - - - - - - - -
ready()
{
  local -r ip_address="${1}"
  local -r port="${2}"
  local -r path=ready?
  rm -f "$(ready_filename)"
  local -r curl_cmd="curl \
    --output $(ready_filename) \
    --silent \
    --fail \
    --data {} \
    -X GET http://$(ip_address):${port}/${path}"
  if ${curl_cmd} && [ "$(cat "$(ready_filename)")" = '{"ready?":true}' ]; then
    true
  else
    false
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - -
ready_filename()
{
  echo /tmp/curl-ready-output
}

# - - - - - - - - - - - - - - - - - - - - - - -
# Echoes the image that runs a kata's files through the runner and reports
# the colour they reached.
image_hiker()
{
  echo ghcr.io/cyber-dojo-tools/image_hiker:latest
}

# - - - - - - - - - - - - - - - - - - - - - - -
# Echoes a dir holding this script's companions, fetching them when this
# script was itself curl'd rather than run from a clone. They sit beside it
# in the repo, so a clone needs no network and a curl takes the same versions
# from the same branch.
shared_dir()
{
  local -r my_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
  if [ -f "${my_dir}/fixtures_test.sh" ] && [ -f "${my_dir}/shunit2" ]; then
    echo "${my_dir}"
  else
    curl_shared fixtures_test.sh
    curl_shared shunit2
    echo "${TMP_DIR}"
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - -
curl_shared()
{
  local -r name="${1}"
  local -r github=raw.githubusercontent.com
  local -r org=cyber-dojo-start-points
  local -r repo=shared-scripts
  local -r branch=main
  local -r url="https://${github}/${org}/${repo}/${branch}/${name}"
  stderr "Curling ${name} from ${url}"
  curl --fail --output "${TMP_DIR}/${name}" --silent "${url}"
  chmod 700 "${TMP_DIR}/${name}"
}

# - - - - - - - - - - - - - - - - - - - - - - -
# A start-point can hold cases of its own, one dir per case under
# test/fixtures/. They cover the cases the three lights cannot express: a
# second test file, a file the learner has not finished writing, a test that
# errors rather than fails, a kata that hangs and never reaches a colour at
# all. Most start-points have no such dir, and that is not a failure, so
# their absence is reported and passed over.
#
# A case holds source and test files only. Everything that runs one lives
# here, so a better assertion is a better assertion for every start-point at
# once rather than in 87 copies.
#
# They run here, after the three lights and before the trap takes the
# services down, because each case is run through those same services.
run_fixture_tests()
{
  if [ ! -d "${GIT_REPO_DIR}/test/fixtures" ]; then
    echo 'Found no test/fixtures/ so there are no cases to run'
    return 0
  fi
  echo 'Running the start-point cases'
  export CYBER_DOJO_START_POINT_REPO_DIR="${GIT_REPO_DIR}"
  export CYBER_DOJO_TRAFFIC_LIGHT_NETWORK="$(docker_network_name)"
  export CYBER_DOJO_IMAGE_HIKER="$(image_hiker)"
  export CYBER_DOJO_SHARED_DIR="$(shared_dir)"
  bash "${CYBER_DOJO_SHARED_DIR}/fixtures_test.sh"
}

# - - - - - - - - - - - - - - - - - - - - - - -
# check red->amber->green progression of '6 * 9'
# Volume-mount is for start_point/options.json
# - - - - - - - - - - - - - - - - - - - - - - -
assert_traffic_light()
{
  local -r colour="${1}" # red|amber|green

  # Save JSON output to a file if requests. This is used by
  # the cyber-dojo/languages-start-points repo to collect the
  # durations of all start-points.
  
  local -r default_filebase="/tmp/assert_traffic_light"
  local -r filename="${CYBER_DOJO_RAG_RUN_FILE_PREFIX:-${default_filebase}}"  

  docker run \
    --env NO_PROMETHEUS=true \
    --env SRC_DIR=${GIT_REPO_DIR} \
    --init \
    --name traffic-light \
    --network $(docker_network_name) \
    --read-only \
    --restart no \
    --rm \
    --tmpfs /tmp \
    --user nobody \
    --volume ${GIT_REPO_DIR}:${GIT_REPO_DIR}:ro \
      "$(image_hiker)" \
      "${colour}" | tee "${filename}.${colour}.json"
  # tee exits zero even when image_hiker exited non-zero, so the status has to
  # come from PIPESTATUS or a failed light would look like a pass.
  return "${PIPESTATUS[0]}"
}

# - - - - - - - - - - - - - - - - - - - - - - -
versioner_env_vars()
{
  docker run --rm cyberdojo/versioner:latest
}

# - - - - - - - - - - - - - - - - - - - - - - -
red_amber_green_test()
{
  exit_zero_if_show_help "$@"
  set_options "$@"
  exit_non_zero_unless_installed docker git jq
  export $(versioner_env_vars)
  exit_non_zero_unless_good_GIT_REPO_DIR "${SRC_DIR}"
  set_git_repo_dir "${SRC_DIR}"
  set_git_repo_tag
  start_services
  if [ "${CHECK_TRAFFIC_LIGHTS}" == 'true' ]; then
    check_traffic_lights
  fi
  if [ "${RUN_FIXTURE_TESTS}" == 'true' ]; then
    run_fixture_tests
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - -
red_amber_green_test "$@"
