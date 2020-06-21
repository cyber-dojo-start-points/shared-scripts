#!/bin/bash -Eeu

readonly MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CDL_DIR="$(cd "${MY_DIR}/../../cyber-dojo-languages" && pwd)"
readonly CDL_DIR_LS="$(cd "${CDL_DIR}" && ls)"
for entry in ${CDL_DIR_LS}
do
  if [ "${entry}" == "csharp-dotnet" ]; then
    continue
  fi
  if [ "${entry}" == "csharp-dotnet-test" ]; then
    continue
  fi

  if [ -d "${CDL_DIR}/${entry}" ]; then
    repo_name=$(basename $(cd "${CDL_DIR}/${entry}" && git remote get-url origin) .git)
    if [ "${entry}" != "${repo_name}" ]; then
      echo Different...
      echo " dir:${entry}:"
      echo "repo:${repo_name}:"
    fi
  fi
done
