#!/bin/bash
#==============================================================================
# Script that creates BTRFS snapshots, manually or schedualed by cron
#
# Usage:
#     sudo btrfs-share-snap <share_path> [-t <tag>] [-c <count>] \
#                                        [-m <mintime>] [-d <subdir>] \
#                                        [-r] [-v] [-s] [-o]
#
# Copyleft 2023 by Arthur Mitchell
#==============================================================================
BIN="${0##*/}"
DEST_PATH=".snapshots"
SHARE_PATH="${1}"

# Shift command line parameters along by one so the options can be read
shift

function print_usage()
{
echo "Usage: $BIN <share_path> [OPTIONS]
  <share_path>                  | Required. Location of the root directory of the share to take a snapshot of.
  -r                            | Create a read-only snapshot. Default off
  -v                            | Verbose output
  -o                            | Only if new. Skips snapshot creation of no files have changed since the last time this tag was snapshotted
  -h                            | Display this message
  -s                            | Safe mode. Used with -v this lets you check parameters and the actions that will be taken but doesn't create or delete any snapshots.
  -t <tag_name>                 │ An optional tag to pre-append to the directory name of the snapshot.
  -c <count>                    | The number of snapshots to keep. This is filtered by tag. Default: 0. Use 0 to disable counting
  -m <mintime>                  │ The minimum time in seconds that snapshots with the same tag can be taken. Default: 0. Use 0 to disable
  -d <destination-subdirectory> │ The sub-directory, level with the shared directory, that holds snapshots. Default: .snapshots

Exit status:
 0  if OK,
 1  if errors occured
"
}

function btrfs-snp()
{
  local COUNT=0
  local MINTIME=0

  ## usage
  [[ "$*" == "" ]] || [[ "$1" == "--help" ]] && {
    print_usage
    return 0
  }

  while getopts 'hvrsot:d:c:m:' flag; do
    case "${flag}" in
      c) COUNT="${OPTARG}" ;;
      d) DEST_PATH="${OPTARG}" ;;
      h) print_usage
         exit 0 ;;
      m) MINTIME="${OPTARG}" ;;
      o) ONLY_IF_NEW='true' ;;
      r) READONLY='true' ;;
      s) SAFE_MODE='true' ;;
      t) TAG="${OPTARG}" ;;
      v) VERBOSE='true' ;;
      *) print_usage
         exit 0 ;;
    esac
  done

  local SHARE_NAME="${SHARE_PATH##*/}"
  local MOUNT_POINT="${SHARE_PATH%%$SHARE_NAME}"
  local SNAPSHOT_LOCATION="$MOUNT_POINT$DEST_PATH/$SHARE_NAME/"

  local SNAPSHOT_NAME="GMT-$(date +%Y.%m.%d-%H.%M.%S)"
  [[ ! -z $TAG ]] && {
    local SNAPSHOT_NAME="$TAG""_GMT-$(date +%Y.%m.%d-%H.%M.%S)"
  }

  local SNAPSHOT_PATH=$SNAPSHOT_LOCATION$SNAPSHOT_NAME

  [[ $VERBOSE ]] && {
    echo "Parameters in use:"
    echo "  Share path" $SHARE_PATH
    echo "  Share name" $SHARE_NAME
    echo "  Share mount point" $MOUNT_POINT
    echo "  Snapshot location" $SNAPSHOT_LOCATION
    echo "  Snapshot name" $SNAPSHOT_NAME
    echo "  Snapshot path" $SNAPSHOT_PATH
    echo "  Destination path directory" $DEST_PATH
    [[ $SAFE_MODE ]] && {
        echo "  Safe mode on, no changes will be made"
        }
    [[ $ONLY_IF_NEW ]] && {
        echo "  Only if new is set, no snapshots will be created unless file changes are detected"
        }
    if [ -z $TAG ]
    then
        echo "  No tag set, file names will be in the format GMT-YYYY.MM.DD-HH.MM.SS"
    else
        echo "  Tag name" $TAG "set. File names will be in the format "$TAG"_GMT-YYYY.MM.DD-HH.MM.SS"
    fi
    echo "  Max snapshot count" $COUNT
    echo "  Minimum time" $MINTIME" /s"
  }

  # Checks
  #
  # Check that the tag name does not contain _GMT
  echo $TAG | grep -q "_GMT"  && { echo "Error: The tag name can not contain the string '_GMT'" ; return 1; }
  # Check that the script is being run as root
  [[ ${EUID} -ne 0  ]] && { echo "This script must be run as root. Try 'sudo $BIN'" ; return 1; }
  # Test the validity of the directories
  [[ ! -d "$SHARE_PATH" ]] && { echo "Error: Source share $SHARE_PATH not found."; return 1; }
  [[ ! -d "$SNAPSHOT_LOCATION" ]] && { echo "Error: Destination $SNAPSHOT_LOCATION not found."; return 1; }
  [[ -d "$SNAPSHOT_PATH" ]] && { echo "Error: $SNAPSHOT_PATH already exists."; return 1; }
  # Test that the share path is a BTRFS volume
  mount -t btrfs | cut -d' ' -f3 | grep -q "^${MOUNT_POINT}$" || {
    btrfs subvolume show "$SHARE_PATH" | grep -q "^${SHARE_NAME}$" || {
      echo "Error: $SHARE_PATH is not a BTRFS sub-volume."
      return 1
      }
    }

  # Count the number of snapshots below the snapshot directory
  if [ $TAG ]
  then
    local SNAPS=( $( btrfs subvolume list -s --sort=gen "$SNAPSHOT_LOCATION" | awk '{ print $14 }' | grep "^${TAG}" | grep "$DEST_PATH/$SHARE_NAME") )
  else
    local SNAPS=( $( btrfs subvolume list -s --sort=gen "$SNAPSHOT_LOCATION" | awk '{ print $14 }' | grep "^GMT-" | grep "$DEST_PATH/$SHARE_NAME" ) )
  fi

  [[ $VERBOSE ]] && {
    echo "Number of existing snapshots (with given tag):" ${#SNAPS[@]}
    }

  # Check time of the last snapshot for this tag
  [[ "$MINTIME" != 0 ]] && [[ "${#SNAPS[@]}" != 0 ]] && {
    [[ $VERBOSE ]] && {
      echo "Checking date and time of last snapshot"
      }
    local LATEST=$( sed -r "s/\-([0-9]{2}).([0-9]{2}).([0-9]{2})$/ \\1:\\2:\\3/;s/([0-9]{4}).([0-9]{2}).([0-9]{2})/\\1\-\\2\-\\3/;s/^.*GMT-//" <<< "${SNAPS[-1]}" )
    LATEST=$( date +%s -d "$LATEST" ) || return 1

    [[ $(( LATEST + MINTIME )) -gt $( date +%s ) ]] && {
      echo "No new snapshot needed for the tag $TAG"; return 0;
      }
    }

  # Check the number of different files between now and the previous snapshot
  [[ $ONLY_IF_NEW ]] && [[ "${#SNAPS[@]}" != 0 ]] && {
      [[ $VERBOSE ]] && {
        echo "Checking for file changes between" $MOUNT_POINT${SNAPS[-1]} "and" $SHARE_PATH
        }
      GEN_ID=$(btrfs sub find-new "$MOUNT_POINT${SNAPS[-1]}" 9999999 | cut -d " " -f 4)
      CHANGED_FILES="$(btrfs subvolume find-new "$SHARE_PATH" ${GEN_ID} | cut -d " " -f 17-1000 | sed '/^$/d'| wc -l)"
      [[ $VERBOSE ]] && {
        echo "Last transitid marker" $GEN_ID
        echo "Number of changes" $CHANGED_FILES
        }
      if [[ ${CHANGED_FILES} -eq 0 ]]; then
          echo "No file changes found, skipping creating of a new snapshot."
          return 0
      fi
  }

  # Take the snapshot
  if [ $READONLY ]
  then
    [[ $VERBOSE ]] && {
      echo "Taking snapshot as read-only"
      }
    [[ ! $SAFE_MODE ]] && {
      btrfs subvolume snapshot -r "$SHARE_PATH" "$SNAPSHOT_PATH" || return 1
      }
  else
    [[ $VERBOSE ]] && {
      echo "Taking snapshot (writeable mode)"
      }
    [[ ! $SAFE_MODE ]] && {
      btrfs subvolume snapshot "$SHARE_PATH" "$SNAPSHOT_PATH" || return 1
      }
  fi

  # Prune older backups
  [[ "$COUNT" != 0 ]] && [[ ${#SNAPS[@]} -ge $COUNT ]] && \
    echo "Pruning $(( ${#SNAPS[@]} - COUNT )) old snapshots..." && \
    for (( i=0; i <= $(( ${#SNAPS[@]} - COUNT - 1 )); i++ )); do
      [[ $VERBOSE ]] && {
        echo "   Deleting" ${SNAPS[$i]}
        }
      [[ ! $SAFE_MODE ]] && {
        btrfs subvolume delete "${SNAPS[$i]}" || return 1
        }
    done

  if [ $SAFE_MODE ]
  then
    echo "Skipping generation of snapshot $SNAPSHOT_NAME generated because safe mode is set."
  else
    echo "Snapshot $SNAPSHOT_NAME generated."
  fi

  return 0
}

btrfs-snp "$@"
