#!/usr/bin/env python3

import os
import subprocess


def ci_fix_machine_images():
    repo_names = [item for item in os.listdir(".") if os.path.isdir(item)]
    for repo_name in repo_names:
        if repo_name not in ["shared-scripts", "python-pytest", "python-behave"]:
            ci_fix_machine_image_in_repo(repo_name)


def ci_fix_machine_image_in_repo(repo_name):
    edit_config_file(repo_name)
    git_add(repo_name)
    git_commit(repo_name)
    git_push(repo_name)


def edit_config_file(repo_name):
    with open(filename(repo_name), "r") as f:
        old_config = f.read()
    with open(filename(repo_name), "w") as f:
        f.write(new_config(old_config))


def new_config(old_config):
    old_image = "ubuntu-1604:201903-01"
    new_image = "ubuntu-2204:2022.04.2"
    return old_config.replace(old_image, new_image)



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
