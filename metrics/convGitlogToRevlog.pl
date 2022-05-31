use strict;
use warnings;
no warnings qw(once);

# e.g., perl convGiglogToRevlog.pl ...

require 'metrics/util.pl';
# If you get "Can't locate util.pl in @INC",
# you might need to set the following path:
# export PERL5LIB=/Users/kamei/Research/sq_effort/scripts/

# project_name
my ($project_name) = ($ARGV[0]);

# file type for analysis
my @file_types = split(/,/,$ARGV[1]);

my $RELEASEDATE   = "";
if ($#ARGV >= 2){
    $RELEASEDATE = $ARGV[2];
}
my ($INT_PRE, $INT_POST) = (-180,180);

############################################
# readFile()
############################################
util::readFile($project_name);
### Item
my %commit_hash = %util::commit_hash;
my %tree_hash =%util::tree_hash;
my %author_name =%util::author_name;
my %author_date = %util::author_date;
my %committer_name = %util::committer_name;
my %committer_date = %util::committer_date;
my %change_type = %util::change_type;
my %changed_file = %util::changed_file;
my %changed_file_type = %util::changed_file_type;

### ID -> Item
my %hash_parent = %util::hash_parent;
my %hash_tree_hash = %util::hash_tree_hash;
my %hash_author_name = %util::hash_author_name;
my %hash_author_mail = %util::hash_author_mail;
my %hash_author_date = %util::hash_author_date;
my %hash_committer_name = %util::hash_committer_name;
my %hash_committer_mail = %util::hash_committer_mail;
my %hash_committer_date = %util::hash_committer_date;
my %hash_subject = %util::hash_subject;
my %hash_message = %util::hash_message;
my %hash_add_file = %util::hash_add_file;
my %hash_del_file = %util::hash_del_file;

### File -> ID
my %file_commit_hash = %util::file_commit_hash;

my $OUT = $project_name . ".revlog";
open(F_OUT, ">$OUT") or die ("Can't open file : $OUT\n");

#####################################################################
# each commit
#####################################################################
# convert git log to revlog
# @Yasu 20141012 I added changeid for review project
print F_OUT "fname,rev,committer_date,committer_name,comment,keyword exists?,number only?,bugids,numbers,refactor,add,del,author_date,author_name,changeid\n";
my ($name,$hash,$date,$auth,$comment,$bugid);

# @Yasu 20141012
# Sorted commits by commiter date
my $all=scalar(keys(%commit_hash));
my %sortdate = ();
foreach my $key(keys(%commit_hash)){
    $sortdate{$key} = $hash_committer_date{$key};
}
my @a = (sort {$sortdate{$b} <=> $sortdate{$a}} keys %commit_hash);
for(my $cnt=0; $cnt < $all; $cnt++){
    my $chng = $a[$cnt];
    #my $simple_committer_date = system($script);
    #    print "$simple_committer_date\n";

    #bugids and numbers ($b_keyword, $b_number, join(":",@bugid), join(":",@number))
    my $comment = $hash_subject{$chng} . " " . $hash_message{$chng} . "<br>";
    my @parseM = &parseMessage($comment);

    # @Yasu 20140828
    # for only post-release
    if($RELEASEDATE ne ""){
        my $diffdate = $hash_committer_date{$chng} - $RELEASEDATE;
        if(!(($diffdate <= ($INT_POST * 60 *  60 * 24)) && ($diffdate > 0))){ # in the x days after the release
            next;
        }
    }

# Hossein: No release date was set (most likely)

    while(my ($file) = each (%{ $hash_add_file{$chng}}  )){

        my ($loc,$complexity) = (-1,-1);
        my ($churn, $add, $del) = (0,0,0);

        # whether or not this file is related to our analysis
        my $type = $changed_file_type{$file};
        my $flag = 0;
        foreach my $t (@file_types){
            $flag++ if($t eq $type);
        }
        next if($flag ==0);

# Hossein: above filters files other than specified type (refer to setting tokens to see what they are for each project)

        # churn
        $add = $hash_add_file{$chng}{$file};
        $del = $hash_del_file{$chng}{$file};
        if($hash_del_file{$chng}{$file} eq "-"){
            print "[warning] $chng, $file, $add, $del\n";
            next; # due to this file might be a binary file
        }

# Hossein: above filters binary files (changed lines are shown as '-' in them) but I think it's okay because binary files
# are already filtered in the previous step

        $churn = $hash_add_file{$chng}{$file} + $hash_del_file{$chng}{$file};

        # output
        #print F_OUT "$proj_name,";
        #fname,rev,committer_date,committer_name,comment,keyword exists?,number only?,bugids,numbers,refactor,add,del,author_date,author_name,changeid
        print F_OUT "$file,";
        print F_OUT "$chng,";
        print F_OUT $hash_committer_date{$chng} . ",";
        print F_OUT $hash_committer_name{$chng} . ",";
        print F_OUT "$comment,"; # comment
        print F_OUT "$parseM[0],"; # keyword exists?
        print F_OUT "NULL,"; # number only?
        print F_OUT "$parseM[2],";
        print F_OUT "$parseM[3],";
        print F_OUT "NULL,"; # refactor
        print F_OUT "$add,";
        print F_OUT "$del,";
        print F_OUT $hash_author_date{$chng} . ",";
        print F_OUT $hash_author_name{$chng} . ",";

        my @chg_id = ();
        @chg_id = split(/:/, $parseM[4]);

        if($#chg_id != -1){
            print F_OUT $chg_id[$#chg_id] . "\n";
        }else{
            print F_OUT "\n";
        }

    }
}
close F_OUT;

# Hossein: apparently normal, merge, and fix commits extracted in util are not used here so no filtering in that regard


################################################################################
sub parseMessage(){
    (my $comment) = @_;
    chomp($comment);

    # variables
    my $b_keyword = 0; # including keywords releated to bugs?
    my $b_number = 0;  # including only numbers?

    my @bugid = ();  # bugID
    my @number = (); # numbers
    my @changeid = ();

    #    Change-Id: I8e407c602cda9c30eda458b0aacb7465787f22c4
    while ($comment =~ /\s*Change-Id: (.*?)<br>/ig){ push(@changeid,$1); }
    #while ($comment =~ /\s*Task-number: (.*?)<br>/ig){ push(@bugid,$1); }

    # for Chronium
    #while ($comment =~ /\s*Review URL: https:\/\/codereview.chromium.org\/(\d*)/ig){ push(@changeid,$1); }
    #while ($comment =~ /\s*BUG=(\d*)<br>/ig){ push(@bugid,$1); }
    #while ($comment =~ /\s*B=(\d*)<br>/ig){ push(@bugid,$1); }
    #BUG=417463
    #B=392309
    #Review URL: https://codereview.chromium.org/643063004

    # for Openstack nova
    while ($comment =~ /\s*Closes-Bug: #(\d*)<br>/ig){ push(@bugid,$1); }

    $comment =~ s/<br>//g; # delete specific characters

    #--- keywords
    if($comment =~ /(bug|bugs|fix|fixed|fixes|fix\s+for|fixes\s+for|defects|patch)/i){ $b_keyword = 1; }

    #--- only numbers
    if($comment =~ /^[0-9]+$/) { $b_number = 1; }
    while ($comment =~ /([0-9]+)/g){ push(@number, $1); }

    #--- bugid
    #while ($comment =~ /bug[# \t]*([0-9]+)/ig){ push(@bugid, $1); }
    ###while ($comment =~ /pr[# \t]*([0-9]+)/ig){ push(@bugid, $1); }
    #while ($comment =~ /show\_bug\.cgi\?id=([0-9]+)/ig){ push(@bugid, $1); }
    ###while ($comment =~ /\[([0-9]+)\]/ig){ push(@bugid, $1); }

    # for QT project
    #while ($comment =~ /\s*Task-number:.*?QTBUG.*?([0-9]+)/ig){ push(@bugid, $1); }

    # for Maven project
    #while ($comment =~ /MNG.*?([0-9]+)/ig){ push(@bugid, $1); }

    # for openldap project
    #while ($comment =~ /ITS.*?([0-9]+)/ig){ push(@bugid, $1); }

    # for postgre project
    #while ($comment =~ /CVE-(\d\d\d\d)-(\d\d\d\d)/ig){my $tmp = $1 . $2; push(@bugid, $tmp); }

    # for postgre project
    #while ($comment =~ /CVE-(\d\d\d\d)-(\d\d\d\d)/ig){my $tmp = $1 . $2; push(@bugid, $tmp); }

    # for clamav
    #bb #9017: tomsfastmath warning with zLinux on s390x
    #while ($comment =~ /bb[# \t]*([0-9]+)/ig){ push(@bugid, $1); }

    return ($b_keyword, $b_number, join(":",@bugid), join(":",@number), join(":",@changeid));
 }
