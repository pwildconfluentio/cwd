
# Overview

The Confluent Wordle Demo (CWD)

This demo is based on the New York Time Wordle game.
The original game can be found here: [Wordle](https://www.nytimes.com/games/wordle/index.html)

The demo re-uses the works of Tommy Dougiamas, a Computer Science student at UWA in Perth Western Austrlia (where I live!).
His github repo is here: [exciteabletom/wordle-API](https://github.com/exciteabletom/wordle-API)

The following changes were made to his code:
* A Registration page was created to capture player details so a prize can be awarded
* Kafka producer code was added to stream game play into a Confluent Cloud cluster
* Removed the ability to share the game number you are playing (so you can't cheat)
* Added links to https://developer.confluent.io 

![image](images/WordleDemoImage.jpg)

# Prerequisites

* An appropriately sized virtual machine somewhere running Ubuntu 22.04
* I'd suggest an AWS T2.large (2 CPU, 8GB & 20GB of Disk because we'll install Splunk for dashboarding)
* A publicly routable IP address and a configured FQDNS A record that will work with Letsencrypt
* An active Confluent Cloud login (the script will use the CLI to provision a Confluent Basic Cluster and setup everything) 

# Run demo

## Confluent Platform

* [Confluent Platform Quick Start](https://docs.confluent.io/platform/current/quickstart/ce-quickstart.html#ce-quickstart?utm_source=github&utm_medium=demo&utm_campaign=ch.examples_type.community_content.cp-quickstart) for the local tarball install of Confluent Platform: run the command below and then open your browser and navigate to the Control Center at http://localhost:9021/:

```bash
./start.sh
```

* [Confluent Platform Quick Start](https://docs.confluent.io/platform/current/quickstart/ce-docker-quickstart.html#ce-docker-quickstart?utm_source=github&utm_medium=demo&utm_campaign=ch.examples_type.community_content.cp-quickstart) for the Docker version of Confluent Platform: run the command below and then open your browser and navigate to the Control Center at http://localhost:9021/:

```bash
./start-docker.sh
```

* [Confluent Platform Quick Start](https://docs.confluent.io/platform/current/quickstart/cos-docker-quickstart.html#cos-docker-quickstart?utm_source=github&utm_medium=demo&utm_campaign=ch.examples_type.community_content.cp-quickstart) for the Docker version of Confluent Platform with community components only: run the command below:

```bash
./start-docker-community.sh
```

## Confluent Cloud

* This quickstart for Confluent Cloud is similar to those above for Confluent Platform, but leverages 100% Confluent Cloud services, including a [ksqlDB application](statements-cloud.sql) which builds streams and tables using Avro, Protobuf and JSON based formats. After logging into the Confluent CLI, run the command below and open your browser navigating to https://confluent.cloud. Note: the demo creates real cloud resources and incurs charges.

```bash
./start-cloud.sh
```

* The first 20 users to sign up for [Confluent Cloud](https://www.confluent.io/confluent-cloud/?utm_source=github&utm_medium=demo&utm_campaign=ch.examples_type.community_content.clients-ccloud) and use promo code ``C50INTEG`` will receive an additional $50 free usage ([details](https://www.confluent.io/confluent-cloud-promo-disclaimer/?utm_source=github&utm_medium=demo&utm_campaign=ch.examples_type.community_content.clients-ccloud)).


### Advanced usage

You may explicitly set the cloud provider and region. For example:

```bash
CLUSTER_CLOUD=aws CLUSTER_REGION=us-west-2 ./start-cloud.sh
```

Here are the variables and their default values:

| Variable | Default |
| --- | --- |
| CLUSTER_CLOUD | aws |
| CLUSTER_REGION | us-west-2 |
