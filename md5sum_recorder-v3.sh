#!/bin/bash
# dmancia
# md5sum_recorder.sh
# 08-03-2025
# 08-25-2025
# 08-28-2025

Red='\033[0;31m'
Black='\033[0;30m'
Clear='\033[0m'
Green='\033[0;32m'
Yellow='\033[1;33m'
White='\033[1;37m'
LOG_DATE=$(date '+%Y-%m-%d-%H%M')


function check_create_dir () {
# Define the mount point and checksum directory
MOUNT_POINT="/var/tmp"
CHECKSUM_DIR="${MOUNT_POINT}/checksum"
OUTPUT_LOG="${CHECKSUM_DIR}/md5sum_recorder.log"
HASH_FILE="${CHECKSUM_DIR}/hashfile_${LOG_DATE}.txt"
MASTER_HASH_FILE="${CHECKSUM_DIR}/master_hashfile.txt"
LIST_FILE="${CHECKSUM_DIR}/listfile.txt"
GG_FILE="${CHECKSUM_DIR}/ggfile.txt"
# Check if the mount point is mounted
if [ -d "$MOUNT_POINT" ] && [ -w "$MOUNT_POINT" ]; then
    echo -e "${Green} $MOUNT_POINT ${White} exists and is writable." | tee -a ${OUTPUT_LOG}
    # Create checksum directory
    if [ ! -d "$CHECKSUM_DIR" ]; then
        mkdir -p "$CHECKSUM_DIR"
        echo -e "${White} Created directory: ${Green} $CHECKSUM_DIR" | tee -a ${OUTPUT_LOG}
    else
        echo -e "${White} Checksum Directory already exists: ${Green} $CHECKSUM_DIR" | tee -a ${OUTPUT_LOG}
    fi
else
  echo -e "${Red} ERROR: Mount point $MOUNT_POINT does not exist or is not writable! ${Clear}" | tee -a "${OUTPUT_LOG}"
  return 1
fi
}

### clean up list_file and gg_file 
function check_remove_file () {
if [ -f "$LIST_FILE" ] && [ -f "$GG_FILE" ] ; then
    # If the file exists, remove it
    rm "$LIST_FILE" 
    rm "$GG_FILE"
    echo -e "${White} File  ${Green} $LIST_FILE ${White} and ${Green} $GG_FILE ${White} were removed successfully." | tee -a ${OUTPUT_LOG}
else
    # If the file does not exist, print message
    echo -e "${White} File  ${Green} $LIST_FILE ${White} and ${Green} $GG_FILE ${White}  does not exist. No action taken." | tee -a ${OUTPUT_LOG}
fi
}


HOST_FQDN=$(host $(hostname -i) | awk '{print $5}' | grep -v TCP | sed 's/\.$//')
for dbsid in $( ps -ef | grep "ora_pmon_" | grep -v grep |grep -v ASM |grep -v ORCL | cut -d'_' -f 3 | grep -v ^+ ) ; do
export ORACLE_SID=$dbsid;
done
SQLPLUS="${ORACLE_HOME}/bin/sqlplus"


### get db wallets
function list_db_wallet () {
TDE_DIR=$($SQLPLUS -s / as sysdba << !
set heading off head off feedback off echo off pagesize 0
select WRL_PARAMETER from v\$encryption_wallet where WRL_PARAMETER is not null;
!
)
DE_WALLET=`ls ${TDE_DIR}ewallet.p12`
DC_WALLET=`ls ${TDE_DIR}cwallet.sso`
}


### get gg wallets
function list_gg_wallet () {
DBFS_MOUNTPT=`df -h |grep "/u10/dbfs/gg"|rev|awk '{print $1}'|rev|sort -u|head -1`
if [[ "$DBFS_MOUNTPT" == "/u10"* ]]; then
  export XX=1
  for i in `find /u10/dbfs/gg*`
        do
          KEY=`echo $i|perl -ne 'if(/^(.*[ce]wallet.[sop12]{3})$/){print "GG wallet file_$ENV{'XX'} : $1\n";}'`
        if [ ! -z "$KEY" ]; then
        PRINT_OP=`echo $KEY`;((XX++))
        echo -e "${PRINT_OP}" >> ${GG_FILE}
        fi
        done
  else
  echo -e "GG wallet file        : No gg wallet found" >> ${GG_FILE}
fi
}


### list of files
function list_files () {
echo -e "Server name           :${HOST_FQDN}" >> ${LIST_FILE}
echo -e "Database Name         :${dbsid}" >> ${LIST_FILE}
echo -e "Database ewallet file :${DE_WALLET}" >> ${LIST_FILE}
echo -e "Database cwallet file :${DC_WALLET}" >> ${LIST_FILE}
echo -e "`cat ${GG_FILE}`" >> ${LIST_FILE}
}


### checksum db and rman files and append to hashfile
function checksum_append_files () {
echo -e "Execution date        : ${LOG_DATE}" >> ${HASH_FILE}
echo -e "Server name           : ${HOST_FQDN}" >> ${HASH_FILE}
echo -e "Database Name         : ${dbsid}" >> ${HASH_FILE}
echo -e "Database ewallet file : `md5sum ${DE_WALLET}` " >> ${HASH_FILE}
echo -e "Database cwallet file : `md5sum ${DC_WALLET}` " >> ${HASH_FILE}
}


### checksum gg files and append to hashfile
function checksum_append_ggfiles () {
GG_WALLET=`cat ${GG_FILE}`
if [[ ${GG_WALLET} == "GG wallet file        : No gg wallet found" ]] ; then
    echo ${GG_WALLET} >> ${HASH_FILE}
    echo -e "${White} There are no gg wallet to be checksum." | tee -a ${OUTPUT_LOG}
else
    CHECKSUM=`cat ${GG_FILE} |grep "GG wallet file" |awk -F":" '{print $2}'`
      count=1
      for file in $CHECKSUM; do
        sum=$(md5sum "$file" | awk '{print $1}')
        echo "GG wallet file_${count} : $sum  $file" >> ${HASH_FILE}
        count=$((count+1))
      done
    echo -e "${White} GG wallet files to be checksum found." | tee -a ${OUTPUT_LOG}
fi
}


### compare hashfile
function compare_hash_files () {
mapfile -t filelist < <(ls ${CHECKSUM_DIR}/hashfile* 2>/dev/null | tail -2)

if [ ${#filelist[@]} -lt 2 ]; then
  echo -e "${Red} Not enough hash files to perform a comparison. At least two hash files are required.${Clear}" | tee -a ${OUTPUT_LOG}
  echo -e "${White} Execute the script again : ${Green} md5sum_recorder.sh " | tee -a ${OUTPUT_LOG}
  return
fi

echo -e "${White} Comparing these files : ${Green} ${filelist[@]} " | tee -a ${OUTPUT_LOG}

OLD_DE_WALLET=$(cat ${filelist[0]} |grep "Database ewallet file"|awk -F":" '{print $2}'|xargs)
OLD_DE_WALLET1=$(echo ${OLD_DE_WALLET}|awk '{print $1}')
##echo $OLD_DE_WALLET1
NEW_DE_WALLET=$(cat ${filelist[1]} |grep "Database ewallet file"|awk -F":" '{print $2}'|xargs)
NEW_DE_WALLET1=$(echo ${NEW_DE_WALLET}|awk '{print $1}')
##echo $NEW_DE_WALLET1

OLD_DC_WALLET=$(cat ${filelist[0]} |grep "Database cwallet file"|awk -F":" '{print $2}'|xargs)
OLD_DC_WALLET1=$(echo ${OLD_DC_WALLET}|awk '{print $1}')
##echo $OLD_DC_WALLET1
NEW_DC_WALLET=$(cat ${filelist[1]} |grep "Database cwallet file"|awk -F":" '{print $2}'|xargs)
NEW_DC_WALLET1=$(echo ${NEW_DC_WALLET}|awk '{print $1}')
##echo $NEW_DC_WALLET1

OLD_NOGG_WALLET=$(grep -c "No gg wallet found" "${filelist[0]}")
##echo $OLD_NOGG_WALLET
NEW_NOGG_WALLET=$(grep -c "No gg wallet found" "${filelist[1]}")
##echo $NEW_NOGG_WALLET

OLD_GG_WALLET=$(cat ${filelist[0]} |grep "GG wallet file_1 :"|awk -F":" '{print $2}'|xargs)
OLD_GG_WALLET1=$(echo ${OLD_GG_WALLET}|awk '{print $1}')
P_OLD_GG_WALLET1=$(echo ${OLD_GG_WALLET}|awk '{print $2}')
##echo $OLD_GG_WALLET1
##echo $P_OLD_GG_WALLET1
NEW_GG_WALLET=$(cat ${filelist[1]} |grep "GG wallet file_1 :"|awk -F":" '{print $2}'|xargs)
NEW_GG_WALLET1=$(echo ${NEW_GG_WALLET}|awk '{print $1}')
##echo $NEW_GG_WALLET1

OLD_GG_WALLET=$(cat ${filelist[0]} |grep "GG wallet file_2 :"|awk -F":" '{print $2}'|xargs)
OLD_GG_WALLET2=$(echo ${OLD_GG_WALLET}|awk '{print $1}')
P_OLD_GG_WALLET2=$(echo ${OLD_GG_WALLET}|awk '{print $2}')
##echo $OLD_GG_WALLET2
##echo $P_OLD_GG_WALLET2
NEW_GG_WALLET=$(cat ${filelist[1]} |grep "GG wallet file_2 :"|awk -F":" '{print $2}'|xargs)
NEW_GG_WALLET2=$(echo ${NEW_GG_WALLET}|awk '{print $1}')
##echo $NEW_GG_WALLET2

OLD_GG_WALLET=$(cat ${filelist[0]} |grep "GG wallet file_3 :"|awk -F":" '{print $2}'|xargs)
OLD_GG_WALLET3=$(echo ${OLD_GG_WALLET}|awk '{print $1}')
P_OLD_GG_WALLET3=$(echo ${OLD_GG_WALLET}|awk '{print $2}')
##echo $OLD_GG_WALLET3
##echo $P_OLD_GG_WALLET3
NEW_GG_WALLET=$(cat ${filelist[1]} |grep "GG wallet file_3 :"|awk -F":" '{print $2}'|xargs)
NEW_GG_WALLET3=$(echo ${NEW_GG_WALLET}|awk '{print $1}')
##echo $NEW_GG_WALLET3

OLD_GG_WALLET=$(cat ${filelist[0]} |grep "GG wallet file_4 :"|awk -F":" '{print $2}'|xargs)
OLD_GG_WALLET4=$(echo ${OLD_GG_WALLET}|awk '{print $1}')
P_OLD_GG_WALLET4=$(echo ${OLD_GG_WALLET}|awk '{print $2}')
##echo $OLD_GG_WALLET4
##echo $P_OLD_GG_WALLET4
NEW_GG_WALLET=$(cat ${filelist[1]} |grep "GG wallet file_4 :"|awk -F":" '{print $2}'|xargs)
NEW_GG_WALLET4=$(echo ${NEW_GG_WALLET}|awk '{print $1}')
##echo $NEW_GG_WALLET4

OLD_GG_WALLET=$(cat ${filelist[0]} |grep "GG wallet file_5 :"|awk -F":" '{print $2}'|xargs)
OLD_GG_WALLET5=$(echo ${OLD_GG_WALLET}|awk '{print $1}')
P_OLD_GG_WALLET5=$(echo ${OLD_GG_WALLET}|awk '{print $2}')
##echo $OLD_GG_WALLET5
##echo $P_OLD_GG_WALLET5
NEW_GG_WALLET=$(cat ${filelist[1]} |grep "GG wallet file_5 :"|awk -F":" '{print $2}'|xargs)
NEW_GG_WALLET5=$(echo ${NEW_GG_WALLET}|awk '{print $1}')
##echo $NEW_GG_WALLET5

OLD_GG_WALLET=$(cat ${filelist[0]} |grep "GG wallet file_6 :"|awk -F":" '{print $2}'|xargs)
OLD_GG_WALLET6=$(echo ${OLD_GG_WALLET}|awk '{print $1}')
P_OLD_GG_WALLET6=$(echo ${OLD_GG_WALLET}|awk '{print $2}')
##echo $OLD_GG_WALLET6
##echo $P_OLD_GG_WALLET6
NEW_GG_WALLET=$(cat ${filelist[1]} |grep "GG wallet file_6 :"|awk -F":" '{print $2}'|xargs)
NEW_GG_WALLET6=$(echo ${NEW_GG_WALLET}|awk '{print $1}')
##echo $NEW_GG_WALLET6

OLD_GG_WALLET=$(cat ${filelist[0]} |grep "GG wallet file_7 :"|awk -F":" '{print $2}'|xargs)
OLD_GG_WALLET7=$(echo ${OLD_GG_WALLET}|awk '{print $1}')
P_OLD_GG_WALLET7=$(echo ${OLD_GG_WALLET}|awk '{print $2}')
##echo $OLD_GG_WALLET7
##echo $P_OLD_GG_WALLET7
NEW_GG_WALLET=$(cat ${filelist[1]} |grep "GG wallet file_7 :"|awk -F":" '{print $2}'|xargs)
NEW_GG_WALLET7=$(echo ${NEW_GG_WALLET}|awk '{print $1}')
##echo $NEW_GG_WALLET7

OLD_GG_WALLET=$(cat ${filelist[0]} |grep "GG wallet file_8 :"|awk -F":" '{print $2}'|xargs)
OLD_GG_WALLET8=$(echo ${OLD_GG_WALLET}|awk '{print $1}')
P_OLD_GG_WALLET8=$(echo ${OLD_GG_WALLET}|awk '{print $2}')
##echo $OLD_GG_WALLET8
##echo $P_OLD_GG_WALLET8
NEW_GG_WALLET=$(cat ${filelist[1]} |grep "GG wallet file_8 :"|awk -F":" '{print $2}'|xargs)
NEW_GG_WALLET8=$(echo ${NEW_GG_WALLET}|awk '{print $1}')
##echo $NEW_GG_WALLET8

OLD_GG_WALLET=$(cat ${filelist[0]} |grep "GG wallet file_9 :"|awk -F":" '{print $2}'|xargs)
OLD_GG_WALLET9=$(echo ${OLD_GG_WALLET}|awk '{print $1}')
P_OLD_GG_WALLET9=$(echo ${OLD_GG_WALLET}|awk '{print $2}')
##echo $OLD_GG_WALLET9
##echo $P_OLD_GG_WALLET9
NEW_GG_WALLET=$(cat ${filelist[1]} |grep "GG wallet file_9 :"|awk -F":" '{print $2}'|xargs)
NEW_GG_WALLET9=$(echo ${NEW_GG_WALLET}|awk '{print $1}')
##echo $NEW_GG_WALLET9

OLD_GG_WALLET=$(cat ${filelist[0]} |grep "GG wallet file_10 :"|awk -F":" '{print $2}'|xargs)
OLD_GG_WALLET10=$(echo ${OLD_GG_WALLET}|awk '{print $1}')
P_OLD_GG_WALLET10=$(echo ${OLD_GG_WALLET}|awk '{print $2}')
##echo $OLD_GG_WALLET10
##echo $P_OLD_GG_WALLET10
NEW_GG_WALLET=$(cat ${filelist[1]} |grep "GG wallet file_10 :"|awk -F":" '{print $2}'|xargs)
NEW_GG_WALLET10=$(echo ${NEW_GG_WALLET}|awk '{print $1}')
##echo $NEW_GG_WALLET10

local any_failed=0

if [ "${OLD_DE_WALLET1}" = "${NEW_DE_WALLET1}" ]; then
  echo -e "${White} Database ewallet file comparison -> ${Green} PASSED! ${Yellow}${DE_WALLET} ${Clear}" | tee -a ${OUTPUT_LOG}
else
  echo -e "${White} Database ewallet file comparison ${Red} FAILED! PLS CHECK! ${Yellow}${DE_WALLET} ${Clear}"  | tee -a ${OUTPUT_LOG}
  any_failed=1
fi

if [ "${OLD_DC_WALLET1}" = "${NEW_DC_WALLET1}" ]; then
  echo -e "${White} Database cwallet file comparison -> ${Green} PASSED! ${Yellow}${DC_WALLET} ${Clear}"  | tee -a ${OUTPUT_LOG}
else
  echo -e "${White} Database cwallet file comparison ${Red} FAILED! PLS CHECK! ${Yellow}${DC_WALLET} ${Clear}"  | tee -a ${OUTPUT_LOG}
  any_failed=1
fi

### detect No gg wallet found marker in each file
if (( OLD_NOGG_WALLET > 0 && NEW_NOGG_WALLET > 0 )); then
    echo -e "${White} No GG wallets found in either hashed file. Skipping GG wallet comparisons. ${Clear}" | tee -a ${OUTPUT_LOG}
    if [ $any_failed -eq 0 ]; then
    echo -e "${White} ############## Overall Comparison Summary: ${Green} PASSED ${White} ############## ${Clear}" | tee -a ${OUTPUT_LOG}
    else
    echo -e "${White} ############## Overall Comparison Summary: ${Red} FAILED ${White} ############## ${Clear}" | tee -a ${OUTPUT_LOG}
    fi
    return
elif (( OLD_NOGG_WALLET > 0 && NEW_NOGG_WALLET == 0 )); then
    echo -e "${Red} GG wallet(s) detected in the new file but not in the old file! ${Clear}" | tee -a ${OUTPUT_LOG}
    any_failed=1   
    if [ $any_failed -eq 0 ]; then
    echo -e "${White} ############## Overall Comparison Summary: ${Green} PASSED ${White} ############## ${Clear}" | tee -a ${OUTPUT_LOG}
    else
    echo -e "${White} ############## Overall Comparison Summary: ${Red} FAILED ${White} ############## ${Clear}" | tee -a ${OUTPUT_LOG}
    fi
    return
elif (( NEW_NOGG_WALLET > 0 && OLD_NOGG_WALLET == 0 )); then
    echo -e "${Red} GG wallet(s) detected in the old file but not in the new file! ${Clear}" | tee -a ${OUTPUT_LOG}
    any_failed=1   
    if [ $any_failed -eq 0 ]; then
    echo -e "${White} ############## Overall Comparison Summary: ${Green} PASSED ${White} ############## ${Clear}" | tee -a ${OUTPUT_LOG}
    else
    echo -e "${White} ############## Overall Comparison Summary: ${Red} FAILED ${White} ############## ${Clear}" | tee -a ${OUTPUT_LOG}
    fi
    return
else

if [ "${OLD_GG_WALLET1}" = "${NEW_GG_WALLET1}" ]; then
  echo -e "${White} GG wallet file1 comparison -> ${Green} PASSED! ${Yellow} `echo ${P_OLD_GG_WALLET1}` ${Clear}" | tee -a ${OUTPUT_LOG}
else
  echo -e "${White} GG wallet file1 comparison ${Red} FAILED! PLS CHECK! ${Yellow} `echo ${P_OLD_GG_WALLET1}` ${Clear}" | tee -a ${OUTPUT_LOG}
  any_failed=1
fi

if [ "${OLD_GG_WALLET2}" = "${NEW_GG_WALLET2}" ]; then
  echo -e "${White} GG wallet file2 comparison -> ${Green} PASSED! ${Yellow} `echo ${P_OLD_GG_WALLET2}` ${Clear}"  | tee -a ${OUTPUT_LOG}
else
  echo -e "${White} GG wallet file2 comparison ${Red} FAILED! PLS CHECK! ${Yellow} `echo ${P_OLD_GG_WALLET2}` ${Clear}"  | tee -a ${OUTPUT_LOG}
  any_failed=1
fi

if [ "${OLD_GG_WALLET3}" = "${NEW_GG_WALLET3}" ]; then
  echo -e "${White} GG wallet file3 comparison -> ${Green} PASSED! ${Yellow} `echo ${P_OLD_GG_WALLET3}` ${Clear}" | tee -a ${OUTPUT_LOG}
else
  echo -e "${White} GG wallet file3 comparison ${Red} FAILED! PLS CHECK! ${Yellow} `echo ${P_OLD_GG_WALLET3}` ${Clear}" | tee -a ${OUTPUT_LOG}
  any_failed=1
fi

if [ "${OLD_GG_WALLET4}" = "${NEW_GG_WALLET4}" ]; then
  echo -e "${White} GG wallet file4 comparison -> ${Green} PASSED! ${Yellow} `echo ${P_OLD_GG_WALLET4}` ${Clear}"  | tee -a ${OUTPUT_LOG}
else
  echo -e "${White} GG wallet file4 comparison ${Red} FAILED! PLS CHECK! ${Yellow} `echo ${P_OLD_GG_WALLET4}` ${Clear}"  | tee -a ${OUTPUT_LOG}
  any_failed=1
fi

if [ "${OLD_GG_WALLET5}" = "${NEW_GG_WALLET5}" ]; then
  echo -e "${White} GG wallet file5 comparison -> ${Green} PASSED! ${Yellow} `echo ${P_OLD_GG_WALLET5}` ${Clear}"  | tee -a ${OUTPUT_LOG}
else
  echo -e "${White} GG wallet file5 comparison ${Red} FAILED! PLS CHECK! ${Yellow} `echo ${P_OLD_GG_WALLET5}` ${Clear}"  | tee -a ${OUTPUT_LOG}
  any_failed=1
fi

if [ "${OLD_GG_WALLET6}" = "${NEW_GG_WALLET6}" ]; then
  echo -e "${White} GG wallet file6 comparison -> ${Green} PASSED! ${Yellow} `echo ${P_OLD_GG_WALLET6}` ${Clear}"  | tee -a ${OUTPUT_LOG}
else
  echo -e "${White} GG wallet file6 comparison ${Red} FAILED! PLS CHECK! ${Yellow} `echo ${P_OLD_GG_WALLET6}` ${Clear}"  | tee -a ${OUTPUT_LOG}
  any_failed=1
fi

if [ "${OLD_GG_WALLET7}" = "${NEW_GG_WALLET7}" ]; then
  echo -e "${White} GG wallet file7 comparison -> ${Green} PASSED! ${Yellow} `echo ${P_OLD_GG_WALLET7}` ${Clear}"  | tee -a ${OUTPUT_LOG}
else
  echo -e "${White} GG wallet file7  comparison ${Red} FAILED! PLS CHECK! ${Yellow} `echo ${P_OLD_GG_WALLET7}` ${Clear}"  | tee -a ${OUTPUT_LOG}
  any_failed=1
fi

if [ "${OLD_GG_WALLET8}" = "${NEW_GG_WALLET8}" ]; then
  echo -e "${White} GG wallet file8 comparison -> ${Green} PASSED! ${Yellow} `echo ${P_OLD_GG_WALLET8}` ${Clear}"  | tee -a ${OUTPUT_LOG}
else
  echo -e "${White} GG wallet file8 comparison ${Red} FAILED! PLS CHECK! ${Yellow} `echo ${P_OLD_GG_WALLET8}` ${Clear}"  | tee -a ${OUTPUT_LOG}
  any_failed=1
fi

if [ "${OLD_GG_WALLET9}" = "${NEW_GG_WALLET9}" ]; then
  echo -e "${White} GG wallet file9 comparison -> ${Green} PASSED! ${Yellow} `echo ${P_OLD_GG_WALLET9}` ${Clear}"  | tee -a ${OUTPUT_LOG}
else
  echo -e "${White} GG wallet file9 comparison ${Red} FAILED! PLS CHECK! ${Yellow} `echo ${P_OLD_GG_WALLET9}` ${Clear}" | tee -a ${OUTPUT_LOG}
  any_failed=1
fi

if [ "${OLD_GG_WALLET10}" = "${NEW_GG_WALLET10}" ]; then
  echo -e "${White} GG wallet file10 comparison -> ${Green} PASSED! ${Yellow} `echo ${P_OLD_GG_WALLET10}` ${Clear}" | tee -a ${OUTPUT_LOG}
else
  echo -e "${White} GG wallet file10 comparison ${Red} FAILED! PLS CHECK! ${Yellow} `echo ${P_OLD_GG_WALLET10}` ${Clear}"  | tee -a ${OUTPUT_LOG}
  any_failed=1
fi

if [ $any_failed -eq 0 ]; then
  echo -e "${White} ############## Overall Comparison Summary: ${Green} PASSED ${White} ############## ${Clear}" | tee -a ${OUTPUT_LOG}
else
  echo -e "${White} ############## Overall Comparison Summary: ${Red} FAILED ${White} ############## ${Clear}" | tee -a ${OUTPUT_LOG}
fi

fi
}

### clean up old hasfiles to prevent /var/tmp/checksum from accumulating old hash files over time
function cleanup_old_hashfiles () {
    local hashfiles
    # Get list of all matching files, sorted by modification time (newest last)
    mapfile -t hashfiles < <(ls -1t ${CHECKSUM_DIR}/hashfile_2* 2>/dev/null)

    # Check if more than 2 files exist
    if [ "${#hashfiles[@]}" -le 2 ]; then
        echo -e "${White} No hash file cleanup needed. Only ${Red} ${#hashfiles[@]} ${White} hash files present." | tee -a ${OUTPUT_LOG}
        return
    fi

    # Retain the two newest, delete the rest
    to_delete=("${hashfiles[@]:2}")
    for file in "${to_delete[@]}"; do
        rm -f "$file"
        echo -e "${White} Removed old hash file: ${Red} $file" | tee -a ${OUTPUT_LOG}
    done
}



check_create_dir
echo -e "${White} Script started: ${Green} $LOG_DATE"  | tee -a ${OUTPUT_LOG}
check_remove_file
list_db_wallet 
list_gg_wallet
list_files
echo -e "${White} List of files saved to ${Green} $LIST_FILE ${White}." | tee -a ${OUTPUT_LOG}
checksum_append_files
checksum_append_ggfiles
echo -e "${White} Checksummed file saved to ${Green} $HASH_FILE ${White}." | tee -a ${OUTPUT_LOG}
cat "$HASH_FILE" >> "$MASTER_HASH_FILE"
echo >> "$MASTER_HASH_FILE" 
echo -e "${White} Master file has been updated ${Green} $MASTER_HASH_FILE ${White}." | tee -a ${OUTPUT_LOG}
compare_hash_files
cleanup_old_hashfiles
echo -e "${White} Script ended: ${Green} $LOG_DATE" | tee -a ${OUTPUT_LOG}





