#! /bin/bash
# sh run.sh setting.txt

#parent_path=$( cd "$(dirname "${BASH_SOURCE[0]}")" ; pwd -P )
#cd ${parent_path}

while read DIR_SCRIPT DIR_TARGET PROJECT EXT; do
  echo "1"
  perl ${DIR_SCRIPT}/get_gitlog.pl ${PROJECT}
  echo "2"
  perl ${DIR_SCRIPT}/convGitlogToRevlog.pl ${PROJECT} ${EXT}
  echo "3"
  perl ${DIR_SCRIPT}/calcMetrics.pl $PROJECT  > ${DIR_TARGET}/${PROJECT}.calcMetrics 2>&1
done <$1

