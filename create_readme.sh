#!/bin/bash -Eeu

readonly REPO_NAME="${1}"
# eg gcc-assert
# Always the dir name?
# Get the repo-name from the CDL/dir?

readonly DISPLAY_NAME="${2}"
# eg "C++ (g++), assert"
# cat start_point/manifest.json | jq .display_name

readonly IMAGE_NAME="${3}"
# eg cyberdojofoundation/gcc_assert
# cat start_point/manifest.json | jq --raw-output .image_name

echo "[![CircleCI](https://circleci.com/gh/cyber-dojo-start-points/${REPO_NAME}.svg?style=svg)](https://circleci.com/gh/cyber-dojo-start-points/${REPO_NAME})"
echo
echo "### display_name=\"${DISPLAY_NAME}\""
echo "### image_name=\"[${IMAGE_NAME}](https://hub.docker.com/repository/docker/${IMAGE_NAME})\""
echo
echo "![cyber-dojo.org home page](https://github.com/cyber-dojo/cyber-dojo/blob/master/shared/home_page_snapshot.png)"
