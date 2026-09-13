#!/bin/bash

read -n 1 -s -r -p "Press enter to continue with npm version patch..."
# press enter
npm version patch

read -n 1 -s -r -p "Press enter to continue with npm pack and publish..."
# press enter
npm pack --dry-run

read -n 1 -s -r -p "Press enter to continue with npm publish..."
# press enter
npm publish

read -n 1 -s -r -p "Press enter to continue with git push..."
# press enter
git push --follow-tags