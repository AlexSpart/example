#!/bin/sh
export GMT_DOCKER_COMPOSE_URL="https://github.com/radon-h2020/radon-gmt/blob/project/radon/docker-compose.yml"
export GMT_HTTP_PORT="18080"
export PARTICLES_URL="https://github.com/radon-h2020/radon-particles.git"
export PARTICLES_BRANCH="master"
export PARTICLES_DIR="/tmp/radon-particles"
export CTT_DOCKER_NAME="RadonCTT"
export CTT_SERVER_DOCKER="radonconsortium/radon-ctt"
export CTT_VOLUME="/tmp/RadonCTT"
export CTT_PORT="18080"
export CTT_EXT_PORT="7999"
export CTT_ENDPOINT="http://localhost:${CTT_EXT_PORT}/RadonCTT"
export CTT_RESULT_FILE="/tmp/result.zip"
export SOCKSHOP_DEMO_URL="https://github.com/radon-h2020/demo-ctt-sockshop.git"
export SOCKSHOP_DEMO_BRANCH="master"
export SOCKSHOP_DEMO_DIR="/tmp/demo-ctt-sockshop"
export SUT_CSAR_FN="sut.csar"
export SUT_CSAR="/tmp/${SUT_CSAR_FN}"
export TI_CSAR_FN="ti.csar"
export TI_CSAR="/tmp/${TI_CSAR_FN}"
    

export NAME="CTT-master"
export CTT_SERVER_DOCKER_TAG="latest"
export SUT_EXPORT_URL="http://127.0.0.1:${GMT_HTTP_PORT}/winery/servicetemplates/radon.blueprints/SockShopTestingExample/?yaml&csar"
export SUT_DEPLOYMENT_PORT="80"
export SUT_DEPLOYMENT_URL="http://localhost:${SUT_DEPLOYMENT_PORT}"
export TI_EXPORT_URL="http://127.0.0.1:${GMT_HTTP_PORT}/winery/servicetemplates/radon.blueprints.testing/JMeterMasterOnly/?yaml&csar"
export TI_DEPLOYMENT_PORT="5000"
export TI_DEPLOYMENT_URL="http://localhost:${TI_DEPLOYMENT_PORT}"

#sudo apt-get -y install docker-compose python3 python3-setuptools python3-wheel python3-pip python3-docker python3-apt jq ansible
python3 -m pip install -r requirements.txt
python3 -m pip install docker-compose docker jq ansible --user
export PATH=/home/jenkins/.local/bin:$PATH
echo $PATH
ls /home/jenkins/.local/bin

echo "remove direcotries from previous builds"
chmod 777 /tmp/RadonCTT
rm -rf /tmp/radon-particles && echo "Deleted radon-particles directory..."
rm -rf /tmp/RadonCTT && echo "Deleted RadonCTT directory..."
rm -rf /tmp/demo-ctt-sockshop && echo "Deleted demo-ctt-sockshop directory..."

set -e
  # Pull Winery
docker-compose pull
  # Clone Particles
git clone --single-branch --branch "${PARTICLES_BRANCH}" "${PARTICLES_URL}" "${PARTICLES_DIR}" || true
chmod -R a+rwx "${PARTICLES_DIR}"
  # Start Winery
docker-compose up -d
  # Start CTT server
mkdir ${CTT_VOLUME} || echo "the ${CTT_VOLUME} already exists"
  # Remove docker 'RadonCTT' from previous build
sh 'docker rm -f ${CTT_DOCKER_NAME} || true'
docker run --name "${CTT_DOCKER_NAME}" -d -p "127.0.0.1:${CTT_EXT_PORT}:${CTT_PORT}" -v /var/run/docker.sock:/var/run/docker.sock -v "${CTT_VOLUME}:/tmp/RadonCTT" "${CTT_SERVER_DOCKER}:${CTT_SERVER_DOCKER_TAG}"
sleep 20
  # 
  SockShop
git clone --single-branch --branch "${SOCKSHOP_DEMO_BRANCH}" "${SOCKSHOP_DEMO_URL}" "${SOCKSHOP_DEMO_DIR}" || true
  # Obtain SUT CSAR
curl -H 'Accept: application/xml' -o \"${SUT_CSAR}\" \"${SUT_EXPORT_URL}\"
echo \"${SUT_CSAR} available at: `curl -F \"file=@${SUT_CSAR}\" \"https://file.io/?expires=1w\" | jq -e '.link'`\"
  # Obtain TI CSAR
curl -H 'Accept: application/xml' -o \"${TI_CSAR}\" \"${TI_EXPORT_URL}\"
echo \"${TI_CSAR} available at: `curl -F \"file=@${TI_CSAR}\" \"https://file.io/?expires=1w\" | jq -e '.link'`\"
  # Shutdown Winery
docker-compose rm -fsv
  # CTT: Create Project
export CTT_PROJECT_UUID=$(./curl_uuid.sh \"${CTT_ENDPOINT}/project\" \"{\\\"name\\\":\\\"SockShop\\\",\\\"repository_url\\\":\\\"${SOCKSHOP_DEMO_URL}\\\"}\")
  # Copy CSARs into project
sudo cp "${SUT_CSAR}" "${TI_CSAR}" "${CTT_VOLUME}/project/${CTT_PROJECT_UUID}/radon-ctt/."
  # CTT: Create Test-Artifact
export CTT_TESTARTIFACT_UUID=$(./curl_uuid.sh \"${CTT_ENDPOINT}/testartifact\" \"{\\\"project_uuid\\\":\\\"${CTT_PROJECT_UUID}\\\",\\\"sut_tosca_path\\\":\\\"radon-ctt/${SUT_CSAR_FN}\\\",\\\"ti_tosca_path\\\":\\\"radon-ctt/${TI_CSAR_FN}\\\"}\")
  # CTT: Create Deployment
export CTT_DEPLOYMENT_UUID=$(./curl_uuid.sh  \"${CTT_ENDPOINT}/deployment\" \"{\\\"testartifact_uuid\\\":\\\"${CTT_TESTARTIFACT_UUID}\\\"}\")
  # Give deployments some time to succeed.
sleep 120
echo \"DEPLOYMENT_UUID: ${CTT_DEPLOYMENT_UUID}\"
  # Check SUT Deployment
export SUT_DEPLOYMENT_HTTP=$(curl -o /dev/null -s -w \"%{http_code}\\n\" \"${SUT_DEPLOYMENT_URL}\")
export TI_DEPLOYMENT_HTTP=$(curl -o /dev/null -s -w \"%{http_code}\\n\" \"${TI_DEPLOYMENT_URL}\")
echo HTTP Codes: SUT ${SUT_DEPLOYMENT_HTTP}, TI ${TI_DEPLOYMENT_HTTP}
  # CTT: Trigger Execution
export CTT_EXECUTION_UUID=$(./curl_uuid.sh \"${CTT_ENDPOINT}/execution\" \"{\\\"deployment_uuid\\\":\\\"${CTT_DEPLOYMENT_UUID}\\\"}\")
sleep 30
  # CTT: Create Result
export CTT_RESULT_UUID=$(./curl_uuid.sh \"${CTT_ENDPOINT}/result\" \"{\\\"execution_uuid\\\":\\\"${CTT_EXECUTION_UUID}\\\"}\")
echo \"RESULT_UUID: ${CTT_RESULT_UUID}\"
  # CTT: Obtain Result
wget "${CTT_ENDPOINT}/result/${CTT_RESULT_UUID}/download" -O "${CTT_RESULT_FILE}" 
echo \"CTT result file available at `curl -F \"file=@${CTT_RESULT_FILE}\" \"https://file.io/?expires=1w\" | jq -e '.link'`\"
ls -al \"${CTT_RESULT_FILE}\"
set +e

docker logs "${CTT_DOCKER_NAME}" | tee ctt_docker.log
echo \"CTT logs available at: `curl -F \"file=@ctt_docker.log\" \"https://file.io/?expires=1w\" | jq -e '.link'`\"

