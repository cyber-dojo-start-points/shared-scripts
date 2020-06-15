#!/bin/bash -Ee

# - - - - - - - - - - - - - - - - - - - - - - -
# Curl'd and run in CircleCI scripts of all repos
# of the cyber-dojo-start-points github organization.
#
# Note: TMP_DIR is off ~ and not /tmp because if we are
# not running on native Linux (eg on Docker-Toolbox on a Mac)
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
show_use_short()
{
  local -r my_name=$(basename ${BASH_SOURCE[0]})
  echo "Use: ${my_name} [GIT_REPO_DIR|-h|--help]"
  echo ''
  echo '  GIT_REPO_DIR defaults to ${PWD}.'
  echo '  GIT_REPO_DIR must hold a git repo.'
  echo '  GIT_REPO_DIR/start_point must exist.'
  echo ''
}

# - - - - - - - - - - - - - - - - - - - - - - -
show_use_long()
{
  show_use_short
  cat <<- EOF
    *) Verifies you can build a start-point image from \${GIT_REPO_DIR}.
       $ cyber-dojo start-point build ... --languages \${GIT_REPO_DIR}

    *) Runs the \${GIT_REPO_DIR}/start_point/ files against the 'image_name'
       specified in \${GIT_REPO_DIR}/start_point/manifest.json
         o) RED   when unmodified
         o) AMBER when '6 * 9' is replaced by '6 * 9sd'
         o) GREEN when '6 * 9' is replaced by '6 * 7'
       If there is no \${GIT_REPO_DIR}/start_point/ file containing '6 * 9',
       looks for the file \${GIT_REPO_DIR}/start_point/options.json. For example, see:
       https://github.com/cyber-dojo-languages/nasm-assert/tree/master/start_point

EOF
}

# - - - - - - - - - - - - - - - - - - - - - - -
exit_zero_if_show_help()
{
  if [ "${1}" == '-h' ] || [ "${1}" == '--help' ]; then
    show_use_long
    exit 0
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
exit_non_zero_unless_git_installed()
{
  if ! hash git 2> /dev/null; then
    stderr 'ERROR: git is not installed'
    exit 42
  fi
}

# - - - - - - - - - - - - - - - - - - - - - - -
exit_non_zero_unless_docker_installed()
{
  if ! hash docker; then
    stderr 'ERROR: docker is not installed'
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
  if [[ -z $(cd ${abs_src_dir} && git status -s) ]]; then
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
    git add .
    git commit -m 'Save'
    echo "Using ${url}"
    GIT_REPO_DIR="${url}"
  fi
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

#- - - - - - - - - - - - - - - - - - - - - - -
image_name()
{
  docker run \
    --rm \
    --volume "${GIT_REPO_DIR}:/data:ro" \
    cyberdojofoundation/image_namer
}

# - - - - - - - - - - - - - - - - - - - - - - -
check_red_amber_green()
{
  echo 'Checking red|amber|green traffic-lights'
  create_docker_network
  # start runner service needed by image_hiker
  start_runner_container
  wait_until_ready "$(runner_container_name)" "${CYBER_DOJO_RUNNER_PORT}"
  # start languages-start-points service needed by image_hiker
  build_lsp_image
  start_lsp_container
  wait_until_ready "$(lsp_container_name)" "${CYBER_DOJO_LANGUAGES_START_POINTS_PORT}"
  # now use image_hiker to check red|amber|green
  assert_traffic_light red
  assert_traffic_light amber
  assert_traffic_light green
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
     --env NO_PROMETHEUS=true \
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
  "$(cyber_dojo)" start-point create "${name}" --languages "${GIT_REPO_DIR}"
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
  local -r max_tries=20
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
  echo "${name} not ready after ${max_tries} tries"
  if [ -f "${READY_FILENAME}" ]; then
    echo "$(cat "${READY_FILENAME}")"
  fi
  docker logs ${name}
  exit 42
}

# - - - - - - - - - - - - - - - - - - - - - - -
ip_address()
{
  if [ -n "${DOCKER_MACHINE_NAME}" ]; then
    docker-machine ip ${DOCKER_MACHINE_NAME}
  else
    echo localhost
  fi
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
# check red->amber->green progression of '6 * 9'
# Works via a volume-mount (and not via a git-clone) so
#   o) uncommitted changes in GIT_REPO_DIR will be seen.
#   o) start_point/options.json can be used if needed.
# - - - - - - - - - - - - - - - - - - - - - - -
assert_traffic_light()
{
  local -r colour="${1}" # red|amber|green
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
      cyberdojofoundation/image_hiker:latest \
      "${colour}"
}

# - - - - - - - - - - - - - - - - - - - - - - -
versioner_env_vars()
{
  docker run --rm cyberdojo/versioner:latest
}

# - - - - - - - - - - - - - - - - - - - - - - -
run_red_amber_green_test()
{
  export $(versioner_env_vars)
  exit_zero_if_show_help "${1}"
  exit_non_zero_unless_git_installed
  exit_non_zero_unless_docker_installed
  exit_non_zero_unless_good_GIT_REPO_DIR "${1}"
  set_git_repo_dir "${1}"
  check_red_amber_green
}

# - - - - - - - - - - - - - - - - - - - - - - -
run_red_amber_green_test "${1}"
