package util;

use strict;
use warnings;
use Cwd;
#use Date::Simple;
#use Time::Piece;
#use Time::Seconds;

# Define variables
our @field_names_main = ("commit_hash","tree_hash","parent_hashes",
"author_name","author_e-mail","author_date", "committer_name",
"committer_email","committer_date");
our @field_names_comment = ("subject","message");
my %convMonth = ('Jan' => '01', 'Feb' => '02', 'Mar' => '03', 'Apr' => '04', 'May' => '05', 'Jun' => '06',
'Jul' => '07', 'Aug' => '08', 'Sep' => '09', 'Oct' => '10', 'Nov' => '11', 'Dec' => '12');

### Item
our %commit_hash =();
our %tree_hash =();
our %author_name =();
our %author_date = ();
our %committer_name = ();
our %committer_date = ();
our %change_type  = ();
our %changed_file = ();
our %changed_file_type = ();

### ID -> Item
our %hash_parent = ();
our %hash_tree_hash = ();
our %hash_author_name = ();
our %hash_author_mail = ();
our %hash_author_date = ();
our %hash_committer_name = ();
our %hash_committer_mail = ();
our %hash_committer_date = ();
our %hash_subject = ();
our %hash_message = ();

our %hash_add_file = ();
our %hash_del_file = ();

our %file_commit_hash = ();

sub init(){
    ### Item
    %commit_hash =();
    %tree_hash =();
    %author_name =();
    %author_date = ();
    %committer_name = ();
    %committer_date = ();
    %change_type  = ();
    %changed_file = ();
    %changed_file_type = ();

    ### ID -> Item
    %hash_parent = ();
    %hash_tree_hash = ();
    %hash_author_name = ();
    %hash_author_mail = ();
    %hash_author_date = ();
    %hash_committer_name = ();
    %hash_committer_mail = ();
    %hash_committer_date = ();
    %hash_subject = ();
    %hash_message = ();

    %hash_add_file = ();
    %hash_del_file = ();

    %file_commit_hash = ();
}

sub readFile(){
    init();
    my $p_name = $_[0];

    my $changed_name = $p_name . "_git_changed.log";
    my $main_name    = $p_name . "_git_main.log";
    my $comment_name = $p_name . "_git_comment.log";

    ######### Read Main Log
    my $fname=$main_name;
    print("here");
    open(F_IN, $fname) or die ("File not found:" . Cwd::getcwd() . "/$fname\n");
    print("there");
    my @f = <F_IN>;
    for(my $i=0; $i <= $#f; $i++){
        chomp($f[$i]);

        if($f[$i] =~ /^\[\[SOF\]\](.*)\[\[EOF\]\]/){
            my $tmp = $1;
            $tmp =~ s/,//g;

            # for each column
            my @x = split(/<SEP>/, $tmp);

            my $author_date = $x[5];
            my $committer_date = $x[8];

            $commit_hash{$x[0]}=$i;
            $tree_hash{$x[1]}=1;
            $author_name{$x[3]}=1;
            $author_date{$author_date}=1;
            $committer_name{$x[6]}=1;
            $committer_date{$committer_date}=1;

            $tmp = $x[3] . $x[5]; # name + date
            $tmp =~ s/ //g;       # remove blanks

            ### ID -> Item
            $hash_parent{$x[0]} = $x[2];
            $hash_tree_hash{$x[0]} = $x[1];
            $hash_author_name{$x[0]} = $x[3];
            $hash_author_mail{$x[0]} = $x[4];
            $hash_author_date{$x[0]} = $author_date;
            $hash_committer_name{$x[0]} = $x[6];
            $hash_committer_mail{$x[0]} = $x[7];
            $hash_committer_date{$x[0]} = $committer_date;
        }else{
            print "Warning: Data Format in Line $i, $fname\n";
        }
    }
    close F_IN;

    ######### Read Comment Log
    $fname=$comment_name;
    open(F_IN, $fname) or die ("File not found:" . Cwd::getcwd() . "/$fname\n");

    my $tmp_hash="";
    my $tmp_message="";

    @f = <F_IN>;
    for(my $i=0; $i <= $#f; $i++){
        chomp($f[$i]);
        $f[$i] =~ s/,//g;

        if($f[$i] =~ /^\[\[SOF\]\](.*)/){
            # for each column
            my @x = split(/<SEP>/, $1);
            $tmp_hash=$x[0];
            $hash_subject{$tmp_hash} = $x[1];

            # change type: Merge or Fix or Normal
            if($x[1] =~ /merge/i){
                $change_type{$tmp_hash} = "MERGE";
            }elsif($x[1] =~ /(bug|bugs|fix|fixed|fixes|fix\s+for|fixes\s+for|defects|patch)/i){
                $change_type{$tmp_hash} = "FIX";
            }else{
                $change_type{$tmp_hash} = "NORMAL";
            }

            $tmp_message = $x[2];
            if($tmp_message =~ s/\[\[EOF\]\]//){
                $hash_message{$tmp_hash} = $tmp_message;
            }
        }else{
            if($f[$i] =~ /\[\[EOF\]\]/){
                $hash_message{$tmp_hash} = $tmp_message;
            }else{
                $tmp_message = $tmp_message . "<br>" . $f[$i];
            }
        }
    }
    close F_IN;

    ######### Read Changed Files Log
    $fname=$changed_name;
    open(F_IN, $fname) or die ("File not found:" . Cwd::getcwd() . "/$fname\n");

    $tmp_hash="";
    @f = <F_IN>;
    my $tmp_type;
    for(my $i=0; $i <= $#f; $i++){
        chomp($f[$i]);

        if($f[$i] =~ /^\[\[SOF\]\](.*)\[\[EOF\]\]/){
            $tmp_hash=$1;
        }else{
            my @x = split(/\t/, $f[$i]);
            if($#x == 2){
                $file_commit_hash{$x[2]}{$tmp_hash} = 1;  # file -> hash
                $changed_file{$x[2]}=1;
                $hash_add_file{$tmp_hash}{$x[2]} = $x[0]; # hash -> file and churn
                $hash_del_file{$tmp_hash}{$x[2]} = $x[1]; # hash -> file and churn

                $tmp_type = $x[2];
                $tmp_type =~ s/(.*)}$/$1/; # to clean up cinder/tests/{test_emc.py => test_emc_smis.py}
                $tmp_type =~ s/(.*\.)(.*)/$2/;
                $changed_file_type{$x[2]} = $tmp_type;
            }
        }
    }
    close F_IN;
}

# util::getDate()
sub dateISO2Epoch(){
    my $x = $_[0];
    my $t = Time::Piece->strptime($x, "%a %b %d %k:%M:%S %Y %z"); #Fri Aug 1 15:41:26 2014 +0900
    return $t->epoch;
}

1;
