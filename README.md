
Holds the [red_amber_green_test.sh](red_amber_green_test.sh) file which is used in _all_ start-point repos to verify they can successfully build a start-point image (from their own dir).

```
$ ./red_amber_green_test.sh --help

Use: red_amber_green_test.sh [GIT_REPO_DIR|-h|--help]

  GIT_REPO_DIR defaults to ${PWD}.
  GIT_REPO_DIR must hold a git repo.
  GIT_REPO_DIR/start_point/ must exist.

  *) Verifies you can build a start-point image from ${GIT_REPO_DIR}.
      $ cyber-dojo start-point create ... --languages ${GIT_REPO_DIR}

  *) Checks the ${GIT_REPO_DIR}/start_point/ files run against the 'image_name'
      specified in ${GIT_REPO_DIR}/start_point/manifest.json are:
        o) RED   when unmodified
        o) AMBER when '6 * 9' is replaced by '6 * 9sd'
        o) GREEN when '6 * 9' is replaced by '6 * 7'
      If there is no ${GIT_REPO_DIR}/start_point/ file containing '6 * 9',
      looks for the file ${GIT_REPO_DIR}/start_point/options.json. For example, see:
      https://github.com/cyber-dojo-languages/nasm-assert/tree/main/start_point
```