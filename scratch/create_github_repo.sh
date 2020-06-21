#!/bin/bash -Eeu

readonly ACCESS_TOKEN="${1}"  # eg 38c0......long....
readonly NEW_REPO_NAME="${2}" # eg bash-bats
readonly DISPLAY_NAME="${3}"  # eg "Bash, bats"
readonly HOME_PAGE="https://cyber-dojo.org"

curl -H \
  "Authorization: token ${ACCESS_TOKEN}" \
  --data "{\"name\":\"${NEW_REPO_NAME}\",\"description\":\"start-point for ${DISPLAY_NAME}\",\"homepage\":\"${HOME_PAGE}\"}" \
  https://api.github.com/orgs/cyber-dojo-start-points/repos
