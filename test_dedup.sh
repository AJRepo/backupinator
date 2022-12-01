#!/bin/bash

#Test your system to see how deduplication and inodes work with rsync. 
# Run this in the file system you plan to backup to. It will
# simulate running backupinator 4 days in a row, where 
# CURRENT is the backup dir where each day's backups go. 
# day 2 no modifications
# day 3 modifies Current
# day 4 no modifications
#
#echo "This will test your system with hardlinks and rsync to see if:"
#echo " * Deduplication works via hardlinks"
#echo " * If backupinator might cause a running out of inodes before running out of disk space" 
#echo " This will create the directory testdir which you can delete after the test."


#NOTE NOTE NOTE: Have only tested this testing script on filesystems
# UFS
# EXT4
# todo: test on other file systems. zfs, reiserfs, etc. 
# In the original implementation of backupinator all backup systems were inodeless (reiserfs)
# which was a requirement for enterprise-scale backups to not run out of inodes. 

CURRENT="current"
DAY_THREE=$(date +%Y%m%d --date="today - 1 day")
DAY_TWO=$(date +%Y%m%d --date="today - 2 day")
DAY_ONE=$(date +%Y%m%d --date="today - 3 day")

MOD_TEST="two files and four simulated days of backups with one day of changes"
CONTROL="two files and four simulated days of backups with no changes"


if [ -d ./testdir ]; then
	echo "Please delete the directory 'testdir' first"
	exit 1
fi

# Create test files
for DIR in "unmodified" "modified"; do
	mkdir -p "testdir/$DIR/$CURRENT"
done

#Create Scratch Orig files
echo "ORIGINAL FILE!!!!!" > "testdir/a"
echo "ALSO AN ORIGINAL FILE!!!!!" > "testdir/b"
#Create Scratch Modified files
echo "THE MODIFIED FILE!!!!!" > "testdir/a.new"
echo "ALSO THE MODIFIED FILE!!!!!" > "testdir/b.new"


#Cp with hard links, no modifications
if ! rsync "testdir/a" "testdir/unmodified/$CURRENT/a"; then 
	echo "ERROR: rsync not installed or working "
	exit 1
fi
rsync "testdir/b" "testdir/unmodified/$CURRENT/b"
cp -al  "testdir/unmodified/$CURRENT" "testdir/unmodified/$DAY_ONE"
cp -al  "testdir/unmodified/$CURRENT" "testdir/unmodified/$DAY_TWO"
cp -al  "testdir/unmodified/$CURRENT" "testdir/unmodified/$DAY_THREE"

# Uncomment to test differences in size
#Cp without hard links, no modifications
#mkdir -p "testdir/nolinks"
#rsync "testdir/a" "testdir/nolinks/$CURRENT/a"
#rsync "testdir/b" "testdir/nolinks/$CURRENT/b"
#cp -a  "testdir/nolinks/$CURRENT" "testdir/nolinks/$DAY_ONE"
#cp -a  "testdir/nolinks/$CURRENT" "testdir/nolinks/$DAY_TWO"
#cp -a  "testdir/nolinks/$CURRENT" "testdir/nolinks/$DAY_THREE"

#Test dirs, modified
rsync "testdir/a" "testdir/modified/$CURRENT/a"
rsync "testdir/b" "testdir/modified/$CURRENT/b"
cp -al  "testdir/modified/$CURRENT" "testdir/modified/$DAY_ONE"
cp -al  "testdir/modified/$CURRENT" "testdir/modified/$DAY_TWO"
#if rsync is setup properly, this breaks the hard link
rsync "testdir/a.new" "testdir/modified/$CURRENT/a"
rsync "testdir/b.new" "testdir/modified/$CURRENT/b"
cp -al  "testdir/modified/$CURRENT" "testdir/modified/$DAY_THREE"

#Check Number of files
#echo "Number of Files in $(pwd)/testdir" ; for d in $(find ./testdir -maxdepth 1 -type d | cut -d/ -f3 | grep -xv .  | sort | uniq); do c=$(find "testdir/$d" | wc -l) ; printf "%s\t\t- %s\n" "$c" "$d"; done ; printf "Total: \t\t%s\n" "$(find "$(pwd)/testdir" | wc -l)"
if [[ $(find testdir/unmodified | wc -l) == 13 && $(find testdir/modified | wc -l) == 13 ]]; then 
	echo "OK: 13 objects detected"
else
	echo "ERROR: More than 13 objects detected"
	exit 1
fi

#check inodes used
if [[ $(find ./testdir/unmodified -type f -exec ls -i {} \; | awk '{print $1}' | sort | uniq | wc -l) -le 2 ]]; then
	echo "OK: 2 Inodes created for $CONTROL"
else
	echo "WARN: more than 2 inodes created $CONTROL"
fi

#check inodes used
INODES_CREATED=$(find ./testdir/modified -type f -exec ls -i {} \; | awk '{print $1}' | sort | uniq | wc -l)
if [[ $INODES_CREATED -lt 4 ]]; then
	# You might be on an inodeless file system. Backupinator will not run out of indodes before disk space
	echo -n "OK: $INODES_CREATED inodes created. Fewer than 4 inodes created for $MOD_TEST"
else
	echo "Note: $INODES_CREATED inodes created for $MOD_TEST."
	echo "Note: (cont) Backups might run out of inodes long before you run out of disk space."
fi


#check disk space used for unmodified
if [[ $(du -sl testdir/unmodified/ | cut -f1) -gt $(du -s testdir/unmodified/ | cut -f1) ]]; then
	echo "OK: Deduplication ok with $CONTROL. Moving on to next test."
else
	echo "ERROR: It appears no deduplication with $CONTROL. Check if your system supports hard links."
	exit 1
fi

#check disk space used for modified
if [[ $(du -sl testdir/modified/ | cut -f1) -gt $(du -s testdir/modified/ | cut -f1) ]]; then
	echo "PASS: Deduplication with $MOD_TEST"
else
	echo "ERROR: It appears no deduplication occured with $MOD_TEST. Check if your system supports hard links and if rsync is working as expected."
	exit 1
fi

exit 0
#Note: Must use tabs instead of spaces (e.g. noexpandtab) for heredoc (<<-) to work
# vim: tabstop=2 shiftwidth=2 noexpandtab
