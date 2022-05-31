CREATE OR REPLACE STREAM pageviews WITH (kafka_topic='pageviews', value_format='AVRO');
CREATE OR REPLACE TABLE users (id STRING PRIMARY KEY) WITH (kafka_topic='users', value_format='PROTOBUF');
CREATE OR REPLACE STREAM pageviews_female AS SELECT users.id AS userid, pageid, regionid, gender FROM pageviews LEFT JOIN users ON pageviews.userid = users.id WHERE gender = 'FEMALE';
CREATE OR REPLACE STREAM pageviews_female_like_89 AS SELECT * FROM pageviews_female WHERE regionid LIKE '%_8' OR regionid LIKE '%_9';
CREATE OR REPLACE TABLE pageviews_regions WITH (key_format='JSON') AS SELECT gender, regionid , COUNT(*) AS numusers FROM pageviews_female WINDOW TUMBLING (size 30 second) GROUP BY gender, regionid HAVING COUNT(*) > 1;
CREATE OR REPLACE STREAM accomplished_female_readers WITH (value_format='JSON_SR') AS SELECT * FROM PAGEVIEWS_FEMALE WHERE CAST(SPLIT(PAGEID,'_')[2] as INT) >= 50;

CREATE OR REPLACE STREAM transactions WITH (kafka_topic='transactions', value_format='AVRO');
CREATE OR REPLACE TABLE credit_cards (id STRING PRIMARY KEY) WITH (kafka_topic='credit_cards', value_format='PROTOBUF');

CREATE OR REPLACE STREAM TRANSACTIONS_CARDS_USERS WITH (kafka_topic='transactions_cards_users', value_format='JSON_SR') AS SELECT * FROM TRANSACTIONS LEFT JOIN CREDIT_CARDS ON cast(TRANSACTIONS.card_id AS STRING) = CREDIT_CARDS.id LEFT JOIN USERS ON TRANSACTIONS.user_id = USERS.ID EMIT CHANGES;

CREATE OR REPLACE TABLE BUSY_STORES WITH (kafka_topic='busy_stores', value_format='JSON_SR') AS SELECT STORE_ID, WINDOWSTART AS STARTTIME, WINDOWEND AS ENDTIME, COUNT(*) AS TRANSACTION_COUNT FROM TRANSACTIONS WINDOW TUMBLING (SIZE 10 SECONDS) GROUP BY STORE_ID HAVING COUNT(*) > 2 EMIT CHANGES;

CREATE OR REPLACE STREAM TCU_REGION_9 WITH (kafka_topic='tcu_region_9', value_format='JSON_SR') AS SELECT * FROM TRANSACTIONS_CARDS_USERS WHERE USERS_REGIONID = 'Region_9' EMIT CHANGES;

