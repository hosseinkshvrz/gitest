from pydriller import Git

repo = Git('../repos/bookkeeper')
commit = repo.get_commit('370d785')
lines = 0
for m in commit.modified_files:
    if m.source_code_before:
        lines += m.source_code.count('\n')
        with open('../files/{}'.format(m.filename), 'w') as fp:
            fp.write(m.source_code_before)
print(lines)
