#!/bin/bash -Eeu

# One time script used to tag cyber-dojo-start-points repos
# from cyber-dojo-languages repos' start_point/ dirs.

readonly MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CDSP_DIR="$(cd "${MY_DIR}/.." && pwd)"
readonly CDSP_DIR_LS="$(cd "${CDSP_DIR}" && ls)"

stderr() { >&2 echo "${1}"; }

#- - - - - - - - - - - - - - - - - - - - - - - -
tag_start_point_repo_image_tag()
{
  local -r entry="${1}"               # eg bash-bats
  local -r src_dir="${CDSP_DIR}/${entry}"
  echo "Tag image_name inside ${entry}"
  local stdout

  # Get image_name:latest
  # NB: sed command is because some manifest.json files
  #     contain strings with illegal (in strict JSON) backslashes.
  local -r image_name="$(cat ${src_dir}/start_point/manifest.json \
    | sed 's/\\/X/g' \
    | jq --raw-output .image_name)" # eg cyberdojofoundation/bash_bats
  docker pull "${image_name}:latest"

  # Get its SHA
  local -r sha_env_var="$(docker run -it --rm ${image_name}:latest sh -c 'env | grep SHA=')"
  local -r sha="${sha_env_var:4}"
  local -r tag="${sha:0:7}"

  # Verify image_name with tag exists
  docker pull "${image_name}:${tag}"

  # Update tag inside manifest.json
  if ! stdout="$(docker run \
    --volume ${src_dir}/start_point:/start_point:rw \
    --rm \
    cyberdojofoundation/image_manifest_tagger \
    ${tag} 2>&1)"
  then
    stderr "ERROR: failed to tag image_name inside .../start_point/manifest.json"
    stderr "${output}"
    exit 42
  fi

  # Run the tests
  cd "${src_dir}"
  ./run_tests.sh

  # Commit it
  git add .
  git commit -m "Add tag to image_name in manifest.json"
  git push
}

#- - - - - - - - - - - - - - - - - - - - - - - -

TOGGLE="off"
for entry in ${CDSP_DIR_LS}
do
  case "${entry}" in
  python-unittest ) TOGGLE="on" ;;
  esac

  if [ -d "${CDSP_DIR}/${entry}/start_point" ]; then
    if [ "${TOGGLE}" == "on" ]; then
      tag_start_point_repo_image_tag "${entry}"
    else
      echo "Skipping ${entry} as it has been coverted already."
    fi
  fi

done
