import math
import os
import subprocess
import sys
import time

from predict import main
from subtree import store_subtrees

start = time.time()
BASE_PATH = os.path.dirname(os.path.dirname(__file__))


def time_since(since):
    now = time.time()
    s = now - since
    h = math.floor(s / 3600)
    s -= h * 3600
    m = math.floor(s / 60)
    s -= m * 60
    return '{}h {}min {:.2f} sec'.format(h, m, s)


command = subprocess.Popen(['git', 'status', '--porcelain'],
                           stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE)
output, error = command.communicate()
if error.decode('utf-8'):
    sys.exit(-1)
output = output.decode('utf-8').splitlines()

modifieds = []
for line in output:
    change_type, path = line.split()
    if change_type == 'M':
        modifieds.append(path)

files = []
for m in modifieds:
    command = subprocess.Popen(['git', 'show', 'HEAD:{}'.format(m)],
                               stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)
    output, error = command.communicate()
    if error.decode('utf-8'):
        sys.exit(-1)
    before = output.decode('utf-8')
    command = subprocess.Popen(['cat', '{}'.format(os.path.join(BASE_PATH, m))],
                               stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)
    output, error = command.communicate()
    if error.decode('utf-8'):
        sys.exit(-1)
    after = output.decode('utf-8')
    f_subtree = store_subtrees(m, before, after)
    if f_subtree:
        files.append(f_subtree)
# with open('diff/commit.json', 'w') as fp:
#     json.dump(files, fp)
if all(f is None for f in files):
    print('nothing to evaluate')
else:
    prd = main(files)
    print(prd)

print(time_since(start))
sys.exit(-1)


# paths=()
# while read line ; do
# 	IFS=' ' read -r -a array <<< "$line"
# 	if [[ "${array[0]}" = "A" ]]
# 	then
# 		IFS='/' read -r -a filename <<< "${array[1]}"
# 		fname=${filename[-1]}
# 		IFS='.' read -r -a namext <<< "$fname"
# #		before=$(git show HEAD:"${array[1]}")
# #		after=$(cat "${array[1]}")
# 		paths+=( "$fname" )
# 		echo $paths
# 	fi
# 	done < <(git status --porcelain)
# 	echo "${paths}"
# 	python3 src/predict.py "${paths}" "before" "after"
