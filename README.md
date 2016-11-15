# backupinator
Incremental Backup via rsync with hard links for instant deduplication. Works both for linux and Free BSD

#History
This is a script that originated in the year 2000 with a need to backup to a central server a complete 
copy of all data on 7 Windows file servers across 7 offices separated by T1 connections with a document retention 
policy of day-by-day snapshots of the entire directory and offsite storage. In 2000, each office had roughly 100 GiB of data. Within 2 years this script was backing up 400,000 files (~3 TiB) nightly and after 10 years the script was backing up 22 TiB twice daily and once nightly with a complete filesystem backup/snapshot of the file servers each and every day with general files having a 12 month.  The script was later modified to also backup key files to an archive directory for permanent storage. All this without massive disk requirements due to the dedupliation that's built into the system using hard links in the daily snapshot.  

Historically to deal with issues of network connectivity and CIFS hanging this script has serveral checks to make sure remote servers are accessible, mountpoints are still mounted, etc.

By having daily incremental remote snapshots this script helps defends against both internal errors and external attacks. 

### Dependencies

Ksh. I wrote this originally in bash but converted to ksh because of the ability to use shcomp 
to compile and deliver a perfectly working c binary. 

### Syntax
 Usage: backupinator.sh: [-l] [-v] <-i input_directory> <-o backup_directory> [-a alert@email.addresses] [-d #days_to_keep] [-E exclude] [-e errors@email.address,err@address2,...] 
 

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
-R      Archive PATTERN   Pattern of files to copy to the archive directory
        (Archive files are a permanent copy of files that are never deleted)
-s      Subject for Email   Something to use on the email subject line
-S      Reserved for later: Rsync over ssh (remote rsync now does via rsync:// protocol) 
-w      Warning Level   Send and alert when the amount of disk used space is above this percentage

### Sample usage

# Example: a mounted directory /path/to/backup/dir where * you want to check to see if that drive has less than 90% filled before backing up to it, * you want to delete directories over 20 days old, * ignore .snap

./backupinator.sh -v -l -i /path/to/input/directory/ -o /path/to/backup/dir -M /path/to/backup/dir  -a admin@example.com -w 90 -E .snap -b -e errors@example.com -d 20


# Example: same as above but also ignore any files ending with .wav. The -E flag is the same as the one for rsync. 

./backupinator.sh -v -l -i /path/to/input/directory/ -o /path/to/backup/dir -M /path/to/backup/dir  -a admin@example.com -w 90 -E .snap -E .wav -b -e errors@example.com -d 20

### Notes

See the License file for copyright terms. Use of this script is at your own risk. Linux/Unix does not ask "if you meant to do that" and there are "rm -rf" commands in this script if you choose to use the -d flag. Use the "-n" flag for a "dry run" to see a list of commands of what will happen. 

The default location for ksh on Ubuntu is /usr/bin/ksh. The default location for ksh93 on OpenNAS (FreeBSD) is /usr/local/bin/ksh93. 


