use strict;
use warnings;

# 2014/04/03 @Yasu I deleted "since".
# 2014/04/03 @Yasu date is formatted as GMT for Time::Piece
# 2014/06/15 @Yasu ignore $TAG
# 2014/07/31 @Yasu change separator
# 2014/10/10 @Yasu two options for after and before

chdir("metrics");

my $project_name = $ARGV[0];
$project_name =~ s/\//_/g;  # replace / -> _ in project_name
my $period = "";

if($#ARGV >= 1){
    my $after = "$ARGV[1]-$ARGV[2]-$ARGV[3]";
    my $before = "$ARGV[4]-$ARGV[5]-$ARGV[6]";
    $period = "--after=\"" . $after . "\" --before=\"" . $before . "\"";
}

# my $TAG = $ARGV[1];
my $TAG = "";

# main log
my $script = "git log $period --pretty=format:\"[[SOF]]%H<SEP>%T<SEP>%P<SEP>%an<SEP>%ae<SEP>%at<SEP>%cn<SEP>%ce<SEP>%ct[[EOF]]\" > " . $project_name . "_git_main.log";
#print "\n$script\n";
system($script);
$script = "echo \"\" >> " . $project_name . "_git_main.log";
system($script);

# comment log
$script = "git log $period --pretty=format:\"[[SOF]]%H<SEP>%s<SEP>%b[[EOF]]\" > " . $project_name . "_git_comment.log";
system($script);
$script = "echo \"\" >> " . $project_name . "_git_comment.log";
system($script);

# changed file log
$script = "git log $period --pretty=format:\"[[SOF]]%H[[EOF]]\" --numstat > " . $project_name . "_git_changed.log";
system($script);
$script = "echo \"\" >> " . $project_name . "_git_changed.log";
system($script);
