#!/usr/bin/ksh
##!/usr/local/bin/ksh93
#Linux use shell: /usr/bin/ksh
#FreeNAS use shell: /usr/local/bin/ksh93
#Copyright 2000 Afan Ottenheimer
# This script is very inode intensive and can use up inodes sooner than actual physical space on a disk unless you are using an inodeess filesystem like ReiserFS

#set -x
VERSION="2.4.0"

#do not assume we run as root
USERNAME=$(whoami)

MAJOR_RSYNC_VERSION=$(rsync --version | grep version | awk '{print $3}' | awk -F . '{print $1}')
RSYNC_VERSION=$(rsync --version | grep version )
if [ "$?" == "127" ]; then 
  echo "ERROR: Requires rsync to be installed and in the path"
  exit 2
fi

OS="linux"
RESULTOS=$(freebsd-version 2>/tmp/backupinator.tmp)
if [ "$?" == "0" ]; then 
  echo "Detected OS as $RESULTOS" > /tmp/backupinator.tmp
  OS="FreeBSD"
fi

#Command Tests
TESTDAY=5
if [ "$OS" == "FreeBSD" ]; then
  SANITY=$(date -v -"${TESTDAY}d" +%Y-%m-%d)
  if [ "$?" == "1" ]; then
    echo "WARNING: date command not working on this OS"
    exit 2
  fi
else
  SANITY=$(date -d "$TESTDAY days ago" +%Y-%m-%d)
  if [ "$?" == "1" ]; then
    echo "WARNING: date command not working on this OS"
    exit 2
  fi
fi

#IFCONFIG=`which ifconfig`
#echo "$IFCONFIG"
#exit;

if [ "$MAJOR_RSYNC_VERSION" -lt 3 ] ; then  
  echo "WARNING: older versions of rsync used -h for help. Newer ones use --human-readable. We have detected that you are using version $MAJOR_RSYNC_VERSION. This program works best with rsync version 3 or higher. Please use an rsync with --human-readable as a valid parameter"
  exit 2
fi


#assume we're not using ipv6
if [ "$OS" == "FreeBSD" ]; then
  LOCAL_INTERFACE=$(route get default | grep interface | awk '{print $2}')
else
  LOCAL_INTERFACE=$(route | grep default | awk '{print $8}')
fi
LOCAL_IP=$(/sbin/ifconfig "$LOCAL_INTERFACE" | grep inet | sed -e /inet6/d | awk '{print $2}' | sed -e /addr:/s///)

#Name of server must not have spaces
HOSTNAME=$(hostname)
NAME="Rsync_$HOSTNAME"
SERVER="The file server "
LONGDATE=$(date +%Y-%m-%d_%H-%M)

#default notify settings
ALERT_MAIL=$USERNAME
ADMIN_MAIL_GROUP="root"
ERROR_MAIL_GROUP="$ADMIN_MAIL_GROUP"

#backup settings
DAYS_TO_KEEP=30
ORIGINAL_DIR="/home/ldapusers/"
#BACKUP_DIR can be on a different partition than ORIGINAL_DIR
BACKUP_ROOT_LEVEL="/mnt/esata/"
BACKUP_DIR="$BACKUP_ROOT_LEVEL/current/"

#for archiving override with r flag  
#ARCHIVE_DIR="/data/Project_archives"
ARCHIVE_DIR=""
#for archiving, override with R flag
#SITE_NUMBER=2
#ARCHIVE_FILES="/data/current/Projects/$SITE_NUMBER*"

#system settings
WHICH_MACHINE=$(hostname)
EMAIL_SUBJECT=$WHICH_MACHINE.backup
#make sure that $NOW and $LONGDATE are in the same format
NOW=$(date +%Y-%m-%d_%H-%M)

PROGRAM_NAME=$(basename "$0")
USAGE_TEXT="$PROGRAM_NAME Version: $VERSION 

Usage: $PROGRAM_NAME [-l] [-v] <-i input_directory> <-o backup_directory> [-a alert@email.addresses] [-d #days_to_keep] [-E exclude] [-e errors@email.address,err@address2,...]  

-l      Create a log file and keep it (otherwise delete log file)
-v      Debug Mode (very verbose)
-n      Dry Run: Don't actually do the rsync part
-i      directory     Original Directory (input), required
-o      directory    Backup Directory (output), required
-O      Rsync servers older than 2.6.3 need this flag
-b      Create a hardlinked backup like YYYYMMDD.HHMMSS? 
-a      email1,email2,...   Send Notices (e.g. done! good things)  to these email addresses
-A      email1,email2,...   Send Alerts (e.g. administrative verbose messages.) to email addresses
-e      email1,email2,...  Send Errors to this email address (e.g. out of space!)
-d N    Delete directories N days old in the -o directory
-D      Delete files that do not exist on sender
-E      Exclude files   Pattern of files to exclude, can be used more than once
-f      Extra flags    Anything else you want to pass to rsync
-h      host      A remote host - used to ping first to see if it is up. If not used then it will just assume the host is available
-m      CIFS_mount_drive   Sometimes CIFS connections hang to windows servers - this unmounts and remounts all CIFS shares. TODO: just operate on the CIFS share specified. 
-M      Mountpoint_dir   Check to make sure that dir Mountpoint_dir is a mounted directory. This is to avoid writing to your own disk when expecting it to be a externally attached drive
-r      Archive directory   What directory to archive to (does not work on FreeBSD)
-R      Archive PATTERN   Pattern of files to copy to the archive directory - 
        (Archive Files are a permanent copy of files that are never deleted)
-s      Subject for Email   Something to use on the email subject line
-S      Reserved for later: Rsync over ssh
-w      Warning Level   Send and alert when the amount of disk used space is above this percentage
"


#
# using getopts
#
aflag=
Aflag=
eflag=
hflag=
iflag=
mflag=
Mflag=
nflag=
oflag=
rflag=
Rflag=
wflag=
#dflag=
#Dflag=
#Eflag=
#fflag=
#vflag=
#lflag=
#Oflag=
#sflag=
#Sflag=

EXCLUDES=""
DELETE=""
OLD_VERSION=""


#warning! make sure that a: is the first : in the list
while getopts 'mnblDvOa:A:d:e:E:f:i:h:M:o:r:R:S:s:w:' OPTION
do
  case $OPTION in
  v)  #vflag=1
    #DEBUG
    set -x
                echo "VERSION=$VERSION"
    ;;
  l)  #lflag=1
    #log in verbose mode, create archive dir, cp -l
    CREATE_LOG="yes"
    ;;
  a)  aflag=1
    #to whom do we send brief e-mail noifications of completion, etc.
    #aval="$OPTARG"
    ALERT_MAIL="$OPTARG"
    ;;
  A)  Aflag=1
    #to whom do we send detailed e-mail noifications of completion, etc.
    #Aval="$OPTARG"
    ADMIN_MAIL_GROUP="$OPTARG"
    ;;
  b)  #bflag=1
    #Create backup in link format - datestamped? 
    #bval="$OPTARG"
    MAKE_BACKUP_DIRECTORY="yes"
    ;;
  D)  #Dflag=1
    #Delete files from destination that do not exist on source
    #Dval="$OPTARG"
    DELETE=" --delete --delete-excluded " 
    ;;
  d)  dflag=1
    #Days to keep archive
    #dval="$OPTARG"
    DAYS_TO_KEEP="$OPTARG"
    ;;
  e)  eflag=1
    #To whom do we sent e-mail notifications of errors
    #eval="$OPTARG"
    ERROR_MAIL_GROUP="$OPTARG"
    ;;
  E)  #Eflag=1
    #Exclude options passed to rsync
    #eval="$OPTARG"
    EXCLUDES="$EXCLUDES --exclude $OPTARG"
    ;;
  f)  #fflag=1
    #If you want to pass an extra flag to rsync.
    #fval="$OPTARG"
    EXTRA_FLAGS="$OPTARG"
    ;;
  h)  hflag=1
    #i for in
    #hval="$OPTARG"
    REMOTE_SERVER="$OPTARG"
    RSYNC_HOST="rsync://$OPTARG/"
    ;;
  i)  iflag=1
    #i for in
    #ival="$OPTARG"
    ORIGINAL_DIR="$OPTARG"
    ;;
  M)  Mflag=1
    #M for check to make sure this is a mount point
    #Mval="$OPTARG"
    MOUNT_POINT_DIR="$OPTARG"
    ;;
  m)  mflag=1
    #m for un-Mount all CIFS mounts and then re-Mount them
    #mval="$OPTARG"
    CIFS_MOUNT="$OPTARG"
    ;;
  n)  nflag=1
    #n dry-run flag
    #nval="$OPTARG"
    DRY_RUN=" -n "
    ;;
  O)  #Oflag=1
    #o for out
    #Oval="$OPTARG"
    OLD_VERSION=" --old-d "
    ;;
  o)  oflag=1
    #o for out
    #oval="$OPTARG"
    BACKUP_ROOT_LEVEL="$OPTARG"
    BACKUP_DIR="$BACKUP_ROOT_LEVEL/current/"
    ;;
  r)  rflag=1
    #Archive directory - where to permanently archive files
    #rval="$OPTARG"
    ARCHIVE_DIR="$OPTARG"
    #ARCHIVE_DIR="/data/Project_archives"
    ;;
  R)  Rflag=1
    #Archive PATTERN - used if there are specific files to permanently archive
    #Rval="$OPTARG"
    ARCHIVE_FILES="$OPTARG"
    #e.g.
    #ARCHIVE_FILES="Projects/$SITE_NUMBER*"
    ;;
  #S)  #Sflag=1
    #Archive PATTERN - used if there are specific files to permanently archive
    #Sval="$OPTARG"
    #SSH_OPTION="-e ssh $OPTARG@"
    #;;
  s)  #sflag=1
    #Archive PATTERN - used if there are specific files to permanently archive
    #sval="$OPTARG"
    EMAIL_SUBJECT="$OPTARG"
    ;;
  w)  wflag=1
    #Warning percentage - send warning if percent disk used ABOVE this number (df returns %used)
    #wval="$OPTARG"
    WARNING_LEVEL="$OPTARG"
    ;;
  #?)  printf "%s" "$USAGE_TEXT" "$(basename "$0")" >&2
  #  exit 2
  #  ;;
  esac
done


if [ "$oflag" != 1 ] ; then
  printf "OUTPUT directory required %b (\033[1m-o backup_directory)\033[0m. \n\n%s" "$oflag" "$USAGE_TEXT"
  exit 2
fi
if [ "$iflag" != 1 ] ; then
  printf "Need INPUT directory %b (\033[1m-i input_directory\033[0m). \n\n%s\n" "$iflag" "$USAGE_TEXT"
  exit 2
fi

#check if this should be a mount point and exit if it is not
if [ "$Mflag" == 1 ] ; then
  RESULT=$(mount | grep "$MOUNT_POINT_DIR")
  #RESULT=`mountpoint $MOUNT_POINT_DIR`
    if [ $? -eq 1 ] ; then 
    printf "OutputDirectory: %s. (\033[1m-M MOUNT_POINT_DIR\033[0m) \n\n %s" "$RESULT" "$USAGE_TEXT" >&2
    exit 2
  fi
fi

if [ "$Rflag" == 1 ] ; then
  #check to see if it starts with a / and if so error out
  FIRST_CHAR=${ARCHIVE_FILES:0:1}
  if [ "$FIRST_CHAR" == "/" ] ; then 
    echo "The path to the Archive files must be relative to the root backup directory (e.g. -i ). You appear to have specified an absolute path ($ARCHIVE_FILES) since it starts with a /. Cowardly stopping. "
    exit
  fi  
fi 

#test to see if is rsync connection
echo "$ORIGINAL_DIR" | egrep "^rsync://" > /dev/null 2>&1
if [ "$?" == "0" ]; then 
  # If it is then set hflag = 1 if not set already
  if [ "$hflag" == "" ] ; then
    hflag=1
    #get just the IP address for REMOTE_SERVER
    REMOTE_SERVER=$(echo "$ORIGINAL_DIR" | sed -e /rsync:../s/// | sed -e /\\.*/s///)
    RSYNC_HOST="$ORIGINAL_DIR"
  fi


  #quick test to see if Rsync is running on remote server and that 
  #we are good to go. rm -rf ./
  rsync "$RSYNC_HOST" > /tmp/error_message_no_archive 2>&1 
  ERROR_CODE=$?
  if [ "$ERROR_CODE" != 0 ] ; then
    if [ "$eflag" == 1 ] ; then
      echo "Hello- 
             This is your backup machine $WHICH_MACHINE. Rsync Failed Error[$ERROR_CODE]. 
             Command was: $0 $* !" >> /tmp/error_message_no_archive;
      mail -s "RSYNC FAILURE $WHICH_MACHINE" "$ERROR_MAIL_GROUP" < /tmp/error_message_no_archive ;
      rm /tmp/error_message_no_archive
    fi
  fi
else
  #this is NOT an rsync server and must be local or a mount. Lets test to see if we can access the directory  
  ORIGINAL_DIR_TEST=$(find "$ORIGINAL_DIR" -maxdepth 2 -type d -wholename "$ORIGINAL_DIR" )
  if [ ! -d "$ORIGINAL_DIR_TEST" ] ; then

    #directory didn't appear - could be problems with a windows connection. 
    #let's try unmounting and re-mounting
    if [ "$mflag" == 1 ] ; then
    #do a ls to re-conenct to make sure the connection is still good
      #TODO: Use "$CIFS_MOUNT"
      if [ "$CIFS_MOUNT" == "" ]; then 
        #TODO: Check that umount/mount is successful
        umount -a -t cifs
        sleep 1
        mount -a -t cifs
        sleep 1
      else
        #TODO: Check that umount/mount is successful
        umount -t cifs "$CIFS_MOUNT"
        sleep 1
        mount -t cifs "$CIFS_MOUNT"
        sleep 1
      fi
    fi
  
  fi

  #now lets test again after previous test
  if [ ! -d "$ORIGINAL_DIR_TEST" ] ; then
    echo "Hello- 
  This is your backup machine $WHICH_MACHINE. Trying to connect to the original directory $ORIGINAL_DIR and could not." > /tmp/error_message_no_link;
    if [ "$eflag" == 1 ] ; then
      mail -s "FAILURE $WHICH_MACHINE" "$ERROR_MAIL_GROUP" < /tmp/error_message_no_link ;
    fi
    exit;
  fi

#echo "REMOTE SERVER=$REMOTE_SERVER"
#echo "ORIGINAL DIR=$ORIGINAL_DIR"
#echo "---"

fi   #end if test to see if remote site is rsync and up
#exit

if [ "$CREATE_LOG" == "yes" ] ; then 
  VERBOSE=" -v --itemize-changes"
  LOG_FILE=$BACKUP_ROOT_LEVEL/backup.$LONGDATE.log
else
  VERBOSE=""
  LOG_FILE="/tmp/last_rsync.$LONGDATE"
fi


#If hflag=1 (remote host) then use ping check to see if it is up
if [ "$hflag" == 1 ] ; then 
    
  TEST=$(which ping)
  if [ "$TEST" == "" ] ; then 
    echo "If you are going to use the -h flag then ping must be installed";
    exit
  fi
  
  #test for icmp response
  #fping -u: Show targets that are unreachable
  #for SERVER in $(fping -u "$REMOTE_SERVER"); do
  #  echo "$SERVER does not respond to ping" > "/tmp/Rsync_Error.$SERVER"
  #  echo "NOT BACKING UP $SERVER" >> "/tmp/Rsync_Error.$SERVER"
  #  mail -s "$HOSTNAME: $NAME SERVER $SERVER IS DOWN!!!!" "$ERROR_MAIL_GROUP" < "/tmp/Rsync_Error.$SERVER"
  #  exit
  #done
  ping -c 1 -q "$REMOTE_SERVER" > "/tmp/backupinator.$SERVER"
  if [ $? == 1 ]; then 
    echo "$SERVER does not respond to ping" >> "/tmp/backupinator.$SERVER"
    echo "NOT BACKING UP $SERVER" >> "/tmp/backupinator.$SERVER"
    mail -s "$HOSTNAME: $NAME SERVER $SERVER IS DOWN!!!!" "$ERROR_MAIL_GROUP" < "/tmp/backupinator.$SERVER"
    exit
  fi 
fi


#are we full - Bytes? the -P flag is to keep the output from wrapping
USED_SPACE=$(df -P "$BACKUP_ROOT_LEVEL" | awk '{print $5}' | sed -e /%/s/// | tail -1 )

if [ "$USED_SPACE" == 100 ] ; then 
  echo "I tried to backup  $NAME but there was an error: Disk is Full" > "/tmp/Rsync_Error.$NAME"
  echo "The Script has ended. No backup was made." >> "/tmp/Rsync_Error.$NAME"
  mail -s "$HOSTNAME: $NAME RSYNC Error:" "$ERROR_MAIL_GROUP" < "/tmp/Rsync_Error.$NAME"
  exit;
fi 

if [ "$wflag" == 1 ] ; then
  if [ "$WARNING_LEVEL" != '' ] && [ "$WARNING_LEVEL" -lt "$USED_SPACE" ] ; then
    echo "WARNING: $HOSTNAME $NAME Used Space greater than than $WARNING_LEVEL %" > /tmp/Rsync_Error_space
    mail -s "$HOSTNAME: $NAME RSYNC Error:" "$ERROR_MAIL_GROUP" < /tmp/Rsync_Error_space
  fi
fi

#Are we out of inodes
FS_TYPE=$(df -P -T "$BACKUP_ROOT_LEVEL" | awk '{print $2}' | tail -1 )
#check to see if you were stupid and used ext3 for this
if [ "$FS_TYPE" != "reiserfs" ] ; then
  #ok - now we have to check if we're out of inodes - sheesh!
  #ugh, now don't you wish you'd used a reiserfs system.
        if [ "$OS" == "FreeBSD" ]; then
    AVAILABLE_SPACE=$(df -P -i "$BACKUP_ROOT_LEVEL" |  awk '{print $7}' | tail -1)
        else 
    AVAILABLE_SPACE=$(df -P -i "$BACKUP_ROOT_LEVEL" |  awk '{print $4}' | tail -1)
        fi
  if [ "$AVAILABLE_SPACE" == 0 ] ; then 
      echo "I tried to backup  $NAME but there was an error: Disk Out of Inodes. Too bad you didn't use and indodeless File System" > "/tmp/Rsync_Error.$NAME"
      echo "The Script has ended. No backup was made." >> "/tmp/Rsync_Error.$NAME"
        if [ "$eflag" == 1 ] ; then
        mail -s "$HOSTNAME: $NAME RSYNC Error:" "$ERROR_MAIL_GROUP" < "/tmp/Rsync_Error.$NAME"
    fi
    exit;
  fi 
fi  

##############CHECK TO see if previous rsync finished


#How many processes are running? We don't want to run if there is already one working on that dir. 
#NUMBER_LINES=$(pgrep -fa -u "$USERNAME" "rsync.*$ORIGINAL_DIR" | grep "$BACKUP_DIR" | sed -e /grep/d | nl |  sed -e /"$USERNAME.*"/s/// | tail -1)
NUMBER_LINES=$(pgrep -fc -u "$USERNAME" "rsync.*$ORIGINAL_DIR")

#echo "$NUMBER_LINES"
#echo "RESULT IS"
#echo "$RESULT"

#if [[ $NUMBER_LINES -gt 0 ]] ; then

if [ "$NUMBER_LINES" != '' ] && [ "$NUMBER_LINES" -gt 1 ] ; then
    echo "$SERVER $NAME RSYNC $LOCAL_IP IS STILL RUNNING. Windows Hang: Fixing" > "/tmp/Rsync_Error.$NAME"
    echo "$NUMBER_LINES lines detected" >> "/tmp/Rsync_Error.$NAME"
    if [ "$eflag" == 1 ] ; then
      mail -s "$SERVER $NAME RSYNC STILL RUNNING ERROR" "$ERROR_MAIL_GROUP" < "/tmp/Rsync_Error.$NAME"
    fi
    /usr/local/bin/kill_rsync.sh
    exit
fi

##############END check if previous rsync finished.


#exit;

#All tests pass? Ok we're ready to start
echo "Starting rsync version $RSYNC_VERSION from backupinator version $VERSION" > "$LOG_FILE"
echo "PATH=$PATH" >> "$LOG_FILE"


ARCHIVE_TEST_FILE=$(find "$ARCHIVE_FILES" -maxdepth 1 -mindepth 1 -name "$ARCHIVE_FILES" | tail -1)
if [ "$rflag" == 1 ] && [ $Rflag == 1 ] && [ -d "$ARCHIVE_DIR" ] && [ -e "$ARCHIVE_TEST_FILE" ] ; then
  printf "Start Project Archives: %s\n" "$(date)">> "$LOG_FILE"
  echo "ajo_cp -ulr --preserve=timestamps -f --remove-destination $BACKUP_DIR/$ARCHIVE_FILES $ARCHIVE_DIR" >> "$LOG_FILE"
  if [ "$nflag" == 1 ] ; then 
    echo "DRY RUN - not performing ARCHIVE step"
    echo "DRY_1: $BACKUP_DIR"
    echo "DRY_2: $ARCHIVE_FILES"
    echo "DRY_3: $ARCHIVE_DIR"
  else 
    cp -ulr --preserve=timestamps -f --remove-destination "$BACKUP_DIR/$ARCHIVE_FILES" "$ARCHIVE_DIR"
  fi
else
    if [ "$rflag" == 1 ] ; then
      echo "Hello- This is your backup machine $WHICH_MACHINE. I was trying to connect to the archive directory $ARCHIVE_DIR because rflag=$rflag and looking for the file $ARCHIVE_TEST_FILE because Rflag=$Rflag and I couldn't find it. Skipping Archives." > /tmp/error_message_no_archive;
        if [ "$eflag" == 1 ] ; then
    mail -s "FAILURE $WHICH_MACHINE" "$ERROR_MAIL_GROUP" < /tmp/error_message_no_archive ;
        fi
    fi
fi

printf "Start Rsync: %s\nrsync flags\nEXTRA=%s\nOLD=%s\nVERBOSE=%s\nDELETE=%s\nEXCLUDES=%s\nORIG=%sBACK=%s\n\n" "$(date)" "$EXTRA_FLAGS" "$OLD_VERSION" "$VERBOSE" "$DELETE" "$EXCLUDES" "$ORIGINAL_DIR" "$BACKUP_DIR" >> "$LOG_FILE"

#Some good excludes for backing up windows machines
#--exclude '*.bak' --exclude '*.BAK' --exclude '*.tmp' --exclude '*.TMP' --exclude '*.lnk' --exclude 'B*.rbf'


#really when we are connecting to a windows machine - we don't care about owner
#dropping -o 
rsync  -rltgDz "$EXTRA_FLAGS" "$DRY_RUN" --human-readable $VERBOSE "$OLD_VERSION" --stats --no-whole-file "$DELETE" "$EXCLUDES" "$ORIGINAL_DIR" "$BACKUP_DIR" >> "$LOG_FILE" 2>&1

ERROR_CODE=$?
if [ "$ERROR_CODE" != 0 ] ; then
  if [ "$eflag" == 1 ] ; then
    echo "Hello
   This is your backup machine $WHICH_MACHINE. 
  Rsync Failed Error[$ERROR_CODE]!
  Rsync Client Version: $RSYNC_VERSION
  Backup Version: $VERSION
  $0 $*" > /tmp/error_message_no_archive;
    awk '/^rsync/ {print $0}' "$LOG_FILE" >> /tmp/error_message_no_archive 
    mail -s "RSYNC FAILURE $WHICH_MACHINE" "$ERROR_MAIL_GROUP" < /tmp/error_message_no_archive ;
   fi
fi

echo "
------------------------
End Rsync: " >> "$LOG_FILE"
date >> "$LOG_FILE"


if [[ "$MAKE_BACKUP_DIRECTORY" == "yes" ]] ; then 
  #now that we've made the rsync backup - lets preserve the data in 
  # a new directory. use hard links to save space
  if [ "$nflag" == 1 ] ; then 
    echo "DRY RUN - not performing BACKUP_STEP step"
    echo "ajo_cp -al $BACKUP_DIR $BACKUP_ROOT_LEVEL/backup.$NOW"
  else 
    cp -al "$BACKUP_DIR" "$BACKUP_ROOT_LEVEL/backup.$NOW"
    touch "$BACKUP_ROOT_LEVEL/backup.$NOW"
  fi
fi

if [ "$eflag" == "" ] ; then 
  echo "Warning: Error message delivery going to root user"
fi

#If dflag=1 then we look for that many days ago and delete it
if [ "$dflag" == 1 ] ; then 
  if [ "$OS" == "FreeBSD" ]; then
    OLDEST_DATE=$(date -v -"${DAYS_TO_KEEP}d" +%Y-%m-%d)
  else
    OLDEST_DATE=$(date -d "$DAYS_TO_KEEP days ago" +%Y-%m-%d)
  fi
  #OLDEST_DIR=$(ls -Ad $BACKUP_ROOT_LEVEL/backup.$OLDEST_DATE* | tail -1)
  OLDEST_DIR=$(find "$BACKUP_ROOT_LEVEL" -maxdepth 1 -mindepth 1 -type d -name "backup.$OLDEST_DATE*" | tail -1)

  #oldest dirs = all backups that day and *.gz files if they are there too
  OLDEST_DIRS=$(ls -Ad "$BACKUP_ROOT_LEVEL/backup.$OLDEST_DATE*" )

  # aflag is for notices, Aflag is for alerts dflag is for deleting
  if [ ! -d "$OLDEST_DIR" ] && [ "$aflag" == 1 ] ; then
    echo "I tried to find a directory named $BACKUP_ROOT_LEVEL/backup.$OLDEST_DATE* and found '$OLDEST_DIR'. Either it isn't a directory or it didn't exist. Don't panic. This may be because the number of days to backup is now larger than the number of days backed up. You can confirm this by going to your local backup directory and looking at the list of files there.  In under $DAYS_TO_KEEP this message will stop arriving. If in $DAYS_TO_KEEP you are still getting this message then you can open a ticket." > /tmp/error_message_no_delete
    echo "
O_DATE = $OLDEST_DATE
O_DIR = $OLDEST_DIR
O_DIRS = $OLDEST_DIRS
KEEP = $DAYS_TO_KEEP
B_ROOT_LEVEL = $BACKUP_ROOT_LEVEL" >> /tmp/error_message_no_delete

    if [ "$eflag" == 1 ] ; then
      mail -s "WARNING $WHICH_MACHINE ON DELETE $OLDEST_DIR" "$ERROR_MAIL_GROUP" < /tmp/error_message_no_delete ;
    fi
  fi

  #santity checks
  SANITY=1
  for SANITY_CHECK_DIR in '/data' '' '.' '/' '.*' '/var' '/tmp' '/home' '/media' '/etc' '* .*' '/usr' '/bin' '/boot'; do 
    if [ "$OLDEST_DIR" == "$SANITY_CHECK_DIR" ]; then 
      printf "Error: I don't think you wanted to delete %s. Not doing it" "$OLDEST_DIR" >> /tmp/error_message_no_delete
      SANITY=0
    fi
  done

  #and lets delete the oldest file
  if [ -d "$OLDEST_DIR" ] && [ "$SANITY" == 1 ] ; then
    if [ "$nflag" == 1 ] ; then 
      echo "DRY RUN - not performing DELETE step"
      echo "ajo_rm -rf $OLDEST_DIRS"
    else 
      rm -rf "$OLDEST_DIRS"
    fi
  fi
  # you may ask - "Why don't you use 'find' to delete old directories?" The answer is that because we 
  # are using hard links instead of an actual new directory - the datestamp of the directories may not 
  # be the date of creation. Also we don't want to just indiscriminately delete everything - just the 
  # backup directories. 

  echo "Deleting backup dirs $OLDEST_DIRS" >> "$LOG_FILE"

fi

echo "------------------------
Space left on hard-drive" >>  "$LOG_FILE"
df -P -h "$BACKUP_ROOT_LEVEL" >> "$LOG_FILE"


PERCENT_USED=$(df -P -h "$BACKUP_ROOT_LEVEL" | awk '{ print $5 }' | tail -1 )


#aflag = notice of good things
#Aflag = warnings of potentially bad things or just more verbose notices of good things
 if [ "$Aflag" == 1 ] ; then
    mail -s "$EMAIL_SUBJECT"  "$ADMIN_MAIL_GROUP" < "$LOG_FILE"
 fi
#eflag = errors - bad
  if [ "$aflag" == 1 ] ; then
    tail -40 "$LOG_FILE" >> "$LOG_FILE.simple"
    #df -P -h > $LOG_FILE.simple
  mail -s "$EMAIL_SUBJECT: $PERCENT_USED Disk Used" "$ALERT_MAIL" < "$LOG_FILE.simple"
        rm "$LOG_FILE.simple"
  fi

if [[ "$CREATE_LOG" == "yes" ]] ; then 
  gzip "$LOG_FILE"
else
  rm "$LOG_FILE"
fi
