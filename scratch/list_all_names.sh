#!/bin/bash -Eeu

# One time script used to list cyber-dojo-start-points repos

readonly MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CDSP_DIR="$(cd "${MY_DIR}/.." && pwd)"
readonly CDSP_DIR_LS="$(cd "${CDSP_DIR}" && ls)"

stderr() { >&2 echo "${1}"; }

for entry in ${CDSP_DIR_LS}
do
  if [ -d "${CDSP_DIR}/${entry}/start_point" ]; then
    echo "${entry}"
  fi

done
