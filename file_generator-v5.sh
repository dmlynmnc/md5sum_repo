#!/bin/bash
# dmancia
# file_generator.sh
# 08-03-2025
# 08-25-2025
# 09-01-2025


Red='\033[0;31m'
Clear='\033[0m'
Green='\033[0;32m'
White='\033[1;0m'
BWhite='\033[1;37m'
Yellow='\033[1;33m'
Cyan='\033[1;36m'

## Get the current date and time
TIMESTAMP=$(date +"%Y-%m-%d-%H%M%S")

# Base directory where all output files will be stored.
BASE_DIR="/home/oracle/checksum"

## Log file to capture all the output
LOG_FILE="${BASE_DIR}/checksum_recorder.log"


## Output file where the checksums will be stored, with a timestamp.
OUTPUT_FILE="${BASE_DIR}/hashfile_${TIMESTAMP}.txt"


## Create the base directory if it does not exist.
function check_create_dir () {
    if [ ! -d "${BASE_DIR}" ]; then
        mkdir -p "${BASE_DIR}"
        echo -e "${White}Created directory: ${Green}${BASE_DIR}${Clear}" | tee -a ${LOG_FILE}
    else
        echo -e "${White}Checksum Directory already exists: ${Green}${BASE_DIR}${Clear}" | tee -a ${LOG_FILE}
    fi
}


GRID_HOME=`cat /etc/oratab|grep "+ASM" |awk '{print $1}'|cut -f2 -d":"`
HOST_FQDN=$(host $(hostname -i) | awk '{print $5}' | grep -v TCP | sed 's/\.$//')
for dbsid in $( ps -ef | grep "ora_pmon_" | grep -v grep |grep -v ASM |grep -v ORCL | cut -d'_' -f 3 | grep -v ^+ ) ; do
export ORACLE_SID=$dbsid;
done
SQLPLUS="${ORACLE_HOME}/bin/sqlplus"



function list_db_wallet() {
    ## Query for wallet directory
    TDE_DIR=$($SQLPLUS -s / as sysdba <<EOF
set heading off feedback off echo off pagesize 0
select WRL_PARAMETER from v\$encryption_wallet where WRL_PARAMETER is not null;
EOF
    )
    ## Trim whitespace
    TDE_DIR=$(echo "$TDE_DIR" | xargs)
    
    if [[ -z "$TDE_DIR" ]]; then
        echo "No db tde wallet directory found."  | tee -a ${OUTPUT_FILE} | tee -a ${LOG_FILE}
        return 1
    fi
    ## List wallet files if directory exists
    if [[ -d "$TDE_DIR" ]]; then
        db_wallet_files=$(find "$TDE_DIR" -maxdepth 1 -type f \( -name "ewallet.p12" -o -name "cwallet.sso" \))
        if [[ -n "$db_wallet_files" ]]; then
            while read -r file; do
                md5sum "$file" | tee -a ${OUTPUT_FILE} | tee -a ${LOG_FILE}
            # Reads the contents of the variable db_wallet_files line by line
            done <<< "$db_wallet_files"
        else
            echo "No db wallet files."  | tee -a ${OUTPUT_FILE} | tee -a ${LOG_FILE}
        fi
    else
        echo "Directory $TDE_DIR does not exist."  | tee -a ${OUTPUT_FILE} | tee -a ${LOG_FILE}
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
        echo "GG            : ${is_gginstalled}"  | tee -a ${OUTPUT_FILE} | tee -a ${LOG_FILE}
        flag=1
    else
        if [[ "$dbfs_mountpt" == /u10* ]]; then
            is_gginstalled="Yes"
        fi
        echo "GG            : ${is_gginstalled} Node: $dbfs_node"  | tee -a ${OUTPUT_FILE} | tee -a ${LOG_FILE}
    fi
}

function list_gg_wallet() {
    if [[ "$is_gginstalled" == "Yes" ]]; then
        gg_wallet_files=$(find "$dbfs_mountpt" -type f \( -name "ewallet.p12" -o -name "cwallet.sso" \))
        if [[ -n "$gg_wallet_files" ]]; then
            while read -r file; do
                md5sum "$file" | tee -a ${OUTPUT_FILE} | tee -a ${LOG_FILE}
            done <<< "$gg_wallet_files" 
        else
            echo "There are no gg wallet files." | tee -a ${OUTPUT_FILE} | tee -a ${LOG_FILE}
        fi
    else
        echo "DBFS not mounted, no gg wallet files to checksum." | tee -a ${OUTPUT_FILE} | tee -a ${LOG_FILE}
    fi
}




function compare_hash_files () {
    echo -e "${Green}Executing wallet comparison...${Clear}" | tee -a ${LOG_FILE}
    ## Find the two most recent checksum files.
    ## `ls -t` sorts files by modification time, newest first.
    mapfile -t HASH_FILES < <(ls -t "${BASE_DIR}"/hashfile_*.txt | head -n 2)
    if [ "${#HASH_FILES[@]}" -lt 2 ]; then
        echo -e "${Red}Not enough hash files to perform a comparison. At least two files are required.${Clear}" | tee -a ${LOG_FILE}
        return 1
    fi

    ## The newest file is the current one, the second newest is the previous.
    CURRENT_FILE="${HASH_FILES[0]}"
    PREVIOUS_FILE="${HASH_FILES[1]}"
    echo -e "${White}Comparing these files:${Green}${PREVIOUS_FILE}${White} and ${Green}${CURRENT_FILE}${Clear}" | tee -a ${LOG_FILE}

	# --- Initialize counters ---
	local ADDED=0
	local MODIFIED=0
	local REMOVED=0
	
	declare -A current_checksums previous_checksums
	
	# Only read lines with two space delimiters & files starting with / 
	get_checksum_lines() {
	    grep -E "^[0-9a-fA-F]{32}  /" "$1"
	}
	
	# Populate previous_checksums array
	while IFS='  ' read -r checksum filepath; do
	    [ -z "$filepath" ] && continue
	    previous_checksums["$filepath"]="$checksum"
	done < <(get_checksum_lines "$PREVIOUS_FILE")
	
	# Populate current_checksums array
	while IFS='  ' read -r checksum filepath; do
	    [ -z "$filepath" ] && continue
	    current_checksums["$filepath"]="$checksum"
	done < <(get_checksum_lines "$CURRENT_FILE")
	
	# Comparison
	for filename in "${!current_checksums[@]}"; do
	    if [[ -z "${previous_checksums["$filename"]}" ]]; then
	    	echo -e "${Yellow}ADDED: $filename${Clear}" | tee -a ${LOG_FILE}
	        ((ADDED++))
	    elif [[ "${current_checksums["$filename"]}" != "${previous_checksums["$filename"]}" ]]; then
	    	 echo -e "${Yellow}MODIFIED: $filename" | tee -a ${LOG_FILE}
             echo -e "  Previous: ${previous_checksums["$filename"]}" | tee -a ${LOG_FILE}
             echo -e "  Current : ${current_checksums["$filename"]}" | tee -a ${LOG_FILE}
	        ((MODIFIED++))
	    fi
	done
	
	for filename in "${!previous_checksums[@]}"; do
	    if [[ -z "${current_checksums["$filename"]}" ]]; then
	    	echo -e "${Yellow}REMOVED: $filename${Clear}" | tee -a ${LOG_FILE}
	        ((REMOVED++))
	    fi
	done
	
	# Summary
	echo
	echo -e "${Green}######################Overall Summary######################${Clear}" | tee -a "${LOG_FILE}"
	if ((ADDED == 0 && MODIFIED == 0 && REMOVED == 0)); then
	    echo -e "${Green}PASSED: ${White} Current and previous checksum files are identical.${Clear}" | tee -a "${LOG_FILE}"
	else
	    echo -e "${Red}FAILED: Files Added: $ADDED  Files Modified: $MODIFIED  Files Removed: $REMOVED${Clear}" | tee -a "${LOG_FILE}"
	fi

}


# CLEANUP AND EXECUTION

function cleanup_old_hashfiles () {
    local old_files
    # Find files older than 60 days and delete them.
    old_files=$(find "${BASE_DIR}" -type f -name "hashfile_*.txt" -mtime +60 -print)

    if [ -z "${old_files}" ]; then
        echo -e "${White}No hash files older than 60 days found for cleanup.${Clear}" | tee -a ${LOG_FILE}
        return
    fi

    echo -e "${White}Cleaning up hash files older than 60 days...${Clear}" | tee -a ${LOG_FILE}
    echo "${old_files}" | while read -r file; do
        rm -f "$file"
        echo -e "${White}Removed old hash file: ${Red}${file}${Clear}" | tee -a ${LOG_FILE}
    done
}



### output summary
function summary_print () {
echo -e "${Red}___________________________________________________________________________________________________________________________________${Clear}" | tee -a "${LOG_FILE}"
echo -e "Execution date: ${TIMESTAMP}"   | tee -a ${OUTPUT_FILE} | tee -a ${LOG_FILE}
echo -e "Server name   : ${HOST_FQDN}"   | tee -a ${OUTPUT_FILE} | tee -a ${LOG_FILE}
check_create_dir
gg_validate 
echo -e "Files         :"  | tee -a ${OUTPUT_FILE} | tee -a ${LOG_FILE}
list_db_wallet 
list_gg_wallet 
compare_hash_files
cleanup_old_hashfiles
}


summary_print
















