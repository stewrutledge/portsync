#!/bin/bash

#########################################################################################################
# Portable Sync. A tool for performing incremental rsync, without a full backup on the destination end. #
# Copyright 2012 Stewart Rutledge, BSD copyright and disclaimer apply					#
#													#
#########################################################################################################

# Location of configuration file:
# Make sure rsync binary exists
which rsync >> /dev/null
which_rsync=$(echo $?)
if [[ $which_rsync == "1" ]]; then
  echo 'rsync binary not found. Make sure it is installed or in $PATH'
  exit 1
fi

function usage {
echo "Usage: $0 -t [type] -s [source] -d [destination]
or
Usage: $0 -t [type] -c [configfile]

Valid types: 

normal: Performs a normal rysnc and builds master_hash after complete

portable: Performas an incremental backup of changes, without the need of a full backup on the destination end 

gen-hash: Rebuilds hash without a sync. Only -s (source) or -c (config file) should be specified.

"
}

if [[ -z $config_file && -z $sync_opt && -z $source_opt && -z $dest_opt ]]; then
  usage
  exit 0
fi

# Generates the hash, using the ctime (the only modifaction time which cannot be easily tampered with)
function hash_gen {
find $source_dir -exec echo -ne {}' ' \; -exec stat -f %c {} \;
}

while getopts ":c:t:s:d:" opts; do
  case $opts in
    c)
      config_file=$OPTARG
      ;;
    t)
      sync_opt=$OPTARG
      ;;
    s)
      source_opt=$OPTARG
      ;;
    d)
      dest_opt=$OPTARG
  esac
done

# Validates that a config file and source destination have not be defined int he same command
if [[ -n $config_file && -n $source_opt ]]; then
  echo "Specify only config file, or souce and destination, not both"
  usage
  exit 1
elif [[ -n $config_file && -n $dest_opt ]]; then
  echo "Specify only config file, or souce and destination, not both"
  usage
  exit 1
fi

if [[ -n $source_opt && -z $dest_opt ]]; then
  echo "You must specify a source and destination"
  usage
elif [[ -z $source_opt && -n $dest_opt ]]; then
  echo "You must specify a source and destination"
  usage
fi

# Creates the the .portsync directory for the master list to be stored in. Default is sourceroot/.portsync 
if [[ -z $config_file && ! -d $source_opt/ ]]; then
  mkdir $source_opt/.portsync/
fi
# Defines a few variables, if no config is defined
if [[ -z $config_file ]]; then
  source_dir=$source_opt
  port_dest_dir=$dest_opt
  normal_dest_dir=$dest_opt
  portsync_dir=$source_dir/.portsync
  tmpdir=~/.portsync
fi
# Tests to see if the config file can be found, and if so, sources it.
if [[ -n $config_file && ! -e $config_file ]]; then
  echo "Config file not found"
  exit 1
fi
if [[ -n $config_file ]]; then
  source $config_file
fi
# Where he master list is actually stored
hash_master=$portsync_dir'hashmaster.chk'

# The gen-hash trigger, for rebuilding a master list
if [[ $sync_opt == "gen-hash" && -n $source_opt ]]; then
  echo "Rebuilding hash"
  hash_gen > $hash_master && echo "hash rebuilt"
  exit 0
elif [[ $sync_opt == "gen-hash" && -n $dest_opt ]]; then
  echo Usage
  exit 1
elif [[ $sync_opt == "gen-hash" && -n $config_file ]]; then
  echo "Rebuilding hash"
  hash_gen > $hash_master && echo "hash rebuilt"
  exit 0
fi

# The temp files needed to perform the sync
hash_portable=$(mktemp $tmpdir/hashchanges.XXX)
change_file=$(mktemp $tmpdir/changes.XXX)
include=$(mktemp $tmpdir/include.XXX)

# If no sync option is specified, exits
if [[ -z $sync_opt ]]; then
  usage
  exit 1
fi


# Command line to deteremine type of sync
if [[ $sync_opt == "portable" ]]; then
  sync_type=portable
elif [[ $sync_opt == "normal" ]]; then
  sync_type=normal
else
  usage
  exit 1
fi



# Used for normal sycns, generates a hashed list of all files in source directory
function rsync_normal_with_hash {
hash_gen > $hash_master
rsync -avr $source_dir $normal_dest_dir
}

# Generates a hash of the source directory, used immediately before the sync to determine which files have changed
function gen_portable_sync_hash {
hash_gen > $hash_portable
}
# Diff function for checking changes and outputting changed files to a temporary file
function check_changes {
diff --changed-group-format='%<' --unchanged-group-format='' $hash_master $hash_portable > $change_file 
}
# Parses the change file into a usable include list for rsync
function gen_portable_include {
cat $change_file | cut -f 1 -d " " | sed "s:$source_dir::g" | sed "s/^\///g" > $include
}
# The actual syncing function for the portable device
function sync_changes {
rsync -avr --include-from=$include --exclude "*" $source_dir $port_dest_dir
}


if [[ $sync_type == "normal" ]];then  
  rsync_normal_with_hash
  exit 0
fi
if [[ $sync_type == "portable" && ! -f $hash_master ]]; then  
  echo "No master hash found, have you ran a full backup?"
  exit 2
elif [[ $sync_type == "portable" && -f $hash_master ]]; then
  echo "Checking for changes"
  gen_portable_sync_hash
  check_changes
  changes_exit=$(echo $?)
fi
if [[ $changes_exit == 0 ]]; then
  echo "There doesn't seem to be any changes"
  rm -f $hash_portable
  rm -f $change_file
  rm -f $include
  exit 3
elif [[ $changes_exit -ne 0 ]]; then
  echo "Syncing changes since last full backup"
  gen_portable_include
  sync_changes
  sync_exit=$(echo $?)
fi
if [[ $sync_exit == 0 ]];then
  echo "Sync successful, recreating master hash"
  hash_gen > $hash_master
  rm -f $change_file
  rm -f $hash_portable
  rm -f $include
  exit 0
else
  echo "Something went wrong with the sync"
  exit 2
fi



