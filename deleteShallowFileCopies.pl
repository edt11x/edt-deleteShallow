#!/usr/bin/env perl

use strict;
use warnings;

use Digest::SHA qw(sha1_base64 sha256_base64 sha512_base64);
use File::Basename;
use File::Find ();
use Getopt::Long;
use IO::All;
use Pod::Usage;
use Scalar::MoreUtils qw( empty );

# Set the variable $File::Find::dont_use_nlink if you're using AFS,
# since AFS cheats.

# for the convenience of &wanted calls, including -eval statements:
use vars qw/*name *dir *prune/;
*name   = *File::Find::name;
*dir    = *File::Find::dir;
*prune  = *File::Find::prune;

my ( $man,$help,$verbose,$thisFile );
my $startDir = ".";
my %fileHash;
my ( @a, @pruneList );

sub prompt {
    my ($query) = @_; # take a prompt string as argument
    local $| = 1; # activate autoflush to immediately show the prompt
    print $query;
    chomp(my $answer = <STDIN>);
    return $answer;
}

sub prompt_yn {
  my ($query) = @_;
  my $answer = prompt("$query (y/n): ");
  return lc($answer) eq 'y';
}

sub wanted {
    my ($dev,$ino,$mode,$nlink,$uid,$gid);
    my $pruneThis = 0;
    $thisFile = $_;

    foreach my $thisPrune (@pruneList) {
        if (/^\Q$thisPrune\E\z/s) {
            $pruneThis = 1;
            print("Pruning $thisFile\n") if $verbose;
        }
    }

    if ($pruneThis) {
        $File::Find::prune = 1;
    } elsif ((($dev,$ino,$mode,$nlink,$uid,$gid) = lstat($thisFile)) &&
             (-f $thisFile) && (-r $thisFile)) {
        # for each file, we need to collect in a list of information
        $fileHash{$name}{sha1} = sha1_base64(io("$thisFile")->all);
        $fileHash{$name}{sha256} = sha256_base64(io("$thisFile")->all);
        $fileHash{$name}{sha512} = sha512_base64(io("$thisFile")->all);
        $fileHash{$name}{fileSize} = -s $thisFile;
        if ($verbose) {
            print("$name\n");
            print("  Size    : ", $fileHash{$name}{fileSize}, "\n");
            print("  SHA-1   : ", $fileHash{$name}{sha1}, "\n");
            print("  SHA-256 : ", $fileHash{$name}{sha256}, "\n");
            print("  SHA-512 : ", $fileHash{$name}{sha512}, "\n");
            print("\n");
        }
    }
}

GetOptions("help|?"                 => \$help, 
           "man"                    => \$man, 
           "start=s"                => \$startDir,
           "exclude=s{2}"           => \@a,
           "prune=s"                => \@pruneList,
           "verbose"                => \$verbose) or pod2usage(2);
pod2usage(-exitval => 0) if $help;
pod2usage(-exitval => 0, -verbose => 2) if $man;
pod2usage(-msg => "Unexpected argument : " . $ARGV[0], -exitval => 3) if (@ARGV != 0);

print("Starting File Find...\n") if ($verbose);
# Traverse desired filesystems
File::Find::find({wanted => \&wanted}, $startDir);
print("File Find DONE.\n\n") if ($verbose);

print("Starting File Match...\n") if ($verbose);
# for each file
foreach my $key (keys %fileHash) {
    # see if we can find a match
    # The psuedo code for this
    #
    # for each file
    #   if there is a file with a matching basename whose path is longer
    #       if the SHA256 hash of the two files match
    #           ask if you want to delete the more shallow file, the shorter file path
    #
    foreach my $matchKey (keys %fileHash) {
        if ((basename($key) eq basename($matchKey)) &&
            (!empty(basename($key))) &&
            (!empty(basename($matchKey))) &&
            ($key ne $matchKey)) {
            my $excludeThisCompare = 0;
            # loop through the excluded combinations
            for (my $i = 0; $i < $#a; $i += 2) {
                if ((!empty($a[$i])) &&
                    (!empty($a[$i+1]))) {
                    print("Checking exclusion ", $a[$i], " vs ", $a[$i+1], "\n") if $verbose;
                    print("  -- key      -", substr($key, 0, length($a[$i])),"-\n") if $verbose;
                    print("  -- matchkey -", substr($key, 0, length($a[$i])),"-\n") if $verbose;
                    if (($a[$i] eq substr($key, 0, length($a[$i]))) &&
                        ($a[$i+1] eq substr($matchKey, 0, length($a[$i+1])))) {
                        $excludeThisCompare = 1;
                    }
                    if (($a[$i] eq substr($matchKey, 0, length($a[$i]))) &&
                        ($a[$i+1] eq substr($key, 0, length($a[$i+1])))) {
                        $excludeThisCompare = 1;
                    }
                }
            }
            print "This match is excluded\n$key\n$matchKey\n\n" if (($verbose) && ($excludeThisCompare));

            # note we need to check again if the file exists,
            # because we may have deleted it.
            # I really really want to make sure these are the
            # same files, that they have the same contents.
            # So I do overly redundant checks to make sure the
            # files are the same.
            if ((!$excludeThisCompare) &&
                (exists $fileHash{$key}{sha1}) &&
                (exists $fileHash{$matchKey}{sha1}) &&
                ($fileHash{$key}{sha1} eq $fileHash{$matchKey}{sha1}) &&
                (exists $fileHash{$key}{sha256}) &&
                (exists $fileHash{$matchKey}{sha256}) &&
                ($fileHash{$key}{sha256} eq $fileHash{$matchKey}{sha256}) &&
                (exists $fileHash{$key}{sha512}) &&
                (exists $fileHash{$matchKey}{sha512}) &&
                ($fileHash{$key}{sha512} eq $fileHash{$matchKey}{sha512}) &&
                (exists $fileHash{$key}{fileSize}) &&
                (exists $fileHash{$matchKey}{fileSize}) &&
                ($fileHash{$key}{fileSize} == $fileHash{$matchKey}{fileSize}) &&
                (-f $key) && (-f $matchKey)) {
                print "\nFile match\n$key\n$matchKey\n\n";
                if (length($key) >= length($matchKey)) {
                    if (prompt_yn("\n$matchKey appears to be the shallow path, delete this path (y/n) ? ")) {
                        print "unlink($matchKey)\n" if ($verbose);
                        unlink($matchKey);
                    }
                } else {
                    if (prompt_yn("\n$key appears to be the shallow path, delete this path (y/n) ? ")) {
                        print "unlink($key)\n" if ($verbose);
                        unlink($key);
                    }
                }
                print("\n");
            }
        }
    }
}

print("File Match DONE.\n\n") if ($verbose);

print("All Done.\n\n") if ($verbose);
exit(0);

__END__

MANUAL_PAGE
=head1 NAME

deleteShallowFileCopies.pl  - delete shallow copies of file duplicates

=head1 SYNOPSIS

deleteShallowFileCopies.pl 

This perl script interactively deletes shallow copies of files that are
duplicates of other files that are stored deeper in the file system. It 
is not uncommon for me to decide to organize an overly crowded directory
into subdirectories. It is also not uncommon for me to leave copies behind.
This perl scripts looks at each file and looks to see if there is a duplicate
deeper in the file system. Since some of my file sync operations such as
Dropbox modify file times, I need to do this comparison based on something
more intrinsic like a sha256 hash of the file.

There are some extra checks in here, but I really want to know that there
are two reliable copies before I delete one of them.

EXAMPLES

    $ cd some_directory_to_evaluate
    $ deleteShallowFileCopies.sh
    remove file foo.bar?

    $ deleteShallowFileCopies.sh --start . --exclude ./a ./b --prune .DS_Store

    $ deleteShallowFileCopies.sh --exclude ./a ./b --exclude ./c ./d

  Options:
    --help                   brief help message
    --man                    manual page
    --verbose                info about everything, even in the into dir
    --start dir_to_start_in  specify the directory to start in
    --exclude ./a ./b        exclude comparing files in directories a & b
    --prune name_to_prune    directory or file names to disregard

=head1 OPTIONS

=over 8

=item B<help>

Print a brief help message and exit

=item B<man>

Print the manual page and exit

=item B<verbose>

This will cause something to be printed about every file, even the ones in the
into directory.

=item B<start>

The argument to this will specify the directory to start in.

=item B<exclude>

This takes a pair of arguments, two directories that you do not want to compare. For
example if you do not want to compare directories ./a and ./b you can add the 
argument "--exclude ./a ./b". Any other combinations will be compared, for example
"./c" and "./a". You can specify the exclude argument many times with separate pairs.

=item B<prune>

This takes an argument, a directory or a file name that we will truncate or prune
the search when that name is encountered. If I specify "--prune .svn", it will not
evaluate any of the files or directories under any directory named ".svn".

=back

=head1 DESCRIPTION

This perl script interactively deletes shallow copies of files that are
duplicates of other files that are stored deeper in the file system.

=cut

