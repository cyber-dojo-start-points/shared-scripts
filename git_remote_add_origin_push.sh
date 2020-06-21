#!/bin/bash -Eeu

readonly REPO_NAME="${1}" # eg bash-bats

git remote add origin https://github.com/cyber-dojo-start-points/${REPO_NAME}.git
git push -u origin master
