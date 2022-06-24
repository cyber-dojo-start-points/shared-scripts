#!/usr/bin/env python3

import os
import subprocess


NO_CONFIG = []
ALREADY_UPGRADED = []
NOT_USING_OLD_IMAGE = []
UPGRADED = []


def ci_fix_machine_images():
    repo_names = [item for item in os.listdir(".") if os.path.isdir(item)]
    for repo_name in repo_names:
        ci_fix_machine_image_in_repo(repo_name)


def ci_fix_machine_image_in_repo(repo_name):
    if edit_config_file(repo_name):
        git_add(repo_name)
        git_commit(repo_name)
        git_push(repo_name)
        UPGRADED.append(repo_name)


OLD_IMAGE = "ubuntu-1604:201903-01"
NEW_IMAGE = "ubuntu-2204:2022.04.2"


def edit_config_file(repo_name):
    filename_path = filename(repo_name)
    if not os.path.isfile(filename_path):
        NO_CONFIG.append(repo_name)
        return False

    with open(filename_path, "r") as f:
        old_config = f.read()

    new_config = old_config.replace(OLD_IMAGE, NEW_IMAGE)
    if new_config != old_config:
        with open(filename_path, "w") as f:
           f.write(new_config)
        return True
    elif NEW_IMAGE in old_config:
        ALREADY_UPGRADED.append(repo_name)
        return False
    else:
        NOT_USING_OLD_IMAGE.append(repo_name)
        return False


def git_add(repo_name):
    bash(repo_name, ['git', 'add', '.'])


def git_commit(repo_name):
    bash(repo_name, ['git', 'commit', '-m', '"Upgrade CI to ubuntu 2204 base image"'])


def git_push(repo_name):
    bash(repo_name, ['git', 'push'])


def bash(repo_name, command):
    subprocess.run(command, cwd=f"./{repo_name}", text=True, check=True)


def filename(repo_name):
    return f"./{repo_name}/.circleci/config.yml"


if __name__ == "__main__":
    ci_fix_machine_images()
    print("No config\n", NO_CONFIG)
    print("Already upgraded\n", ALREADY_UPGRADED)
    print("Not using old image\n", NOT_USING_OLD_IMAGE)
    print("Upgraded\n", UPGRADED)

