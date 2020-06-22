#!/bin/bash -Eeu

# One time script used to create cyber-dojo-start-points repos
# from cyber-dojo-languages repos' start_point/ dirs.

readonly MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CDL_DIR="$(cd "${MY_DIR}/../../cyber-dojo-languages" && pwd)"
readonly CDSP_DIR="$(cd "${MY_DIR}/../../cyber-dojo-start-points" && pwd)"
readonly CDL_DIR_LS="$(cd "${CDL_DIR}" && ls)"

#- - - - - - - - - - - - - - - - - - - - - - - -
one_time_repo_name_check()
{
  local -r entry="${1}"
  if [ -d "${CDL_DIR}/${entry}" ]; then
    repo_name=$(basename $(cd "${CDL_DIR}/${entry}" && git remote get-url origin) .git)
    if [ "${entry}" != "${repo_name}" ]; then
      echo Different...
      echo " dir:${entry}:"
      echo "repo:${repo_name}:"
      exit 42
    fi
  fi
}

#- - - - - - - - - - - - - - - - - - - - - - - -
one_time_image_tag_check()
{
  local -r entry="${1}"
  if [ -d "${CDL_DIR}/${entry}/start_point" ]; then
    # See if any repo has image_name with a tag
    echo "Checking ${entry}'s manifest.json image_name for a tag"
    if cat "${CDL_DIR}/${entry}/start_point/manifest.json" | jq .image_name | grep --silent ':' ; then
      echo "${entry}'s image_name has a tag"
    fi
  fi
}

#- - - - - - - - - - - - - - - - - - - - - - - -
create_start_point_repo()
{
  local -r entry="${1}"               # eg bash-bats
  local -r repo_name="${1}"           # eg bash-bats
  local -r github_access_token="${2}" # eg 38c0......long....

  local -r src_dir="${CDL_DIR}/${entry}"
  local -r dst_dir="${CDSP_DIR}"

  local -r display_name="$(cat ${src_dir}/start_point/manifest.json | jq --raw-output .display_name)" # eg "Bash, bats"
  local -r image_name="$(cat ${src_dir}/start_point/manifest.json | jq --raw-output .image_name)" # eg cyberdojofoundation/bash_bats

  local -r home_page="https://cyber-dojo.org"

  echo "Create start_point repo from ${src_dir}"
  cp -R ${src_dir} ${dst_dir}
  cd ${dst_dir}/${entry}

  # Remove unwanted dirs
  rm -rf .git docker
  rm -rf .circleci/
  # Recreate .circleci dir
  cp -R ${CDSP_DIR}/gcc-assert/.circleci .
  # Remove unwanted files
  rm pipe_build_up_test.sh
  # Add wanted file
  cp ${CDSP_DIR}/gcc-assert/run_tests.sh .
  chmod +x run_tests.sh

  # Create new README.md
  {
    echo "[![CircleCI](https://circleci.com/gh/cyber-dojo-start-points/${repo_name}.svg?style=svg)](https://circleci.com/gh/cyber-dojo-start-points/${repo_name})"
    echo
    echo "### display_name=\"${display_name}\""
    echo "### image_name=\"[${image_name}](https://hub.docker.com/repository/docker/${image_name})\""
    echo
    echo "![cyber-dojo.org home page](https://github.com/cyber-dojo/cyber-dojo/blob/master/shared/home_page_snapshot.png)"
  } > ./README.md

  # Prepare to push to new repo
  git init
  git add .
  git commit -m "Initial commit"

  # Create new repo
  curl -H \
    "Authorization: token ${github_access_token}" \
    --data "{\"name\":\"${repo_name}\",\"description\":\"start-point for ${display_name}\",\"homepage\":\"${home_page}\"}" \
    https://api.github.com/orgs/cyber-dojo-start-points/repos

  # Make it the repo and push to it
  git remote add origin https://github.com/cyber-dojo-start-points/${repo_name}.git
  git push -u origin master

}

#- - - - - - - - - - - - - - - - - - - - - - - -
readonly GITHUB_ACCESS_TOKEN="${1}"  # eg 38c0......long....

for entry in ${CDL_DIR_LS}
do
  if [ "${entry}" == "csharp-dotnet" ]; then
    echo "Skipping ${entry} as it has no git repo."
    continue
  fi
  if [ "${entry}" == "csharp-dotnet-test" ]; then
    echo "Skipping ${entry} as it has no git repo."
    continue
  fi

  if [ "${entry}" == "bash-bats" ]; then
    echo "Skipping ${entry} as it has been coverted already."
    continue
  fi
  if [ "${entry}" == "bash-shunit2" ]; then
    echo "Skipping ${entry} as it has been coverted already."
    continue
  fi
  if [ "${entry}" == "gcc-assert" ]; then
    echo "Skipping ${entry} as it has been coverted already."
    continue
  fi
  if [ "${entry}" == "python-unittest" ]; then
    echo "Skipping ${entry} as it has been coverted already."
    continue
  fi
  if [ "${entry}" == "ruby-minitest" ]; then
    echo "Skipping ${entry} as it has been coverted already."
    continue
  fi

  # one_time_repo_name_check "${entry}"
  # one_time_image_tag_check "${entry}"

  if [ -d "${CDL_DIR}/${entry}/start_point" ]; then
    create_start_point_repo "${entry}" "${GITHUB_ACCESS_TOKEN}"
  fi

done
