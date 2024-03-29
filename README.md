# backupinator
Incremental Backup via rsync with hard links for instant deduplication. Works both for linux (tested in RedHat, OpenSuse and Ubuntu) and FreeBSD (tested in FreeNAS 9.10)

###History
This is a script that originated in the year 2000 with a need to backup to a central server a complete 
copy of all data on 7 Windows file servers across 7 offices separated by T1 connections with a document retention 
policy of day-by-day snapshots of each local office's server's shares to offsite storage. The script was later modified to autodelete after N days and recognize key files to move to an archive directory for permanent storage. 

In 2000, each office had roughly 100 GiB of data. Within 2 years this script (paired with rsync servers) was backing up 400,000 files (~3 TiB) nightly and after ~8 years, was backing up to a central repository 22 TiB twice daily and once nightly with a complete daily filesystem backup/snapshot from each of the 7 file servers.  This was possible without massive network connections due to rsync's server-to-server binary differential speedup and possible without massive disk requirements due to dedupliation that's built into backupinator using hard links in the daily snapshot for unchanged files.  

Historically, to deal with issues of network connectivity and CIFS hanging, this script has serveral checks to make sure remote servers are accessible, mountpoints are still mounted, etc.

### Dependencies

* Rsync. 

* A system that supports hard links (e.g. Linux, BSD) 

* Optionally ksh: I wrote this originally in bash but converted to ksh because of the ability to use shcomp 
to compile and deliver a perfectly working c binary. However you can change it to bash w/out changes. 

* Optionally an inodeless file system like ReiserFS. This uses hard links for deduplication. However if you have a system that has a hard limit on inodes, unlimited time backups, and lots of files then you can run out of inodes LOOOOOONG before you run out of disk space.

You can test your system for the above dependencies with the test script test\_deup.sh

### Syntax
 Usage: 

backupinator.sh: [-l] [-v] <-i input\_directory> <-o backup\_directory> [-a alert@email.addresses] [-d #days_to_keep] [-E exclude] [-e errors@email.address,err@address2,...] 

```
 

-l      Create a log file and keep it (otherwise delete log file)
-v      Debug Mode (very verbose), executes "set -x" 
-n      Dry Run: Don't actually do the rsync part
-i      directory     Original Directory (input), required
-o      directory    Backup Directory (output), required
-O      Rsync servers older than 2.6.3 need this flag
-b      Create a hardlinked backup like YYYYMMDD.HHMMSS (for deduplication)
-a      email1,email2,...   Send Notices (e.g. done! good things)  to these email addresses
-A      email1,email2,...   Send Alerts (e.g. administrative verbose messages.) to email addresses
-e      email1,email2,...  Send Errors to this email address (e.g. out of space!)
-d N    Delete directories N days old in the -o directory
-D      Delete files that do not exist on sender
-E      Exclude files   Pattern of files to exclude, can be used more than once
-f      Extra flags    Anything else you want to pass to rsync
-h      host      A remote host - ping first to see if it is up. If not used assume the host is available
-m      CIFS_mount_drive   Sometimes CIFS connections hang to windows servers - this unmounts and remounts all CIFS shares. TODO: just operate on the CIFS share specified. 
-M      directory Mountpoint_dir: Check that Mountpoint_dir is a mounted directory. This is to avoid writing to your own disk when expecting it to be a externally attached drive
-r      Archive directory   What directory to archive to (does not work on FreeBSD)
-R      Archive PATTERN   Pattern of files to copy to the archive directory
        (Archive files are a permanent copy of files that are never deleted)
-s      Subject for Email   Something to use on the email subject line
-S      Reserved for later: Rsync over ssh (remote rsync now does via rsync:// protocol) 
-w      Warning Level   Send an alert if the percent of disk used is above this number
```


### Sample usage

#### Examples:

* This example does the following:
  * Backs up the directory (and all subdirectories) /path/to/input/directory/ (-i flag) 
  * Specifies the backup directory as /path/to/backup/dir  (-o flag ) 
  * Specifies that the backup directory is a mountpoint and attempt to remount if not mounted. Errs out if it can't mount ( -M flag) 
  * Checks to see if the backup drive has less than 90% filled before backing up to it (-w 90 )
  * Delete directories over 20 days old, (-d 20 ) 
  * Ignores files/directories named .snap ( -E .snap )
  * Sends errors to errors@example.com (-e errors@example.com)
  * Sends notifications to admins@example.com (-a admin@example.com)
  * Saves the log file output (-l)

     ./backupinator.sh -l -i /path/to/input/directory/ -o /path/to/backup/dir -M /path/to/mount/point  -a admin@example.com -w 90 -E .snap -b -e errors@example.com -d 20


* This next example does the same as above but *also* 
  * ignores any files ending with .wav. The -E flag calls rsync's --exclude flag.  (-E .snap -E .wav )

     ./backupinator.sh -l -i /path/to/input/directory/ -o /path/to/backup/dir -M /path/to/mount/point  -a admin@example.com -w 90 -E .snap -E .wav -b -e errors@example.com -d 20
     
* Let's say your backup machine is a remote network mount `myNFSbackup.example.com` and your machine will hang for what seems forever if it can't access that network mount (i.e. NFS4) . Add a ping test before running the mount command. This example does the same as the above and *also* adds that test and abort the script before a mount test is done.

     ./backupinator.sh -l -i /path/to/input/directory/ -o /path/to/backup/dir -M /path/to/mount/point  -a admin@example.com -w 90 -E .snap -E .wav -b -e errors@example.com -d 20 -h myNFSbackup.example.com
     

### Notes

See the License file for copyright terms. Use of this script is at your own risk. Linux/Unix does not ask "if you meant to do that" and there are "rm -rf" commands in this script if you choose to use the -d flag. 

Use the "-n" flag for a "dry run" to see a list of commands of what will happen plus -l to keep the log file for review. Highly recommended for the first run.  

Note that there is a difference between `directory` and `directory/` in rsync (note the slash at the end of the directory name). Backupinator passes arguments to rsync so don't be surprised if `-i /path/to/input/dir` gives you different results than `-i /path/to/input/dir/` and likewise for the -o flag. 

The default location for ksh on Ubuntu is /usr/bin/ksh. The default location for ksh93 on OpenNAS (FreeBSD) is /usr/local/bin/ksh93. 


