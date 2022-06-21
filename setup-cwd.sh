#!/bin/bash

#########################################
# This script uses real Confluent Cloud resources.
# To avoid unexpected charges, carefully evaluate the cost of resources before launching 
# the script and ensure all resources are destroyed after you are done running it.
#########################################

NAME=`basename "$0"`
# Setting default QUIET=false to surface potential errors
QUIET="${QUIET:-false}"
[[ $QUIET == "true" ]] && 
  REDIRECT_TO="/dev/null" ||
  REDIRECT_TO="/dev/tty"

# Install required packages

printf "\nUpdating and installing required packages\n"
CMD="sudo apt-get update && sudo apt-get install -q -y jq apache2 python3-pip libapache2-mod-wsgi-py3 python3-confluent-kafka python3-avro python3-flask python3-flask-cors python3-werkzeug python3-rjsmin python3-rcssmin python3-requests certbot python3-certbot-apache docker-compose"
eval $CMD \
  && print_code_pass -c "$CMD" \
    || exit_with_error -c $? -n "$NAME" -m "$CMD" -l $(($LINENO -3))


printf "\nInstalling filebeat\n"
CMD="curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-8.2.2-amd64.deb && sudo dpkg -i filebeat-8.2.2-amd64.deb && rm filebeat-8.2.2-amd64.deb"
eval $CMD \
  && print_code_pass -c "$CMD" \
    || exit_with_error -c $? -n "$NAME" -m "$CMD" -l $(($LINENO -3))

printf "\nStaring local Splunk instance using docker-compose\n"
CMD="sudo docker-compose up -d"
eval $CMD \
  && print_code_pass -c "$CMD" \
    || exit_with_error -c $? -n "$NAME" -m "$CMD" -l $(($LINENO -3))

printf "\nSetting up website configuration\n"
SEDCMD="s/===WEBHOSTNAME===/$WEBHOSTNAME/g"
CMD="sed -e $SEDCMD cwd/apache2/sites-available/wordle.conf > wordle.conf && sudo cp wordle.conf /etc/apache2/sites-available/ && sudo cp -r cwd/wsgi /var/www/wsgi && sudo chown -R www-data:www-data /var/www/wsgi && sudo a2ensite wordle && sudo a2enmod rewrite proxy proxy_http && sudo systemctl reload apache2 && sudo certbot --non-interactive --apache --agree-tos -m $YOUREMAIL -d $WEBHOSTNAME"
eval $CMD \
  && print_code_pass -c "$CMD" \
    || exit_with_error -c $? -n "$NAME" -m "$CMD" -l $(($LINENO -3))



# Install Confluent CLI

if ! command -v confluent &> /dev/null
then
	echo "confluent cli not installed or in the path... Installing"
	curl -sL --http1.1 https://cnfl.io/cli | sh -s -- latest
fi
export PATH=$PWD/bin:$PATH
confluent login --save

# Source library
source utils/helper.sh
source utils/ccloud_library.sh

check_jq \
  && print_pass "jq found"

[[ -z "$AUTO" ]] && {
  printf "\n====== Confirm\n\n"
  ccloud::prompt_continue_ccloud_demo || exit 1
  read -p "Do you acknowledge this script creates a Confluent Cloud KSQL app (hourly charges may apply)? [y/n] " -n 1 -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi
	printf "\n"
} 

ccloud::validate_version_cli $CLI_MIN_VERSION \
  && print_pass "Confluent CLI version ok"

ccloud::validate_logged_in_cli \
  && print_pass "Logged into the Confluent CLI" 

print_pass "Prerequisite check pass"

printf "\nFor your reference the demo will highlight some commands in "; print_code "code format"

printf "\n====== Starting\n\n"

printf "\n====== Creating new Confluent Cloud stack using the ccloud::create_ccloud_stack function\nSee: %s for details\n" "https://github.com/confluentinc/examples/blob/$CONFLUENT_RELEASE_TAG_OR_BRANCH/utils/ccloud_library.sh"
export EXAMPLE="wordle-demo"
ccloud::create_ccloud_stack true  \
	&& print_code_pass -c "cccloud::create_ccloud_stack true"

SERVICE_ACCOUNT_ID=$(ccloud:get_service_account_from_current_cluster_name)
CONFIG_FILE=stack-configs/java-service-account-$SERVICE_ACCOUNT_ID.config
export CONFIG_FILE=$CONFIG_FILE
ccloud::validate_ccloud_config $CONFIG_FILE || exit 1

ccloud::generate_configs $CONFIG_FILE \
	&& print_code_pass -c "ccloud::generate_configs $CONFIG_FILE"

DELTA_CONFIGS_ENV=delta_configs/env.delta
printf "\nSetting local environment based on values in $DELTA_CONFIGS_ENV\n"
CMD="source $DELTA_CONFIGS_ENV"
eval $CMD \
  && print_code_pass -c "$CMD" \
    || exit_with_error -c $? -n "$NAME" -m "$CMD" -l $(($LINENO -3))

# false argument here means defer checking on ksqlDB to later in the script, to optimize time to run
ccloud::validate_ccloud_stack_up $CLOUD_KEY $CONFIG_FILE false || exit 1

printf "\n";print_process_start "====== Pre-creating topics"

CMD="confluent kafka topic create game --partitions 1"
$CMD &>"$REDIRECT_TO" \
  && print_code_pass -c "$CMD" \
  || exit_with_error -c $? -n "$NAME" -m "$CMD" -l $(($LINENO -3)) 

CMD="confluent kafka topic create guesses --partitions 1"
$CMD &>"$REDIRECT_TO" \
  && print_code_pass -c "$CMD" \
  || exit_with_error -c $? -n "$NAME" -m "$CMD" -l $(($LINENO -3))

CMD="confluent kafka topic create registrations --partitions 1"
$CMD &>"$REDIRECT_TO" \
  && print_code_pass -c "$CMD" \
  || exit_with_error -c $? -n "$NAME" -m "$CMD" -l $(($LINENO -3))

CMD="confluent kafka topic create wordle-web-log"
$CMD &>"$REDIRECT_TO" \
  && print_code_pass -c "$CMD" \
  || exit_with_error -c $? -n "$NAME" -m "$CMD" -l $(($LINENO -3))

print_pass "Topics created"
 

printf "\n====== Setting up ksqlDB\n"
date
# Pre-flight check of Confluent Cloud credentials specified in $CONFIG_FILE
MAX_WAIT=1440
printf "\n";print_process_start "Waiting up to $MAX_WAIT seconds for Confluent Cloud ksqlDB cluster to be UP"
retry $MAX_WAIT ccloud::validate_ccloud_ksqldb_endpoint_ready $KSQLDB_ENDPOINT || exit 1
print_pass "Confluent Cloud KSQL is UP"
date
printf "Obtaining the ksqlDB App Id\n"
CMD="confluent ksql cluster list -o json | jq -r '.[].id'"
ksqlDBAppId=$(eval $CMD) \
  && print_code_pass -c "$CMD" -m "$ksqlDBAppId" \
  || exit_with_error -c $? -n "$NAME" -m "$CMD" -l $(($LINENO -3))

printf "\nConfiguring ksqlDB ACLs\n"
CMD="confluent ksql cluster configure-acls $ksqlDBAppId pageviews users"
$CMD \
  && print_code_pass -c "$CMD" \
  || exit_with_error -c $? -n "$NAME" -m "$CMD" -l $(($LINENO -3))

echo -e "\nSleeping 60 seconds\n"
sleep 60
printf "\nSubmitting KSQL queries via curl to the ksqlDB REST endpoint\n"
printf "\tSee https://docs.ksqldb.io/en/latest/developer-guide/api/ for more information\n"
while read ksqlCmd; do # from statements-cloud.sql
  response=$(curl -w "\n%{http_code}" -X POST $KSQLDB_ENDPOINT/ksql \
       -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
	       -u $KSQLDB_BASIC_AUTH_USER_INFO \
	       --silent \
	       -d @<(cat <<EOF
	{
	  "ksql": "$ksqlCmd",
	  "streamsProperties": {
			"ksql.streams.auto.offset.reset":"earliest",
			"ksql.streams.cache.max.bytes.buffering":"0"
		}
	}
EOF
	))
	echo "$response" | {
	  read body
	  read code
	  if [[ "$code" -gt 299 ]];
	    then print_code_error -c "$ksqlCmd" -m "$(echo "$body" | jq .message)"
	    else print_code_pass  -c "$ksqlCmd" -m "$(echo "$body" | jq -r .[].commandStatus.message)"
	  fi
	}
sleep 3;
done < statements-cloud.sql
printf "\nConfluent Cloud ksqlDB ready\n"

printf "\nStarting a local instance of Splunk Enterprise within Docker\n"
sudo docker-compose up -d
echo -e "\nSleeping 60 seconds\n"
sleep 60
printf "\nValidate that there are no errors within Docker\n"
sudo docker-compose ps

printf "\nAdding ccloud python config to Wordle app\n"
sudo sh -c 'awk "/^producer = Producer/,/})/" delta_configs/python.delta | awk "!/(plugin|location|configuration)/" > /var/www/wsgi/cwd/kafka.config'
sudo sed -i "/###PRODUCER START###/r /var/www/wsgi/cwd/kafka.config" /var/www/wsgi/cwd/app.py
sudo sh -c 'cd /var/www/wsgi/cwd && python3 init.py && chown -R www-data:www-data .'
sudo systemctl restart apache2
:
printf "\nConfiguring filebeat to send to CC\n"
. ./delta_configs/env.delta
sudo cp filebeat.yml /etc/filebeat/filebeat.yml
sudo cp filebeat.apache.yml /etc/filebeat/modules.d/apache.yml
sudo sed -i "s ###BOOTSTRAP### $BOOTSTRAP_SERVERS " /etc/filebeat/filebeat.yml
sudo sed -i "s ###USERNAME### $CLOUD_KEY " /etc/filebeat/filebeat.yml
sudo sed -i "s ###PASSWORD### $CLOUD_SECRET " /etc/filebeat/filebeat.yml
sudo systemctl restart filebeat

printf "/nCreate Splunk Sink Managed Connector/n"
sed -e "s ###USERNAME### $CLOUD_KEY " -e "s ###PASSWORD### $CLOUD_SECRET " -e "s ###WEBHOSTNAME### $WEBHOSTNAME " splunk_connector.json > connector.json
CMD="confluent connect create --config connector.json"
$CMD &>"$REDIRECT_TO" \
  && print_code_pass -c "$CMD" \
  || exit_with_error -c $? -n "$NAME" -m "$CMD" -l $(($LINENO -3)) 


printf "\nLocal client configuration file written to $CONFIG_FILE\n\n"

printf "====== Verify\n"


printf "\nConfluent Cloud ksqlDB and the fully managed Datagen Source Connectors are running and accruing charges. To destroy this demo and its Confluent Cloud resources->\n"
printf "\t./stop-cloud.sh $CONFIG_FILE\n\n"
