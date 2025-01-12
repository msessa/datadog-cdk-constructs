#!/bin/bash

# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2021 Datadog, Inc.

set -e

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ $BRANCH != "main" ]; then
    echo "Not on main, aborting"
    exit 1
else
    echo "Updating main"
    git pull origin main
fi

#Read the current version
CURRENT_VERSION=$(node -pe "require('./package.json').version")

#Read the desired version
if [ -z "$1" ]; then
    echo "Must specify a desired version number"
    exit 1
elif [[ ! $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Must use a semantic version, e.g., 3.1.4"
    exit 1
else
    VERSION=$1
fi

if ! [ -x "$(command -v yarn)" ]; then
  echo 'Error: yarn is not installed.'
  exit 1
fi
if ! [ -x "$(command -v pip)" ]; then
  echo 'Error: pip is not installed.'
  exit 1
fi
pip3 install --upgrade twine
if ! [ -x "$(command -v python3)" ]; then
  echo 'Error: python3 is not installed.'
  exit 1
fi

# Make sure dependencies are installed before proceeding
yarn

read -p "Do you have the PyPI and npm login credentials for the Datadog account (y/n)?" CONT
if [ "$CONT" != "y" ]; then
    echo "Exiting"
    exit 1
fi

echo "Removing folder 'dist' to clear previously built distributions"
rm -rf dist;

#Confirm to proceed
read -p "About to bump the version from ${CURRENT_VERSION} to ${VERSION}, and publish. Continue (y/n)?" CONT
if [ "$CONT" != "y" ]; then
    echo "Exiting"
    exit 1
fi

if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
    echo "tag v${VERSION} already exists, aborting"
    exit 1
fi

echo "Bumping the version number and committing the changes"
if git log --oneline -1 | grep -q "chore(release):"; then
    echo "Create a new commit before attempting to release. Be sure to not include 'chore(release):' in the commit message. This means if the script previously prematurely ended without publishing you may need to 'git reset --hard' to a previous commit before trying again, aborting"
    exit 1
else
    yarn standard-version --release-as $VERSION
fi

echo "Building artifacts"
yarn build
#Make sure artifacts were created before publishing
JS_TARBALL=./dist/js/datadog-cdk-constructs@$VERSION.jsii.tgz
if [ ! -f $JS_TARBALL ]; then
    echo "'${JS_TARBALL}' not found. Run 'yarn build' and ensure this file is created."
    exit 1
fi

PY_WHEEL=./dist/python/datadog_cdk_constructs-$VERSION-py3-none-any.whl
if [ ! -f $PY_WHEEL ]; then
    echo "'${PY_WHEEL}' not found. Run 'yarn build' and ensure this file is created."
    exit 1
fi

PY_TARBALL=./dist/python/datadog-cdk-constructs-$VERSION.tar.gz
if [ ! -f $PY_TARBALL ]; then
    echo "'${PY_TARBALL}' not found. Run 'yarn build' and ensure this file is created."
    exit 1
fi

yarn logout
yarn login

echo "Publishing to npm"
yarn publish $JS_TARBALL --new-version "$VERSION"

echo "Publishing to PyPI"
python3 -m twine upload ./dist/python/*

echo 'Pushing updates to github'
git push origin main
git push origin "refs/tags/v$VERSION"
echo 'Please add release notes in GitHub!'
