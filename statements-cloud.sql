CREATE STREAM GUESSES (username VARCHAR,  game_id VARCHAR, guess VARCHAR, answer VARCHAR, tries INT, win VARCHAR, timestamp VARCHAR) WITH (KAFKA_TOPIC='guesses', VALUE_FORMAT='JSON');
CREATE STREAM REGISTRATIONS (firstname VARCHAR, lastname VARCHAR, jobtitle VARCHAR, company VARCHAR, workemail VARCHAR, mobile VARCHAR, consent VARCHAR, timestamp VARCHAR) WITH (KAFKA_TOPIC=‘registrations’, VALUE_FORMAT=‘JSON’);
CREATE STREAM GAME (game_id VARCHAR, username VARCHAR, answer VARCHAR, tries INT, winstreak INT, avgtries DECIMAL(3,2), timestamp VARCHAR) WITH (KAFKA_TOPIC='game', VALUE_FORMAT='JSON');
CREATE TABLE MAX_WIN_STREAM WITH (KAFKA_TOPIC='max-win-streak', PARTITIONS=1, REPLICAS=3) AS SELECT GAME.USERNAME USERNAME, MAX(GAME.WINSTREAK) MAX_WIN_STREAK FROM GAME GAME GROUP BY GAME.USERNAME EMIT CHANGES;
CREATE STREAM REGISTRATIONS_OBFUSCATED WITH (KAFKA_TOPIC='registrations_obfuscated', PARTITIONS=1, REPLICAS=3, VALUE_FORMAT='JSON') AS SELECT MASK_KEEP_RIGHT(REGISTRATIONS.FIRSTNAME, 3) FIRSTNAME, MASK_KEEP_RIGHT(REGISTRATIONS.LASTNAME, 3) LASTNAME, REGISTRATIONS.COMPANY COMPANY, MASK_KEEP_RIGHT(REGISTRATIONS.WORKEMAIL, 3) WORKEMAIL, REGISTRATIONS.MOBILE MOBILE, REGISTRATIONS.CONSENT CONSENT, REGISTRATIONS.TIMESTAMP TIMESTAMP FROM REGISTRATIONS REGISTRATIONS EMIT CHANGES;
CREATE OR REPLACE TABLE GUESS_CHANGE WITH (KAFKA_TOPIC='guess-change', PARTITIONS=1, REPLICAS=3, VALUE_FORMAT='JSON_SR') AS SELECT GUESSES.USERNAME USERNAME, LATEST_BY_OFFSET(GUESSES.GAME_ID, 2) LAST_GAME_ID, LATEST_BY_OFFSET(GUESSES.WIN, 2) LAST_WIN, LATEST_BY_OFFSET(GUESSES.TRIES, 2) LAST_TRIES FROM GUESSES GUESSES GROUP BY GUESSES.USERNAME EMIT CHANGES;
CREATE STREAM FIRST_GUESSES WITH (KAFKA_TOPIC='first_guesses', PARTITIONS=1, REPLICAS=3, VALUE_FORMAT='JSON_SR') AS SELECT GUESSES.GAME_ID GAME_ID, GUESSES.GUESS FIRST_GUESS FROM GUESSES GUESSES WHERE (GUESSES.TRIES = 1) EMIT CHANGES;
CREATE OR REPLACE STREAM LOST_GAMES WITH (KAFKA_TOPIC='lost-games', PARTITIONS=1, REPLICAS=3, VALUE_FORMAT='JSON_SR') AS SELECT * FROM GUESSES GUESSES WHERE ((GUESSES.WIN = 'False') AND (GUESSES.TRIES = 6)) EMIT CHANGES;
CREATE OR REPLACE STREAM WON_GAMES WITH (KAFKA_TOPIC='won-games', PARTITIONS=1, REPLICAS=3, VALUE_FORMAT='JSON_SR') AS SELECT * FROM GUESSES GUESSES WHERE (GUESSES.WIN = 'True') EMIT CHANGES;
CREATE OR REPLACE TABLE ABANDONED_GAMES WITH (KAFKA_TOPIC='abandoned_games', PARTITIONS=1, REPLICAS=3, VALUE_FORMAT='JSON_SR') AS SELECT GUESS_CHANGE.USERNAME KEY, GUESS_CHANGE.LAST_GAME_ID[1] ABANDONED_GAME, AS_VALUE(GUESS_CHANGE.USERNAME) USERNAME, GUESS_CHANGE.LAST_GAME_ID[2] NEW_GAME, GUESS_CHANGE.LAST_WIN[1] ABANDONED_GAME_WIN, GUESS_CHANGE.LAST_TRIES[1] ABANDONED_GAME_TRIES, GUESS_CHANGE.LAST_TRIES[2] NEW_GAME_TRIES FROM GUESS_CHANGE GUESS_CHANGE WHERE (((GUESS_CHANGE.LAST_GAME_ID[1] <> GUESS_CHANGE.LAST_GAME_ID[2]) AND (GUESS_CHANGE.LAST_WIN[1] = 'False')) AND (GUESS_CHANGE.LAST_TRIES[1] < 6)) EMIT CHANGES;
CREATE OR REPLACE TABLE LOSSES_BY_USER WITH (KAFKA_TOPIC='losses-by-user', PARTITIONS=1, REPLICAS=3, VALUE_FORMAT='JSON_SR') AS SELECT LOST_GAMES.USERNAME USERNAME, COUNT(*) LOSSES FROM LOST_GAMES LOST_GAMES GROUP BY LOST_GAMES.USERNAME EMIT CHANGES;
CREATE OR REPLACE TABLE WINS_BY_USER WITH (KAFKA_TOPIC='wins-by-user', PARTITIONS=1, REPLICAS=3, VALUE_FORMAT='JSON_SR') AS SELECT WON_GAMES.USERNAME USERNAME, COUNT(*) WINS FROM WON_GAMES WON_GAMES GROUP BY WON_GAMES.USERNAME EMIT CHANGES;
