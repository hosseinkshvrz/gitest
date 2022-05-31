############################################
# This script calculates metrics
#   ARGV: project_name
#     In: log data
#    Out: metrics data
############################################
use strict;
use warnings;
no warnings qw(once);
use Time::Piece;
use Time::HiRes qw(usleep ualarm gettimeofday tv_interval);
use Getopt::Long qw(:config posix_default no_ignore_case gnu_compat);

############################################
# Setting
############################################
my $MIN_TIME = 60*60*24*365*100; # 100 year
my $DEBUG=1;
my $TEST=0;
# my $DIR_INPUT  = "/home/kamei/HIC/data_logs/";
# my $DIR_SCRIPT = "/home/kamei/HIC/scripts/";
# my $DIR_OUTPUT = "/home/kamei/HIC/data_logs/";
# chdir($DIR_SCRIPT) or die ("ERROR chdir $DIR_SCRIPT $!\n");
require 'metrics/util.pl';

my $project_name = $ARGV[0];
$project_name = "test.$project_name" if($TEST);
############################################
# readFile()
############################################
# chdir($DIR_INPUT) or die ("ERROR chdir $!\n");
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

### HASHID -> Item
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

### File -> HASHID
my %file_commit_hash = %util::file_commit_hash;

############################################
# calcEntropy
#  In: array of churns in one change
# Out: entropy
sub calcEntropy{
  (my @mods) = @_;
  my ($ent,$sum) = (0,0);

  ### calc all modifies for denominator
  for my $mod (@mods){
    $sum = $sum + $mod;
  }
  return 0 if($sum==0);

  for my $mod (@mods){
    my $prob = $mod/$sum;
    $ent = $ent + ((-1) * $prob * log2($prob)) if($prob!=0);
  }

  return $ent;
}

sub log2{
  my $x = shift;
  return log($x) / log(2);
}

############################################

# my $OUT = $DIR_OUTPUT . $project_name . ".changes";
my $OUT = $project_name . ".changes";
open(F_OUT, ">$OUT") or die ("Can't open file : $OUT\n");
print F_OUT "\"HASHID\",\"AUTHOR_NAME\",\"AUTHOR_DATE\",\"COMMITTER_DATE\",\"CHURN\",\"ADD\",\"DEL\",\"CHANGE_TYPE\",\"NS\",\"ND\",\"NF\",\"Ent\",\"NDEV\",\"AGE\",\"NFC\",\"EXP\",\"REXP\",\"SEXP\"\n";

my ($churn, $add, $del,$length,$NS,$ND,$NF,$ENT,$NDEV,$AGE,$NFC,$EXP,$REXP,$SEXP);
my (@churns,%count_NS,%count_ND,%count_NF,%min_time,@ns_chng,@dir_chng,@nf_chng);

## 昇順:101, 158

# Main Function
my $all=scalar(keys(%commit_hash));
#my @a = (sort { $commit_hash{$a} <=> $commit_hash{$b} } keys %commit_hash);
#my @a = (sort { $hash_author_date{$b} <=> $hash_author_date{$a}} keys %commit_hash);     # 新しいコミットから
my @a = (sort { $hash_author_date{$a} <=> $hash_author_date{$b}} keys %commit_hash);      # 古いコミットから
my $t0 = [gettimeofday];
for(my $cnt=0; $cnt < $all; $cnt++){
   my $chng = $a[$cnt];
   if($cnt%1000 == 0){
      my $t1 = [gettimeofday];
      print "    TIME: " . (tv_interval($t0, $t1))/1000 ."sec\n" if($DEBUG);
   }
   print "    ($cnt/$all)$chng\n" if($DEBUG);

   ($churn, $add, $del,$length,$NS,$ND,$NF,$ENT,$NDEV,$AGE,$NFC,$EXP,$REXP,$SEXP) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0);
   @churns = ();
   %count_NS = ();
   %count_ND = ();
   %count_NF = ();
   %min_time = ();
   @ns_chng = ();
   @dir_chng = ();
   @nf_chng = ();

   #################################################################
   # Modified Files
   #################################################################
   my @files = keys %{ $hash_add_file{$chng} };
   my ($tmp_add, $tmp_del) = (0, 0);
   for my $file (@files){
     if($hash_add_file{$chng}{$file} ne "-"){
       $tmp_add = $hash_add_file{$chng}{$file};
       $add = $add + $hash_add_file{$chng}{$file}; # LA: mid-flow + DONE
     }
     if($hash_del_file{$chng}{$file} ne "-"){
       $tmp_del = $hash_del_file{$chng}{$file};
       $del = $del + $hash_del_file{$chng}{$file}; # LD: mid-flow + DONE
     }
     $churn = $add + $del;                  # CHURN: mid-flow + DONE
     push(@churns, ($tmp_add + $tmp_del));  # ready: churns for calculation of entropy

     ### NS, ND, NF: mid-flow
     @dir_chng = split(/\//, $file);
     $length = @dir_chng;
     $count_NS{$dir_chng[0]}++;                  #dir_chng[0] : subsystem
     $count_ND{$dir_chng[$length-2]}++;          #dir_chng[$length-2] : module
     $count_NF{$file}++;                         #file
   }

   ### NS, ND, NF
   @ns_chng = keys %count_NS;
   $NS = @ns_chng;             # NS: DONE
   $ND = keys %count_ND;       # ND: DONE
   @nf_chng = keys %count_NF;
   $NF = @nf_chng;             # NF: DONE
   for my $set_time (@nf_chng){           # $set_time means file name to use set_time
     $min_time{$set_time} = $MIN_TIME;    # ready: calculation of age
   }

   ### ENT: DONE
   $ENT = calcEntropy(@churns);

   my ($file_chng,$file_prev_chng);
   my %count_NDEV = ();

   #################################################################
   ### HISTORY  $a[$cnt];
   #################################################################
#  for(my $z=($cnt+1); $z < $all; $z++){ # 新しいコミットから
   for(my $z=($cnt-1); $z >= 0; $z--){   # 古いコミットから
     my $prev_chng = $a[$z];
     if ($hash_author_date{$chng} <= $hash_author_date{$prev_chng}){
       next;
     } else { #HISTORY ($NDEV,$AGE,$NFC,$EXP,$REXP,$SEXP)
       my @files_prev_chng = keys %{ $hash_add_file{$prev_chng} };
       my @dir_prev_chng = ();
       my %count_NS_prev = ();
       my %count_NF_prev = ();

       for $file_prev_chng (@files_prev_chng){
         @dir_prev_chng = split(/\//, $file_prev_chng);
         $count_NS_prev{$dir_prev_chng[0]}++;
         $count_NF_prev{$file_prev_chng}++;
       }

       for $file_chng (@nf_chng){
         if(exists($count_NF_prev{$file_chng})){			#ファイル名が同じものに対して$NDEV,$AGE,$NFCの計測を行う
           $count_NDEV{$hash_author_name{$prev_chng}}++;
           $NFC++;											#$NFC: mid-flow

           # For AGE
           my $diff_time = $hash_author_date{$chng} - $hash_author_date{$prev_chng};
           if ($min_time{$file_chng} > $diff_time){
             $min_time{$file_chng} = $diff_time;			#直前に変更されたファイルとその期間の計測
           }
         }
       }
       $NDEV = keys %count_NDEV;							#$NDEV: mid-flow

       #################################################################
       ### EXPs
       #################################################################
       if (($hash_author_name{$chng} cmp $hash_author_name{$prev_chng})==0){
         $EXP++;											#$EXP: mid-flow + DONE

         my $n = $hash_author_date{$chng} - $hash_author_date{$prev_chng};
         $n = sprintf("%d", $n/(60*60*24*365)) + 1;
         $REXP = $REXP + 1/$n;								#$REXP: $n : (n years ago + 1)

         for $file_chng (@ns_chng){
           if (exists($count_NS_prev{$file_chng})){
             $SEXP++;										#$SEXP: mid-flow
           }
         }
         if ($NS != 0){
           $SEXP = $SEXP/$NS;								#$SEXP: DONE
         }
       }
     }
   }

   my $tmp;
   for $file_chng (@nf_chng){
     if ($min_time{$file_chng} == $MIN_TIME){
       $min_time{$file_chng} = 0;							# if this file is not changed in $MIN_TIME
     }
     $tmp = sprintf("%d", $min_time{$file_chng}/(60*60*24));
     $AGE = $AGE + $tmp;									#$AGE: 途中    $tmp : ($tmp日前の変更)
   }

   if ($NF != 0){
       $NDEV = $NDEV/$NF;									#$NDEV: DONE
       $AGE = $AGE/$NF;										#$AGE : DONE
       $NFC = $NFC/$NF;										#$NFC : DONE
   }

   #################################################################
   # Print Out
   #################################################################
   print F_OUT "\"$chng\",\"";
   print F_OUT $hash_author_name{$chng} . "\",\"";
   print F_OUT $hash_author_date{$chng} . "\",\"";
   print F_OUT $hash_committer_date{$chng} . "\",\"";
   print F_OUT $churn . "\",\"";
   print F_OUT $add . "\",\"";#LA
   print F_OUT $del . "\",\"";#LD
   print F_OUT $change_type{$chng} . "\",\"";
   #################################################################
   print F_OUT $NS . "\",\"";
   print F_OUT $ND . "\",\"";
   print F_OUT $NF . "\",\"";
   print F_OUT $ENT . "\",\"";
   print F_OUT $NDEV . "\",\"";
   print F_OUT $AGE . "\",\"";
   print F_OUT $NFC . "\",\"";
   print F_OUT $EXP . "\",\"";
   print F_OUT $REXP . "\",\"";
   print F_OUT $SEXP . "\"\n";
}
close F_OUT;
