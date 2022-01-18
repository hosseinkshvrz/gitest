from pydriller import Git

repo = Git('../repos/bookkeeper')
commit = repo.get_commit('a65e888b25eb966921ff39032e04f367a553d634')
for m in commit.modified_files:
    with open('../files/{}'.format(m.filename)) as fp:
        fp.write(m.source_code_before)
