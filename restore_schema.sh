#!/usr/bin/env bash

# variables
DBNAME='sabyasachi';
TMP_DB='postgres';
HOST='localhost';
PORT='5432';
USER='postgres';
ROLE=$USER;
BIN_DIR='C:\tools\PostgreSQL.9.5\bin';
SCHEMA_FILE="C:\\Users\\Raja\\Desktop\\AppSquad\\syncPGSchema\\$DBNAME.schema.sql";
BACKUP_FILE="C:\\Users\\Raja\\Desktop\\AppSquad\\syncPGSchema\\$DBNAME.all.bak";

# set password for all Pg commands
PGPASSWORD=password;

# dump current db for backup
$BIN_DIR\\pg_dump.exe \
      --dbname=$DBNAME \
      --host=$HOST \
      --port=$PORT \    
      --username=$USER \
      --role=$USER \
      --no-password \
      --format=custom \
      --compress=7 \
      --clean \
      --create \
      --serializable-deferrable \
      --file=$BACKUP_FILE 

	&& 

# delete old .orig and rename current db
$BIN_DIR\\bin\\psql.exe
      --dbname=$TMP_DB \
      --host=$HOST \
      --port=$PORT \
      --username=$USER \
      --role=$USER \
      --no-password \
      --command="
      		BEGIN TRANSACTION; \
      		DROP DATABASE IF EXISTS $DBNAME.orig; \
     		ALTER DATABASE $DBNAME RENAME TO $DBNAME.orig; \
     		END TRANSACTION;
     	"

	&& 

	(	

		# restore db schema from new sql(text) file received from git
		$BIN_DIR\\bin\\psql.exe \
		      --dbname=$TMP_DB \
		      --host=$HOST \
		      --port=$PORT \
		      --username=$USER \
		      --role=$USER \
		      --no-password \
		      --single-transaction \
		      --pset='ON_ERROR_STOP=on' \
		      --file=$SCHEMA_FILE

			&& 

		# restore data from recent dump
		$BIN_DIR\\bin\\pg_restore.exe \
		      --dbname=$DBNAME \
		      --host=$HOST \
		      --port=$PORT \
		      --username=$USER \
		      --role=$USER \
		      --no-password \
		      --format=custom \
		      --data-only \
		      --superuser=$USER \
		      --disable-triggers \
		      --single-transaction \
		      --exit-on-error \
		      --clean \
		      $BACKUP_FILE 

		exit 0;
	)

	||

	(

		# if any of the above fails rename orig	
		$BIN_DIR\\bin\\psql.exe
		      --dbname=$TMP_DB \
		      --host=$HOST \
		      --port=$PORT \
		      --username=$USER \
		      --role=$USER \
		      --no-password \
		      --command="
		      		BEGIN TRANSACTION; \
		      		DROP DATABASE IF EXISTS $DBNAME; \
		     		ALTER DATABASE $DBNAME.orig RENAME TO $DBNAME; \
		     		END TRANSACTION;
		     	"

		exit 1;
	)	
