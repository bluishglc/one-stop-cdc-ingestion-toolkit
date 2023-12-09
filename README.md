
# One-Stop CDC Ingestion Toolkit


加一个 inuse=true|false 配置

## Install

## Profile Ⅰ: MySQL + Confluent Schema Registry + Avro



## Profile Ⅱ: MySQL + Glue Schema Registry + Avro

## Profile Ⅲ:


## Prerequisites


```bash
export APP_NAME='apache-hudi-delta-streamer'
export APP_S3_HOME="s3://$APP_NAME"
export APP_LOCAL_HOME="$HOME/$APP_NAME"

export SCHEMA_REGISTRY_URL='http://10.0.13.30:8085'
export KAFKA_BOOTSTRAP_SERVERS='b-3.oscimskcluster1.6ww5j7.c3.kafka.us-east-1.amazonaws.com:9092,b-1.oscimskcluster1.6ww5j7.c3.kafka.us-east-1.amazonaws.com:9092,b-2.oscimskcluster1.6ww5j7.c3.kafka.us-east-1.amazonaws.com:9092'

export EMR_SERVERLESS_APP_SUBNET_ID='subnet-0a11afe6dbb4df759'
export EMR_SERVERLESS_APP_SECURITY_GROUP_ID='sg-071f18562f41b5804'
export EMR_SERVERLESS_APP_ID='00fbfel40ee59k09'
export EMR_SERVERLESS_EXECUTION_ROLE_ARN='arn:aws:iam::366020657890:role/EMR_SERVERLESS_ADMIN'
```

```bash
kafka-topics.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --list

kafka-console-consumer.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --topic 'osci.mysql-server-3.inventory.orders' --from-beginning

kafka-consumer-groups.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --list
kafka-consumer-groups.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS  --group <group_id>   --topic <topic_name> --reset-offsets --to-datetime 2021-06-25T21:22:39.306 --execute


kafka-topics.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --delete --topic '__amazon_msk_connect.*|_schemas|fullfillment.*|schemahistory.*'
```

### A Source Database

```bash
docker run -it --rm \
    --name mysql \
    -p 3307:3306 \
    -e MYSQL_ROOT_PASSWORD=Admin1234! \
    -e MYSQL_USER=mysqluser \
    -e MYSQL_PASSWORD=Admin1234! \
    debezium/example-mysql:1.0
```

### 

```bash
export BOOTSTRAP_SERVERS='b-3.oscimskcluster1.6ww5j7.c3.kafka.us-east-1.amazonaws.com:9092,b-1.oscimskcluster1.6ww5j7.c3.kafka.us-east-1.amazonaws.com:9092,b-2.oscimskcluster1.6ww5j7.c3.kafka.us-east-1.amazonaws.com:9092'
```

## setup mysql server

### mysql-server-1

```bash
docker run -it --rm \
    --name mysql \
    -p 3307:3306 \
    -e MYSQL_ROOT_PASSWORD=Admin1234! \
    -e MYSQL_USER=mysqluser \
    -e MYSQL_PASSWORD=Admin1234! \
    debezium/example-mysql:1.0
```

### mysql-server-2

```bash
docker run -it --rm \
    --name mysql \
    -p 3308:3306 \
    -e MYSQL_ROOT_PASSWORD=Admin1234! \
    -e MYSQL_USER=mysqluser \
    -e MYSQL_PASSWORD=Admin1234! \
    debezium/example-mysql:1.0
```

## open a mysql client

```bash
docker run -it --rm \
    --name mysqlterm \
    --link mysql \
    --rm mysql:5.7 \
    sh -c 'exec mysql -h"$MYSQL_PORT_3306_TCP_ADDR" -P"$MYSQL_PORT_3306_TCP_PORT" -uroot -p"$MYSQL_ENV_MYSQL_ROOT_PASSWORD"'
```

## start confluent schema registry

### IAM authentication

```bash
docker run -d \
  --net=host \
  --name=confluent-schema-registry \
  -e SCHEMA_REGISTRY_HOST_NAME="confluent-schema-registry" \
  -e SCHEMA_REGISTRY_LISTENERS="http://0.0.0.0:8085" \
  -e SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS="$KAFKA_BOOTSTRAP_SERVERS" \
  -e SCHEMA_REGISTRY_KAFKASTORE_SECURITY_PROTOCOL="SASL_SSL" \
  -e SCHEMA_REGISTRY_KAFKASTORE_SASL_MECHANISM="AWS_MSK_IAM" \
  -e SCHEMA_REGISTRY_KAFKASTORE_SASL_JAAS_CONFIG="software.amazon.msk.auth.iam.IAMLoginModule required;" \
  -e SCHEMA_REGISTRY_KAFKASTORE_SASL_CLIENT_CALLBACK_HANDLER_CLASS="software.amazon.msk.auth.iam.IAMClientCallbackHandler" \
  bluishglc/cp-schema-registry
```

### No authentication

```bash
docker run -d \
  --net=host \
  --name=confluent-schema-registry \
  -e SCHEMA_REGISTRY_HOST_NAME="confluent-schema-registry" \
  -e SCHEMA_REGISTRY_LISTENERS="http://0.0.0.0:8085" \
  -e SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS="$KAFKA_BOOTSTRAP_SERVERS" \
  confluentinc/cp-schema-registry
  
  
cat << EOF > docker-compose.yml
services:
  confluent-schema-registry:
    image: confluentinc/cp-schema-registry
    hostname: confluent-schema-registry
    container_name: confluent-schema-registry
    ports:
      - "8085:8085"
    environment:
      SCHEMA_REGISTRY_HOST_NAME: "confluent-schema-registry"
      SCHEMA_REGISTRY_LISTENERS: "http://0.0.0.0:8085"
      SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: "$KAFKA_BOOTSTRAP_SERVERS"
EOF

# start a new env everytime
docker compose up --force-recreate -V

```

```bash
docker ps -a
# restart a clean environment
containerId=$(docker ps -aqf "name=confluent-schema-registry")
docker container stop $containerId
docker container rm $containerId
docker ps -a
```


## print configs

```bash
osci list-configs
```

## quickstart

```bash
osci quickstart \
    --home-bucket 'one-stop-cdc-ingestion-toolkit' \
    --vpc-id 'vpc-0f137759978aab3c3' \
    --subnet-ids 'subnet-0a11afe6dbb4df759,subnet-0f377f35a3aeed93c,subnet-060cae22e5a2da7a2' \
    --security-group-ids 'sg-071f18562f41b5804' \
    --msk-cluster-name 'msk-cluster-1' \
    --kafka-bootstrap-servers 'b-2.mskcluster2.42919p.c12.kafka.us-east-1.amazonaws.com:9098,b-1.mskcluster2.42919p.c12.kafka.us-east-1.amazonaws.com:9098,b-3.mskcluster2.42919p.c12.kafka.us-east-1.amazonaws.com:9098' \
    --mskc-worker-config-name 'osci-worker-configuration-1' \
    --mskc-worker-config-arn 'arn:aws:kafkaconnect:us-east-1:366020657890:worker-configuration/osci-worker-configuration-1/edd7f188-f26e-4af9-98c7-55ef928d17a5-4' \
```

## configure

```bash
osci configure \
    --home-bucket 'one-stop-cdc-ingestion-toolkit' \
    --vpc-id 'vpc-0f137759978aab3c3' \
    --subnet-ids 'subnet-0a11afe6dbb4df759,subnet-0f377f35a3aeed93c,subnet-060cae22e5a2da7a2' \
    --security-group-ids 'sg-071f18562f41b5804' \
    --msk-cluster-name 'msk-cluster-2' \
    --msk-cluster-arn 'arn:aws:kafka:us-east-1:366020657890:cluster/msk-cluster-2/86b26be7-ed6a-4acf-8f19-04174609f314-12' \
    --kafka-bootstrap-servers 'b-2.mskcluster2.42919p.c12.kafka.us-east-1.amazonaws.com:9098,b-1.mskcluster2.42919p.c12.kafka.us-east-1.amazonaws.com:9098,b-3.mskcluster2.42919p.c12.kafka.us-east-1.amazonaws.com:9098' \
    --mskc-worker-config-name 'osci-worker-configuration-1' \
    --mskc-worker-config-arn 'arn:aws:kafkaconnect:us-east-1:366020657890:worker-configuration/osci-worker-configuration-1/edd7f188-f26e-4af9-98c7-55ef928d17a5-4'

```

## setup

```bash

osci setup-mskc-connector \
    --mskc-connector-name 'osci-connector-mysql-server-1' \
    --mskc-worker-config-name 'osci-worker-configuration-1' \
    --mskc-plugin-name 'osci-plugin-mysql-gsr-avro' \
    --mskc-connector-mcu-count '1' \
    --mskc-connector-worker-count '1' \
    --mskc-connector-database-hostname '10.0.13.30' \
    --mskc-connector-database-port '3307' \
    --mskc-connector-database-user 'root' \
    --mskc-connector-database-password 'Admin1234!' \
    --mskc-connector-database-server-id '223344' \
    --mskc-connector-database-server-name 'mysql-server-1' \
    --mskc-connector-database-include-list 'inventory' \
    --mskc-connector-topic-prefix 'osci.mysql-server-1' \
    --mskc-connector-schema-registry-name 'osci.mysql-server-1' \
    --mskc-connector-schema-history-internal-kafka-topic 'osci.mysql-server-1.schema-history' \
    --mskc-connector-schema-registry-compatibility 'BACKWARD'

```

## backup

```bash

osci setup \
    --mskc-plugin-name 'osci-plugin-mysql-gsr-avro' \
    --mskc-worker-config-name 'osci-worker-configuration-2' \
    --mskc-connector-name 'osci-connector-mysql-server-1' \
    --mskc-connector-mcu-count '1' \
    --mskc-connector-worker-count '1' \
    --mskc-connector-database-hostname '10.0.13.30' \
    --mskc-connector-database-port '3306' \
    --mskc-connector-database-user 'root' \
    --mskc-connector-database-password 'Admin1234!' \
    --mskc-connector-database-server-id '223344' \
    --mskc-connector-database-server-name 'mysql-server-1' \
    --mskc-connector-database-include-list 'cdc_test_db' \
    --mskc-connector-topic-prefix 'osci.db.mysql-server-1' \
    --mskc-connector-schema-registry-name 'osci.db.mysql-server-1' \
    --mskc-connector-schema-history-internal-kafka-topic 'osci.db.mysql-server-1.schema-history' \
    --mskc-connector-schema-registry-compatibility 'BACKWARD'
    
```

## configure s3

```bash
osci configure-s3 --home-bucket 'one-stop-cdc-ingestion-toolkit'
```

## configure vpc

```bash
osci configure-vpc \
    --vpc-id 'vpc-0f137759978aab3c3' \
    --subnet-ids 'subnet-0a11afe6dbb4df759,subnet-0f377f35a3aeed93c,subnet-060cae22e5a2da7a2' \
    --security-group-ids 'sg-071f18562f41b5804'
```

## configure msk cluster

```bash
osci configure-msk-cluster \
    --msk-cluster-name 'msk-cluster-2' \
    --msk-cluster-arn 'arn:aws:kafka:us-east-1:366020657890:cluster/msk-cluster-2/86b26be7-ed6a-4acf-8f19-04174609f314-12' \
    --kafka-bootstrap-servers 'b-2.mskcluster2.42919p.c12.kafka.us-east-1.amazonaws.com:9098,b-1.mskcluster2.42919p.c12.kafka.us-east-1.amazonaws.com:9098,b-3.mskcluster2.42919p.c12.kafka.us-east-1.amazonaws.com:9098'
```

## create msk cluster

### create a msk cluster without authentication

- create

```bash
osci setup-msk-cluster --msk-cluster-name 'osci-msk-cluster-1'
```

- remove

```bash
osci remove-msk-cluster --msk-cluster-name 'osci-msk-cluster-1'

```
### create a msk cluster with IAM authentication

```bash
osci setup-msk-cluster --msk-cluster-name 'osci-msk-cluster-1' --msk-cluster-auth-type 'IAM'
```

## install msk connect plugin

```bash
osci install-mskc-plugin --mskc-plugin-name 'osci-plugin-mysql-gsr-avro'
osci install-mskc-plugin --mskc-plugin-name 'osci-plugin-mysql-confluent-avro'
```

## configure msk connect plugin

```bash
osci configure-mskc-plugin \
    --mskc-plugin-name 'osci-plugin-mysql-gsr-avro' \
    --mskc-plugin-arn 'arn:aws:kafkaconnect:us-east-1:366020657890:custom-plugin/osci-plugin-mysql-gsr-avro/75ca6812-59c9-4fed-996a-3839e7ac14e4-4'
    
osci configure-mskc-plugin --mskc-plugin-name 'osci-plugin-mysql-confluent-avro'
```

## remove msk connect plugin

```bash
osci remove-mskc-plugin --mskc-plugin-name 'osci-plugin-mysql-gsr-avro'
```


## setup msk connect worker-configuration

```bash
osci setup-mskc-worker-config --mskc-worker-config-name 'osci-worker-configuration-1'
```


## add msk connect connector

NOTE: The debezium-mysql-connector only uses a single task, see:
https://debezium.io/documentation/reference/1.8/connectors/mysql.html#mysql-property-tasks-max
So, it does not work with autoscaled capacity mode for Amazon MSK Connect. We should instead
use provisioned capacity mode and set workerCount equal to '1' in our connector configuration.
And also, we have no option like '--mskc-connector-worker-count', it is a hard-coded value: '1'.
But you can assign a higher value for mcuCount via option '--mskc-connector-mcu-count'

### osci-connector-mysql-server-1 (osci-plugin-mysql-gsr-avro)

```bash
osci setup-mskc-connector \
    --mskc-connector-name 'osci-connector-mysql-server-1' \
    --mskc-worker-config-name 'osci-worker-configuration-2' \
    --mskc-plugin-name 'osci-plugin-mysql-gsr-avro' \
    --mskc-connector-mcu-count '1' \
    --mskc-connector-worker-count '1' \
    --mskc-connector-database-hostname '10.0.13.30' \
    --mskc-connector-database-port '3306' \
    --mskc-connector-database-user 'root' \
    --mskc-connector-database-password 'Admin1234!' \
    --mskc-connector-database-server-id '223344' \
    --mskc-connector-database-server-name 'mysql-server-1' \
    --mskc-connector-database-include-list 'cdc_test_db' \
    --mskc-connector-topic-prefix 'osci.db.mysql-server-1' \
    --mskc-connector-schema-registry-name 'osci.db.mysql-server-1' \
    --mskc-connector-schema-history-internal-kafka-topic 'osci.db.mysql-server-1.schema-history' \
    --mskc-connector-schema-registry-compatibility 'BACKWARD'
```


```bash
osci remove-mskc-connector --mskc-connector-name 'osci-connector-mysql-server-1'
```

### osci-connector-mysql-server-2 (osci-plugin-mysql-gsr-avro)

```bash
osci setup-mskc-connector \
    --mskc-connector-name 'osci-connector-mysql-server-2' \
    --mskc-worker-config-name 'osci-worker-configuration-2' \
    --mskc-plugin-name 'osci-plugin-mysql-gsr-avro' \
    --mskc-connector-mcu-count '1' \
    --mskc-connector-worker-count '1' \
    --mskc-connector-database-hostname '10.0.13.30' \
    --mskc-connector-database-port '3308' \
    --mskc-connector-database-user 'root' \
    --mskc-connector-database-password 'Admin1234!' \
    --mskc-connector-database-server-id '223344' \
    --mskc-connector-database-server-name 'mysql-server-2' \
    --mskc-connector-database-include-list 'inventory' \
    --mskc-connector-topic-prefix 'osci.mysql-server-2' \
    --mskc-connector-schema-registry-name 'osci.mysql-server-2' \
    --mskc-connector-schema-history-internal-kafka-topic 'osci.mysql-server-2.schema-history' \
    --mskc-connector-schema-registry-compatibility 'BACKWARD'
```

```bash
osci remove-mskc-connector --mskc-connector-name 'osci-connector-mysql-server-2'
```

### osci-connector-mysql-server-3 (osci-plugin-mysql-confluent-avro)

```bash
osci setup-mskc-connector \
    --mskc-connector-name 'osci-connector-mysql-server-3' \
    --mskc-worker-config-name 'osci-worker-configuration-2' \
    --mskc-plugin-name 'osci-plugin-mysql-confluent-avro' \
    --msk-cluster-name 'osci-msk-cluster-1' \
    --mskc-connector-mcu-count '1' \
    --mskc-connector-worker-count '1' \
    --mskc-connector-database-hostname '10.0.13.30' \
    --mskc-connector-database-port '3307' \
    --mskc-connector-database-user 'root' \
    --mskc-connector-database-password 'Admin1234!' \
    --mskc-connector-database-server-id '223344' \
    --mskc-connector-database-server-name 'mysql-server-3' \
    --mskc-connector-database-include-list 'inventory' \
    --mskc-connector-topic-prefix 'osci.mysql-server-3' \
    --mskc-connector-schema-registry-url 'http://10.0.13.30:8085' \
    --mskc-connector-schema-registry-name 'osci.mysql-server-3' \
    --mskc-connector-schema-history-internal-kafka-topic 'osci.mysql-server-3.schema-history' \
    --mskc-connector-schema-registry-compatibility 'BACKWARD'
```

```bash
osci remove-mskc-connector \
    --mskc-connector-name 'osci-connector-mysql-server-3' \
    --msk-cluster-name 'osci-msk-cluster-1'
```

## find msk connect connector log errors

```bash
osci find-mskc-connector-log-errors --mskc-connector-name 'osci-connector-mysql-server-3'
```

## list kafka topics

```bash
osci list-topics --msk-cluster-name 'osci-msk-cluster-1'
```

## clean kafka topics

```bash
osci clean-topics --msk-cluster-name 'osci-msk-cluster-1'
```

## Kafka Manual Ops

```bash
kafka-console-consumer.sh --consumer.config /home/ec2-user/one-stop-cdc-ingestion-toolkit-1.0/cnf/kafka-client.properties \
    --bootstrap-server $(jq -r '.MskCluster.KafkaBootstrapServers' /home/ec2-user/one-stop-cdc-ingestion-toolkit-1.0/cnf/osci-conf.json) \
    --from-beginning --topic osci.db.mysql-server-1.cdc_test_db.person
```

 Note: for unauthenticated client authentication,
 The EncryptionInTransit could be PLAINTEXT or TLS,
 If we do NOT set EncryptionInTransit explicitly,
 The TLS will be enabled by default.
 Here, we don't want to add an extra param like `--encryption PLAINTEXT|TLS`,
 To be simple, we let unauthenticated client authentication always use PLAINTEXT,
 If you need a cluster with unauthenticated client authentication & TLS encryption,
 you can replace following `populatePlaintextEncryptionInTransit` with `populateTlsEncryptionInTransit`

 Note: for IAM, SASL/SCRAM, TLS authentication, TLS encryption is REQUIRED!
 Actually, we don't need configure TLS for IAM explicitly, because TLS encryption is always
 enabled by default, here, we set it explicitly just for human readable.


```sql
drop database if exists cdc_test_db;
create database if not exists cdc_test_db;
drop table if exists cdc_test_db.person;
create table if not exists cdc_test_db.person
(
    firstName    varchar(155)              null,
    lastName     varchar(155)              null,
    age          int                       not null
)charset = utf8mb4;

insert into cdc_test_db.person values ('foo','doe', 18);

-- Backward Test Case 1: 通过

alter table cdc_test_db.person drop column lastName;
insert into cdc_test_db.person values ('foo2', 18);

-- Backward Test Case 2: 通过

alter table cdc_test_db.person add column email varchar(155) null;
insert into cdc_test_db.person values ('foo1',18, 'abc');

-- Backward Test Case 3: 失败

alter table cdc_test_db.person add column address varchar(155) not null;
insert into cdc_test_db.person values ('foo1',18, 'abc', 'xyz');
```

```bash
# 这部分得存储到配置文件中
# 其他命令行都应该读取配置文件
--config-vpc

--create-kafka-cluster     # 创建成功之后，再将kafka信息写到配置文件中
--configure-kafka-cluster  # 只是将kafka信息写到配置文件中

# 可反复追加多次
--add-database




--kafka-cluster: create | reuse
--kafka-cluzter-name: xxx

--add-database
--database-user
--database-password

--show-all-configs
```
