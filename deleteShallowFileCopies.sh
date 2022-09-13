#!/bin/bash
die() {
    set +x
    echo >&2 "$@"
    usage
    exit 1
}

function usage {
    set +x
    echo "Usage: deleteShallowFileCopies.sh"
    exit 1
}

function man {
    set +x
    cat << MANUAL_PAGE
NAME

    deleteShallowFileCopies.sh  - delete the shallow copies of file duplicates

SYNOPSIS

    deleteShallowFileCopies.sh 


DESCRIPTION

This shell script interactively deletes shallow copies of files that are
duplicates of other files that are stored deeper in the file system. It 
is not uncommon for me to decide to organize an overly crowded directory
into subdirectories. It is also not uncommon for me to leave copies behind.
This shell scripts looks at each file and looks to see if there is a duplicate
deeper in the file system. Since some of my file sync operations such as
Dropbox modify file times, I need to do this comparison based on something
more intrinsic like a sha256 hash of the file.

There are some extra checks in here, but I really want to know that there
are two reliable copies before I delete one of them.

EXAMPLES

    $ cd some_directory_to_evaluate
    $ deleteShallowFileCopies.sh
    remove file foo.bar?


MANUAL_PAGE
exit 1
}

unameOut="$(uname -s)"
export machine=Linux
case "${unameOut}" in
    Linux*)     machine=Linux;;
    Darwin*)    machine=Darwin;;
    CYGWIN*)    machine=Cygwin;;
    MINGW*)     machine=MinGw;;
    *)          machine="UNKNOWN:${unameOut}"
esac

OPENSSLCMD="openssl dgst -sha512"

SIZECMD='stat --printf=%s'
if [ $machine == Darwin ]
then
    SIZECMD='stat -f%z'
fi

VERBOSE=FALSE
MORE_PRUNES=""
while test -n "$1"; do
    case "$1" in
        -h|--help)
            usage
            exit 1
            ;;
        -v|--verbose)
            VERBOSE=TRUE
            shift
            ;;
        -p|--prune)
            MORE_PRUNES="$MORE_PRUNES -path \"$2\" -prune -o"
            shift 2
            ;;
    esac
done

echo MORE_PRUNES --$MORE_PRUNES--

# The psuedo code for this
#
# for each file
#   if there is a file with a matching basename whose path is longer
#       if the SHA256 hash of the two files match
#           ask if you want to delete the more shallow file
#

# pipe it into while to handle files with spaces in the path
# need to ignore some of the Apple file system spew like
# .DS_Store, .localized
# Other Apple machines Documents directories reflected in the
# Documents folder, eg "Documents - Alice"
find . -path 'Documents - *' -prune -o $MORE_PRUNES -type f ! -name .DS_Store ! -name .localized ! -name .FBCIndex ! -name .FBCSemaphoreFile -print0 | while read -d $'\0' i
do
    BASEFILE=$(basename "$i")
    $OPENSSLCMD "$i" > /dev/null 2>&1
    if [ $? != 0 ]
    then
        echo "openssl FAILED on $i - do not trust continuing, we are done."
        exit 1
    fi
    $SIZECMD "$i" > /dev/null 2>&1
    if [ $? != 0 ]
    then
        echo $SIZECMD "$i"
        $SIZECMD "$i"
        echo "stat FAILED on $i - do not trust continuing, we are done."
        exit 1
    fi
    THATHASH=`$OPENSSLCMD "$i" | awk '{ print $NF }'`
    THATSIZE=`$SIZECMD "$i"`
    THATNUMCHARS=$(echo "$i" | wc -c)
    find . -type d -name 'Documents - *' -prune -o -type f -name "$BASEFILE" -print0 | while read -d $'\0' j
    do
        $OPENSSLCMD "$j" > /dev/null 2>&1
        if [ $? != 0 ]
        then
            echo "openssl FAILED on $i - do not trust continuing, we are done."
            exit 1
        fi
        $SIZECMD "$j" > /dev/null 2>&1
        if [ $? != 0 ]
        then
            echo $SIZECMD "$j"
            $SIZECMD "$j"
            echo "stat FAILED on $i - do not trust continuing, we are done."
            exit 1
        fi
        THISHASH=`$OPENSSLCMD "$j" | awk '{ print $NF }'`
        THISSIZE=`$SIZECMD "$j"`
        THISNUMCHARS=$(echo "$j" | wc -c)
        if [ $VERBOSE == TRUE ]
        then
            echo "Checking $i $THISHASH $THISSIZE"
        fi
        # If that path is longer, ie if that path is deeper
        if [ $THISNUMCHARS -gt $THATNUMCHARS ]
        then
            if [ $VERBOSE == TRUE ]
            then
                echo $THISSIZE $THATSIZE
            fi
            # if the size matches
            if [ $THISSIZE -eq $THATSIZE ]
            then
                # if the sha256 hashes match
                if [ x"$THISHASH" == x"$THATHASH" ]
                then
                    echo ------------------------------------
                    echo "This file path is longer -- "
                    echo "Chars $THISNUMCHARS - $j"
                    echo " -- Hash  $THISHASH Size $THISSIZE"
                    echo "Than this file -- "
                    echo "Chars $THATNUMCHARS - $i"
                    echo " -- Hash  $THATHASH Size $THATSIZE"
                    echo /bin/rm -i "$i"
                    # redirect from tty to read the answer not the next file 
                    # from the find command
                    /bin/rm -i "$i" < /dev/tty
                    echo
                    echo ------------------------------------
                    break
                fi
            fi
        fi
    done
done

