#!/bin/bash
# dmancia
# file_generator.sh
# 08-03-2025
# 08-25-2025
# 09-01-2025


LOG_DATE=$(date '+%Y-%m-%d-%H%M')

GRID_HOME=`cat /etc/oratab|grep "+ASM" |awk '{print $1}'|cut -f2 -d":"`
HOST_FQDN=$(host $(hostname -i) | awk '{print $5}' | grep -v TCP | sed 's/\.$//')
for dbsid in $( ps -ef | grep "ora_pmon_" | grep -v grep |grep -v ASM |grep -v ORCL | cut -d'_' -f 3 | grep -v ^+ ) ; do
export ORACLE_SID=$dbsid;
done
SQLPLUS="${ORACLE_HOME}/bin/sqlplus"



function list_db_wallet() {
    # Query for wallet directory
    TDE_DIR=$($SQLPLUS -s / as sysdba <<EOF
set heading off feedback off echo off pagesize 0
select WRL_PARAMETER from v\$encryption_wallet where WRL_PARAMETER is not null;
EOF
    )
    # Trim whitespace
    TDE_DIR=$(echo "$TDE_DIR" | xargs)
    
    if [[ -z "$TDE_DIR" ]]; then
        echo "No db tde wallet directory found."
        return 1
    fi
    # List wallet files if directory exists
    if [[ -d "$TDE_DIR" ]]; then
        db_wallet_files=$(find "$TDE_DIR" -maxdepth 1 -type f \( -name "ewallet.p12" -o -name "cwallet.sso" \))
        if [[ -n "$db_wallet_files" ]]; then
            while read -r file; do
                md5sum "$file"
            # Reads the contents of the variable db_wallet_files line by line
            done <<< "$db_wallet_files"
        else
            echo "No db wallet files."
        fi
    else
        echo "Directory $TDE_DIR does not exist."
        return 2
    fi
}



function gg_validate() {
    is_gginstalled="No"
    ## Extract the mountpoint ex. /u10/dbfs/gg
    dbfs_mountpt=$(df -h | grep "/u10/dbfs/gg" | rev | awk '{print $1}' | rev | sort -u | head -1)
    ## Extract the dbfs name  ex. dbfs_mount_v01dbgg_phx3cw
    dbfs_name=$($GRID_HOME/bin/crsctl stat res -t | grep dbfs | head -1)
    ## Extract the node where dbfs is up  ex. d14w31dbgg1
    dbfs_node=$($GRID_HOME/bin/crsctl stat res $dbfs_name |grep STATE  | awk '{print $3}')
    flag=0
    if [[ ! -d "$dbfs_mountpt" ]]; then
        echo "GG            : ${is_gginstalled}"
        flag=1
    else
        if [[ "$dbfs_mountpt" == /u10* ]]; then
            is_gginstalled="Yes"
        fi
        echo "GG            : ${is_gginstalled} Node: $dbfs_node"
    fi
}
function list_gg_wallet() {
    if [[ "$is_gginstalled" == "Yes" ]]; then
        gg_wallet_files=$(find "$dbfs_mountpt" -type f \( -name "ewallet.p12" -o -name "cwallet.sso" \))
        if [[ -n "$gg_wallet_files" ]]; then
            while read -r file; do
                md5sum "$file"
            done <<< "$gg_wallet_files"
        else
            echo "There are no gg wallet files."
        fi
    else
        echo "DBFS not mounted, no gg wallet files to checksum."
    fi
}



### list of files
function summary_print () {
echo -e "Execution date: ${LOG_DATE}" 
echo -e "Server name   : ${HOST_FQDN}" 
gg_validate
echo -e "Files         :" 
list_db_wallet
list_gg_wallet
}


summary_print
