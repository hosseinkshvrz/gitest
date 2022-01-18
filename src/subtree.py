import os
import re
import subprocess
import sys

BASE_PATH = os.path.dirname(os.path.dirname(__file__))


class GumTreeDiff:
    def __init__(self):
        self.bin_path = os.path.join(BASE_PATH, 'gumtree-3.0.0/bin/gumtree')
        self.src_dir = os.path.join(BASE_PATH, 'diff')
        if not os.path.exists(self.src_dir):
            os.makedirs(self.src_dir)

    def get_diff(self, fname, b_content, a_content):
        fname = fname.split('/')[-1]
        b_file = os.path.join(self.src_dir, fname.split('.')[0] + '_b.' + fname.split('.')[1])
        a_file = os.path.join(self.src_dir, fname.split('.')[0] + '_a.' + fname.split('.')[1])
        with open(b_file, 'w') as file:
            file.write(b_content)
        with open(a_file, 'w') as file:
            file.write(a_content)
        command = subprocess.Popen([self.bin_path, 'dotdiff', b_file, a_file],
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        output, error = command.communicate()
        if error.decode('utf-8'):
            return None
        return output.decode('utf-8')

    def get_dotfiles(self, file):
        dot = self.get_diff(file[0], file[1], file[2])
        if dot is None:
            raise SyntaxError()
        lines = dot.splitlines()
        dotfiles = {
            'before': [],
            'after': []
        }
        current = 'before'
        node_pattern = '^n_[0-9]+_[0-9]+ \\[label=".+", color=(red|blue)\\];$'
        edge_pattern = '^n_[0-9]+_[0-9]+ -> n_[0-9]+_[0-9]+;$'

        for l in lines:
            if l == 'subgraph cluster_dst {':
                current = 'after'
            if not re.match(node_pattern, l) and not re.match(edge_pattern, l):
                continue
            dotfiles[current].append(l)

        return dotfiles['before'], dotfiles['after']


class SubTreeExtractor:
    def __init__(self, dot):
        self.dot = dot
        self.red_nodes = list()
        self.node_dict = dict()
        self.from_to = dict()  # mapping from src nodes to list of their dst nodes.
        self.to_from = dict()  # mapping from dst nodes to list of their src nodes.
        self.subtree_nodes = set()
        self.subtree_edges = set()

    def read_ast(self):
        node_pattern = '^n_[0-9]+_[0-9]+ \\[label=".+", color=(red|blue)\\];$'
        edge_pattern = '^n_[0-9]+_[0-9]+ -> n_[0-9]+_[0-9]+;$'
        for line in self.dot:
            if re.match(node_pattern, line):
                assert len(re.findall('^(.*) \\[label=".+", color=.+\\];$', line)) == 1
                id = re.findall('^(.*) \\[label=".+", color=.+\\];$', line)[0]
                assert len(re.findall('^n_[0-9]+_[0-9]+ \\[label="(.+)", color=.+\\];$', line)) == 1
                unclean_label = re.findall('^n_[0-9]+_[0-9]+ \\[label="(.+)", color=.+\\];$', line)[0]
                label = re.split('\\[[0-9]+', unclean_label)[0]
                assert len(re.findall('color=(red|blue)\\];$', line)) == 1
                color = re.findall('color=(red|blue)\\];$', line)[0]

                self.node_dict[id] = label
                if color == 'red':
                    self.red_nodes.append(id)

            elif re.match(edge_pattern, line):
                assert len(re.findall('^(.*) -> n_[0-9]+_[0-9]+;$', line)) == 1
                source = re.findall('^(.*) -> n_[0-9]+_[0-9]+;$', line)[0]
                assert len(re.findall('^n_[0-9]+_[0-9]+ -> (.*);$', line)) == 1
                dest = re.findall('^n_[0-9]+_[0-9]+ -> (.*);$', line)[0]

                if source not in self.from_to:
                    self.from_to[source] = [dest]
                else:
                    self.from_to[source].append(dest)
                if dest not in self.to_from:
                    self.to_from[dest] = [source]
                else:
                    self.to_from[dest].append(source)

            else:
                print(line, end='\t')

    def extract_subtree(self):
        self.read_ast()
        for n in self.red_nodes:
            self.subtree_nodes.add(n)
            if n in self.from_to:
                for d in self.from_to[n]:
                    self.subtree_nodes.add(d)
                    self.subtree_edges.add((n, d))
            if n in self.to_from:
                for s in self.to_from[n]:
                    self.subtree_nodes.add(s)
                    self.subtree_edges.add((s, n))
                    for d in self.from_to[s]:
                        self.subtree_nodes.add(d)
                        self.subtree_edges.add((s, d))

        vs = list(self.subtree_nodes)
        es = list(self.subtree_edges)
        colors = ['red' if node_id in self.red_nodes else "blue" for node_id in vs]
        features = [[self.node_dict[node_id]] if node_id in self.node_dict else ['unknown'] for node_id in vs]
        edges = [[], []]
        for src, dst in es:
            edges[0].append(vs.index(src))
            edges[1].append(vs.index(dst))

        return features, edges, colors

    def generate_dotfile(self):
        content = 'digraph G {\nnode [style=filled];\nsubgraph cluster_dst {\n'
        for node in self.subtree_nodes:
            content += '{} [label="{}", color={}];\n'.format(node,
                                                             self.node_dict[node],
                                                             'blue' if node not in self.red_nodes else 'red')
        for edge in self.subtree_edges:
            content += '{} -> {};\n'.format(edge[0], edge[1])
        content += '}\n;}\n'

        with open(os.path.join(BASE_PATH, 'src', 'diff.dot'), 'w') as file:
            file.write(content)


def store_subtrees(path, before, after):
    gumtree = GumTreeDiff()
    f = (path, before, after)
    try:
        b_dot, a_dot = gumtree.get_dotfiles(f)
    except SyntaxError:
        print('!!!!! source code has syntax error !!!!!')
        return None

    subtree = SubTreeExtractor(b_dot)
    b_subtree = subtree.extract_subtree()
    subtree = SubTreeExtractor(a_dot)
    a_subtree = subtree.extract_subtree()
    if len(b_subtree[0]) == 0 and len(a_subtree[0]) == 0:
        print('!!!!! before or after empty !!!!!')
    elif len(b_subtree[0]) == 0:
        b_subtree[0].append('None')
    elif len(a_subtree[0]) == 0:
        a_subtree[0].append('None')
    return path, b_subtree, a_subtree

