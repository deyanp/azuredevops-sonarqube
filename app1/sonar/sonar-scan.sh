#!/usr/bin/env bash
CURRENT_FOLDER="$(dirname $0)"

$CURRENT_FOLDER/../sonar/sonar-scan.sh --projectName=App1 --projectPath=$CURRENT_FOLDER