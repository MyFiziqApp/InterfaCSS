#!/usr/bin/env python3

"""Script to simplify publish of SDK for release (available to partners).
"""

from __future__ import print_function
import os
import sys
import argparse
import subprocess
import shutil
from git import Repo, GitCommandError
from pathlib import Path

# helper functions

def askUserToContinue():
  should_continue = input("\nContinue? (type 'y' to continue, or anything else to abort): ")
  if should_continue == 'y':
    return True
  return False

# git check functions

def gitCheckIsCorrectBranch(repo, sdk_version):
  print("INFO: Checking if on the correct branch...")
  # Check if on the correct branch
  trunk_branch = sdk_version + '_trunk'
  if repo.active_branch.name != trunk_branch:
    print("FAILED - ❌")
    return False
  print("PASS - ✅ - Repo is on the correct branch")
  return True

def gitCheckIsDirty(repo, sdk_version):
  print("INFO: Checking if sandbox has become dirty...")
  if repo.is_dirty() or len(repo.untracked_files) != 0:
    print("FAILED - ❌")
    return True
  print("PASS - ✅ - Repo is clean")
  return False

# git sync functions

def gitSyncPullGitHub(repo, sdk_version):
  trunk_branch = sdk_version + '_trunk'
  ref_spec = "refs/heads/" + trunk_branch + ":refs/heads/" + trunk_branch
  print("INFO: Pull from GitHub...")
  try:
    repo.remotes.fork.pull(refspec=ref_spec)
  except GitCommandError as e:
    print("WARN - 🚨 - An error occured: " + e.stderr)
  return

def gitSyncPushGitHub(repo, sdk_version):
  trunk_branch = sdk_version + '_trunk'
  ref_spec = "refs/heads/" + trunk_branch + ":refs/heads/" + trunk_branch
  print("INFO: Push to GitHub...")
  try:
    repo.remotes.fork.push(refspec=ref_spec)
  except GitCommandError as e:
    print("WARN - 🚨 - An error occured: " + e.stderr)
  return

# CocoaPods sync functions

def podUpdate(sdk_dir):
  print("INFO: CocoaPods repo update...")
  subprocess.run(["pod", "repo", "update"])
  print("INFO: CocoaPods install...")
  try:
    shutil.rmtree(sdk_dir + "/Example/Pods")
    os.remove(sdk_dir + "/Example/Podfile.lock")
  except:
    print("Error removing Pods")
  example_path = sdk_dir + "/Example"
  subprocess.run(["pod", "install"], cwd=example_path)

def podSpecLint(sdk_dir):
  print("INFO: Initiating CocoaPods linter...")
  subprocess.run(["pod", "spec", "lint", "--allow-warnings", "--sources=https://cdn.cocoapods.org/,https://git-codecommit.ap-southeast-1.amazonaws.com/v1/repos/myfiziq-sdk-podrepo"])

def podSpecPush(sdk_dir):
  print("INFO: Initiating CocoaPods repo push to publish the new SDK release...")
  subprocess.run(["pod", "repo", "push", "myfiziq-private", "--allow-warnings"])

def podCleanUpdate(sdk_dir):
  print("INFO: CocoaPods cache cleae...")
  subprocess.run(["pod", "cache", "clean", "--all"])
  print("INFO: CocoaPods repo update...")
  subprocess.run(["pod", "repo", "update"])

# Main

def main(arguments):
    parser = argparse.ArgumentParser(
        description = "Script to simplify publish of SDK for release (available to partners).",
        epilog = "As an alternative to the commandline, params can be placed in a file, one per line, and specified on the commandline like '%(prog)s @params.conf'.",
        fromfile_prefix_chars = '@'
    )
    parser.add_argument('-v', '--sdkversion', metavar=('SDKVER'), required=True, nargs='?', help="The version tag of the release (e.g. '19.2.0')")
    parser.add_argument('-d', '--dir', metavar=('DIR'), required=False, default='.', nargs='?', help="The directory of the SDK")
    args = parser.parse_args(arguments)

    sdk_version = args.sdkversion.replace('"', '')
    sdk_dir = args.dir.replace('"', '')

    repo = Repo(sdk_dir)

    print("\n\n++++ GIT CHECKS ++++")
    if askUserToContinue() == False:
      return
    if gitCheckIsCorrectBranch(repo, sdk_version) == False:
      return
    if gitCheckIsDirty(repo, sdk_version) == True:
      return
    print("done.\n\n")

    print("++++ GIT REPO SYNC ++++")
    if askUserToContinue() == False:
      return
    gitSyncPullGitHub(repo, sdk_version)
    gitSyncPushGitHub(repo, sdk_version)
    if gitCheckIsDirty(repo, sdk_version) == True:
      return
    print("done.\n\n")

    print("++++ POD UPDATE CHECK ++++")
    if askUserToContinue() == False:
      return
    podUpdate(sdk_dir)
    if gitCheckIsDirty(repo, sdk_version) == True:
      return
    print("done.\n\n")
    
    print("++++ CocoaPods LINT ++++")
    if askUserToContinue() == False:
      return
    podSpecLint(sdk_dir)
    print("done.\n\n")

    print("++++ CocoaPods PUBLISH ++++")
    if askUserToContinue() == False:
      return
    podSpecPush(sdk_dir)
    podCleanUpdate(sdk_dir)
    print("done.\n\n")


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
