#!/usr/bin/env bash
# ****************************************************************************
#	see README.md for complete setup instructions. read README first!
#	Else, modify the following variables, 
#		then place file where post-merge git-hook can find it
# ***************************************************************************/

# variables
DBNAME='test_db';
TMP_DB='postgres';
HOST='localhost';
PORT='5432';
USER='postgres';
ROLE=$USER;
BIN_DIR='C:\tools\PostgreSQL.9.5\bin';
WORK_DIR="C:\\Users\\postgres\\Documents\\syncPGSchema";
OUT_FILE="$WORK_DIR\\tmp\\$DBNAME.out";
SCHEMA_FILE="$WORK_DIR\\sqls\\$DBNAME.schema.sql";
BACKUP_FILE="$WORK_DIR\\sqls\\$DBNAME.all.bak";
# set password for all Pg commands
# PGPASSWORD=password; # should not need this anymore, added test_db to pgpass.conf

############################################################################

RETVAL=1
echo
{
	echo "dump all of '$DBNAME' to '$BACKUP_FILE'";
	$BIN_DIR\\pg_dump.exe \
	  --dbname=$DBNAME \
	  --host=$HOST \
	  --port=$PORT \
	  --username=$USER \
	  --role=$USER \
	  --no-password \
	  --format=custom \
	  --compress=7 \
	  --serializable-deferrable \
	  --file=$BACKUP_FILE; 
	if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
} && {
	echo "rename '$DBNAME' to '${DBNAME}_orig'";
	{
		echo "	disconnect all from '${DBNAME}_orig'";
		$BIN_DIR\\psql.exe \
		  --dbname=$TMP_DB \
		  --host=$HOST \
		  --port=$PORT \
		  --username=$USER \
		  --no-password \
		  --echo-errors \
		  --output=$OUT_FILE \
		  --command="
		  SELECT pg_terminate_backend(pg_stat_activity.pid)
			FROM pg_stat_activity
			WHERE pg_stat_activity.datname = '${DBNAME}_orig'
	  			AND pid <> pg_backend_pid();";
		if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
	} && { 
		echo "	drop '${DBNAME}_orig'";
		$BIN_DIR\\psql.exe \
		  --dbname=$TMP_DB \
		  --host=$HOST \
		  --port=$PORT \
		  --username=$USER \
		  --no-password \
		  --echo-errors \
		  --output=$OUT_FILE \
		  --command="DROP DATABASE IF EXISTS ${DBNAME}_orig;";
	 	if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
	} && { 
		echo "	disconnect all from '$DBNAME'";
		$BIN_DIR\\psql.exe \
		  --dbname=$TMP_DB \
		  --host=$HOST \
		  --port=$PORT \
		  --username=$USER \
		  --no-password \
		  --echo-errors \
		  --output=$OUT_FILE \
		  --command="
		  SELECT pg_terminate_backend(pg_stat_activity.pid)
			FROM pg_stat_activity
			WHERE pg_stat_activity.datname = '${DBNAME}'
	  			AND pid <> pg_backend_pid();";
		if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
	} && { 
		echo "	rename '$DBNAME' to '${DBNAME}_orig'";
		$BIN_DIR\\psql.exe \
		  --dbname=$TMP_DB \
		  --host=$HOST \
		  --port=$PORT \
		  --username=$USER \
		  --no-password \
		  --echo-errors \
		  --output=$OUT_FILE \
		  --command="ALTER DATABASE ${DBNAME} RENAME TO ${DBNAME}_orig;";
		if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
	}
} && { 
	{
		echo "restore '$DBNAME'";
		{  
			echo "	create '$DBNAME'";
			$BIN_DIR\\psql.exe \
			  --dbname=$TMP_DB \
			  --host=$HOST \
			  --port=$PORT \
			  --username=$USER \
			  --no-password \
			  --echo-errors \
			  --output=$OUT_FILE \
			  --command="CREATE DATABASE ${DBNAME};";
		} && {
			echo '	restore db schema from new sql(text) file received from git';
			$BIN_DIR\\psql.exe \
			      --dbname=$DBNAME \
			      --host=$HOST \
			      --port=$PORT \
			      --username=$USER \
			      --no-password \
				  --echo-errors \
				  --output=$OUT_FILE \
			      --set='ON_ERROR_STOP' \
			      --file=$SCHEMA_FILE; 
			if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
		} && {
			echo 'restore data from recent dump';
			$BIN_DIR\\pg_restore.exe \
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
			      $BACKUP_FILE;
			false;
			if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
		} && RETVAL=0;
	} || {  
	echo "if restore schema or restore data fails, rename '${DBNAME}_orig' to '${DBNAME}'";
	{
		echo "	disconnect all from '${DBNAME}'";
		$BIN_DIR\\psql.exe \
		  --dbname=$TMP_DB \
		  --host=$HOST \
		  --port=$PORT \
		  --username=$USER \
		  --no-password \
		  --echo-errors \
		  --output=$OUT_FILE \
		  --command="
		  SELECT pg_terminate_backend(pg_stat_activity.pid)
			FROM pg_stat_activity
			WHERE pg_stat_activity.datname = '${DBNAME}'
	  			AND pid <> pg_backend_pid();";
		if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
	} && { 
		echo "	drop '${DBNAME}'";
		$BIN_DIR\\psql.exe \
		  --dbname=$TMP_DB \
		  --host=$HOST \
		  --port=$PORT \
		  --username=$USER \
		  --no-password \
		  --echo-errors \
		  --output=$OUT_FILE \
		  --command="DROP DATABASE IF EXISTS ${DBNAME};";
	 	if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
	} && { 
		echo "	disconnect all from '$DBNAME_orig'";
		$BIN_DIR\\psql.exe \
		  --dbname=$TMP_DB \
		  --host=$HOST \
		  --port=$PORT \
		  --username=$USER \
		  --no-password \
		  --echo-errors \
		  --output=$OUT_FILE \
		  --command="
		  SELECT pg_terminate_backend(pg_stat_activity.pid)
			FROM pg_stat_activity
			WHERE pg_stat_activity.datname = '${DBNAME}_orig'
	  			AND pid <> pg_backend_pid();";
		if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
	} && { 
		echo "	rename '${DBNAME}_orig' to '${DBNAME}'";
		$BIN_DIR\\psql.exe \
		  --dbname=$TMP_DB \
		  --host=$HOST \
		  --port=$PORT \
		  --username=$USER \
		  --no-password \
		  --echo-errors \
		  --output=$OUT_FILE \
		  --command="ALTER DATABASE ${DBNAME}_orig RENAME TO ${DBNAME};";
		if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
	}
	} || {
		echo "if rename orig fails, restore all from dump '$BACKUP_FILE'";
		$BIN_DIR\\pg_restore.exe \
		      --dbname=$DBNAME \
		      --host=$HOST \
		      --port=$PORT \
		      --username=$USER \
		      --role=$USER \
		      --no-password \
		      --format=custom \
		      --superuser=$USER \
		      --disable-triggers \
		      --single-transaction \
		      --exit-on-error \
		      $BACKUP_FILE;
		if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
	} || {
		echo "all automated restore attempts have failed; restore '$DBNAME' manually now!";
		CMD /C eventcreate /ID 1 /L APPLICATION /T WARNING  /SO syncPgSchema /D "all automated restore attempts have failed; restore '$DBNAME' manually now!"
	}
}
echo 'exiting with '$RETVAL' . . .';
exit $RETVAL;

###########################################################################

# following is the if-then-else logic (using shell && and ||) for calling 
# the Post dump and restore commands to apply a new schema from a text file

# the following is no longer the same as above;
# think of converting to seperate of functions, 
#	and a more readable if-then-else tree

# RETVAL=1
# echo
# {
# 	echo 'dump current db for backup';
# 	if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
# } && { 
# 	echo 'delete old .orig and rename current db';
# 	if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
# } && { 
# 	{
# 		{  
# 			echo 'restore db schema from new sql(text) file received from git';
# 			if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
# 		} && {
# 			echo 'restore data from recent dump';
# 			false;
# 			if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
# 		} && RETVAL=0;
# 	} || {  
# 		echo 'if restore schema or restore data fails, rename orig';	
# 			false;
# 		if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
# 	} || {
# 		echo 'if rename orig fails, restore from dump';	
# 			false;
# 		if [ $? != 0 ] ; then echo '	. . . failed !'; false; fi;
# 	} || {
# 		echo "all automated restore attempts failed; restore '$DBNAME' manually !";
# 	}
# }
# echo 'exiting with '$RETVAL' . . .';
# exit $RETVAL;

