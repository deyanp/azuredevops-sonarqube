#!/usr/bin/env bash
CURRENT_FOLDER="$(dirname $0)"
echo "CURRENT_FOLDER: $CURRENT_FOLDER"

# Example Usage:
# ./scan.sh \
#     --projectName App1 \
#     --projectPath some-folder/app1

#input
echo $1 | grep -E -q '^[a-zA-Z0-9\-]+$' || { echo "Parameter #1 projectName not provided"; exit 1; }
projectName=$1

echo $2 | grep -E -q '^[a-zA-Z0-9\-]+$' || { echo "Parameter #2 projectPath not provided"; exit 1; }
projectPath=$2

# https://github.com/gitricko/sonarless/blob/main/makefile.sh

PROJECT_NAME=$projectName
# DOCKER_SONAR_SERVER_IMAGE="sonarqube:10.6-community"
DOCKER_SONAR_SERVER_IMAGE="sonarqube:latest"
echo "DOCKER_SONAR_SERVER_IMAGE: ${DOCKER_SONAR_SERVER_IMAGE}"
DOCKER_NETWORK_NAME="sonarqube"
echo "DOCKER_NETWORK_NAME: ${DOCKER_NETWORK_NAME}"
DOCKER_SONAR_SERVER_INSTANCE_NAME="sonar-server"
echo "DOCKER_SONAR_SERVER_INSTANCE_NAME: ${DOCKER_SONAR_SERVER_INSTANCE_NAME}"
DOCKER_SONAR_SERVER_INSTANCE_PORT="9234"
echo "DOCKER_SONAR_SERVER_INSTANCE_PORT: ${DOCKER_SONAR_SERVER_INSTANCE_PORT}"
export PROJECT_PATH=$projectPath
echo "PROJECT_PATH: ${PROJECT_PATH}"

if ! docker network inspect "${DOCKER_NETWORK_NAME}" > /dev/null 2>&1; then
    echo "Creating Docker network ${DOCKER_NETWORK_NAME} ..."
    docker network create "${DOCKER_NETWORK_NAME}" > /dev/null 2>&1
else
    echo "Docker network ${DOCKER_NETWORK_NAME} already exists"
fi

if ! docker inspect "${DOCKER_SONAR_SERVER_INSTANCE_NAME}" > /dev/null 2>&1; then
        docker run -d --name "${DOCKER_SONAR_SERVER_INSTANCE_NAME}" -p "${DOCKER_SONAR_SERVER_INSTANCE_PORT}:9000" --network "${DOCKER_NETWORK_NAME}" \
            "${DOCKER_SONAR_SERVER_IMAGE}" # > /dev/null 2>&1
            # -v "${SONAR_EXTENSION_DIR}:/opt/sonarqube/extensions/plugins" \
            # -v "${SONAR_EXTENSION_DIR}:/usr/local/bin" \
        echo "docker run ${DOCKER_SONAR_SERVER_INSTANCE_NAME}"
else
    docker start "${DOCKER_SONAR_SERVER_INSTANCE_NAME}" # > /dev/null 2>&1
    echo "docker start ${DOCKER_SONAR_SERVER_INSTANCE_NAME}"
fi

echo "Booting SonarQube docker instance $DOCKER_SONAR_SERVER_INSTANCE_NAME ..."
for counter in $(seq 1 60); do
    sleep 1
    printf .
    HTTP_CODE=$(curl -k -s -o /dev/null -I -w "%{http_code}" -H 'User-Agent: Mozilla/6.0' "http://localhost:$DOCKER_SONAR_SERVER_INSTANCE_PORT" 2>/dev/null || true) # || true suppresses the error for this command, so that the script does not exit here due to the global flag "set -e"
    if [[ "${HTTP_CODE}" == "200" ]] && EXIT_CODE=0 || EXIT_CODE=-1; then
        echo "SonarQube docker instance $DOCKER_SONAR_SERVER_INSTANCE_NAME is reachable via HTTP"
        break
    fi
done

if [[ "$counter" == 60 ]]; then
    echo "SonarQube docker instance $DOCKER_SONAR_SERVER_INSTANCE_NAME is NOT reachable via HTTP, exiting"
    docker logs -f "$DOCKER_SONAR_SERVER_INSTANCE_NAME"
    exit 1
fi

echo 'Waiting for SonarQube docker instance $DOCKER_SONAR_SERVER_INSTANCE_NAME status to be "UP" ...'
for counter in $(seq 1 180); do
    sleep 1
    printf .
    status_value=$(curl -s "http://localhost:$DOCKER_SONAR_SERVER_INSTANCE_PORT/api/system/status" 2>/dev/null | jq -r '.status' || true)   # || true suppresses the error for this command, so that the script does not exit here due to the global flag "set -e"

    # Check if the status value is "running"
    if [[ "$status_value" == "UP" ]]; then
        echo "SonarQube docker instance $DOCKER_SONAR_SERVER_INSTANCE_NAME status is $status_value"
        break
    fi
done

if [[ "$counter" == 180 ]]; then
    echo "SonarQube docker instance $DOCKER_SONAR_SERVER_INSTANCE_NAME status is NOT UP but $status_value, exiting"
    docker logs -f "$DOCKER_SONAR_SERVER_INSTANCE_NAME"
    exit 1
fi

USERNAME=admin
OLD_PASSWORD=admin
PASSWORD="abcDEFG_S123"   # Password must be at least 12 characters long, Password must contain at least one uppercase character, Password must contain at least one special character
CREDENTIALS="$USERNAME:$PASSWORD"

echo "Resetting $USERNAME password to $PASSWORD (otherwise user is asked to change default password)..."
curl -s -X POST -u "$USERNAME:$OLD_PASSWORD" \
    -d "login=$USERNAME&previousPassword=$OLD_PASSWORD&password=$PASSWORD" \
    "http://localhost:${DOCKER_SONAR_SERVER_INSTANCE_PORT}/api/users/change_password"
echo "Local sonarQube URI: http://localhost:${DOCKER_SONAR_SERVER_INSTANCE_PORT}"
echo "Credentials: $CREDENTIALS"

# function scan() {
echo "Creating default project and set default fav ..."
curl -s -u "$CREDENTIALS" -X POST "http://localhost:$DOCKER_SONAR_SERVER_INSTANCE_PORT/api/projects/create?name=$PROJECT_NAME&project=$PROJECT_NAME" | jq
curl -s -u "$CREDENTIALS" -X POST "http://localhost:$DOCKER_SONAR_SERVER_INSTANCE_PORT/api/users/set_homepage?type=PROJECT&component=$PROJECT_NAME"

echo "Creating token and scan using internal-ip because of docker to docker communication"
SONAR_TOKEN=$(curl -s -X POST -u "$CREDENTIALS" "http://localhost:$DOCKER_SONAR_SERVER_INSTANCE_PORT/api/user_tokens/generate?name=$(date +%s%N)" | jq -r .token)

pushd $PROJECT_PATH   # Go to the project folder

echo "Running scan using Sonar Scanner for NPM"
npx -y sonarqube-scanner -Dsonar.host.url="http://localhost:$DOCKER_SONAR_SERVER_INSTANCE_PORT" -Dsonar.token="$SONAR_TOKEN" -Dsonar.projectKey="$PROJECT_NAME"

popd

pushd $CURRENT_FOLDER   # Go to the script folder

echo "Collecting scan results via the Web API ..."
SONAR_OUTPUT_FOLDER="$PROJECT_PATH/.sonar"
SONAR_METRICS_PATH="$SONAR_OUTPUT_FOLDER/sonar-metrics.json"
mkdir -p "${SONAR_METRICS_PATH%/*}"

SLEEP_SECONDS=10
echo "Sleeping $SLEEP_SECONDS seconds to let SonarQube finish processing the scan results ..."
sleep $SLEEP_SECONDS

curl -s -u "$CREDENTIALS" "http://localhost:${DOCKER_SONAR_SERVER_INSTANCE_PORT}/api/measures/component?component=${PROJECT_NAME}&metricKeys=bugs,vulnerabilities,code_smells,quality_gate_details,violations,duplicated_lines_density,ncloc,coverage,reliability_rating,security_rating,security_review_rating,sqale_rating,security_hotspots,open_issues" \
    | jq -r > $SONAR_METRICS_PATH
echo "Scan results written to $SONAR_METRICS_PATH"
cat $SONAR_METRICS_PATH

echo "Installing Playwright ..."
npm install
npx playwright install --with-deps --no-shell
echo "Collecting scan results via the Web UI ..."
tsc save_mhtml.ts
node save_mhtml.js --projectName $PROJECT_NAME --outputFolder $SONAR_OUTPUT_FOLDER

popd

read -p "Press enter to clean up docker"
echo "Cleaning up docker ..."
docker stop "$DOCKER_SONAR_SERVER_INSTANCE_NAME" > /dev/null 2>&1
echo "Local SonarQube docker instance \"$DOCKER_SONAR_SERVER_INSTANCE_NAME\" has been stopped"
docker rm -f "$DOCKER_SONAR_SERVER_INSTANCE_NAME"
echo "Local SonarQube docker instance \"$DOCKER_SONAR_SERVER_INSTANCE_NAME\" has been removed"
# docker image rm -f "$DOCKER_SONAR_SERVER_IMAGE"
# echo "Docker image $DOCKER_SONAR_SERVER_IMAGE has been removed"
docker volume prune -a -f
echo "Docker volumes have been pruned"
docker network rm -f "$DOCKER_NETWORK_NAME"
echo "Docker network $DOCKER_NETWORK_NAME has been removed"
echo "Clean up docker done"

echo "Checking SonarQube metrics ..."
vulnerabilities=$(cat $SONAR_METRICS_PATH | jq -r '.component.measures[] | select(.metric == "vulnerabilities") | .value')
if [[ "$vulnerabilities" -gt 0 ]]; then
    echo "Vulnerabilities found: $vulnerabilities"
    exit 1
else
    echo "No vulnerabilities found"
fi
