import os
import pickle

import numpy as np
import scipy.sparse as sp
import torch

from models import JITGNN

BASE_PATH = os.path.dirname(os.path.dirname(__file__))
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")


class Dataset:
    def __init__(self, vectorizer, special_token):
        self.vectorizer_model = vectorizer
        self.special_token = special_token
        # self.metrics = None
        # self.load_metrics(metrics_file)

    # def load_metrics(self, metrics_file):
    #     self.metrics = pd.read_csv(os.path.join(data_path, metrics_file))
    #     # self.metrics = self.metrics.drop(
    #     #     ['author_date', 'bugcount', 'fixcount', 'revd', 'tcmt', 'oexp', 'orexp', 'osexp', 'osawr', 'project',
    #     #      'buggy', 'fix'],
    #     #     axis=1, errors='ignore')
    #     self.metrics = self.metrics[['commit_id', 'la', 'ld', 'nf', 'nd', 'ns', 'ent',
    #                                  'ndev', 'age', 'nuc', 'aexp', 'arexp', 'asexp']]
    #     self.metrics = self.metrics.fillna(value=0)

    @staticmethod
    def normalize(mx):
        """Row-normalize sparse matrix"""
        rowsum = np.array(mx.sum(1))
        r_inv = np.power(rowsum, -1).flatten()
        r_inv[np.isinf(r_inv)] = 0.
        r_mat_inv = sp.diags(r_inv)
        mx = r_mat_inv.dot(mx)
        return mx

    @staticmethod
    def sparse_mx_to_torch_sparse_tensor(sparse_mx):
        """Convert a scipy sparse matrix to a torch sparse tensor."""
        sparse_mx = sparse_mx.tocoo().astype(np.float32)
        indices = torch.from_numpy(
            np.vstack((sparse_mx.row, sparse_mx.col)).astype(np.int64))
        values = torch.from_numpy(sparse_mx.data)
        shape = torch.Size(sparse_mx.shape)
        return torch.sparse.FloatTensor(indices, values, shape)

    def get_adjacency_matrix(self, n_nodes, src, dst):
        edges = np.array([src, dst]).T
        adj = sp.coo_matrix((np.ones(edges.shape[0]), (edges[:, 0], edges[:, 1])),
                            shape=(n_nodes, n_nodes),
                            dtype=np.float32)

        # build symmetric adjacency matrix
        adj = adj + adj.T.multiply(adj.T > adj) - adj.multiply(adj.T > adj)
        # add supernode
        adj = sp.vstack([adj, np.ones((1, adj.shape[1]), dtype=np.float32)])
        adj = sp.hstack([adj, np.zeros((adj.shape[0], 1), dtype=np.float32)])
        adj = self.normalize(adj + sp.eye(adj.shape[0]))
        adj = self.sparse_mx_to_torch_sparse_tensor(adj)
        return adj

    def get_embedding(self, file_node_tokens, colors):
        for i, node_feat in enumerate(file_node_tokens):
            file_node_tokens[i] = node_feat.strip()
            if node_feat == 'N o n e':
                file_node_tokens[i] = 'None'
                colors.insert(i, 'blue')
                assert colors[i] == 'blue'
            if self.special_token:
                if ':' in node_feat:
                    feat_type = node_feat.split(':')[0]
                    file_node_tokens[i] = feat_type + ' ' + '<' + feat_type[
                                                                  :3].upper() + '>'  # e.g. number: 14 -> number <NUM>
        # fix the data later to remove the code above.
        features = self.vectorizer_model.transform(file_node_tokens).astype(np.float32)
        # add color feature at the end of features
        color_feat = [1 if c == 'red' else 0 for c in colors]
        features = sp.hstack([features, np.array(color_feat, dtype=np.float32).reshape(-1, 1)])
        # add supernode
        features = sp.hstack([features, np.zeros((features.shape[0], 1), dtype=np.float32)])
        supernode_feat = np.zeros((1, features.shape[1]), dtype=np.float32)
        supernode_feat[-1, -1] = 1
        features = sp.vstack([features, supernode_feat])
        features = self.normalize(features)
        features = torch.FloatTensor(np.array(features.todense()))
        return features

    def prepare_data(self, commit):
        # metrics = torch.FloatTensor(self.normalize(self.metrics[self.metrics['commit_id'] == c]
        #                                            .drop(columns=['commit_id']).to_numpy(dtype=np.float32))[0, :])
        metrics = None

        b_node_tokens, b_edges, b_colors = [], [[], []], []
        a_node_tokens, a_edges, a_colors = [], [[], []], []
        b_nodes_so_far, a_nodes_so_far = 0, 0
        for file in commit:
            b_node_tokens += [' '.join(node) for node in file[1][0]]
            b_colors += [c for c in file[1][2]]
            b_edges = [
                b_edges[0] + [s + b_nodes_so_far for s in file[1][1][0]],   # source nodes
                b_edges[1] + [d + b_nodes_so_far for d in file[1][1][1]]    # destination nodes
            ]
            a_node_tokens += [' '.join(node) for node in file[2][0]]
            a_colors += [c for c in file[2][2]]
            a_edges = [
                a_edges[0] + [s + a_nodes_so_far for s in file[2][1][0]],   # source nodes
                a_edges[1] + [d + a_nodes_so_far for d in file[2][1][1]]    # destination nodes
            ]

            b_n_nodes = len(file[1][0])
            a_n_nodes = len(file[2][0])
            b_nodes_so_far += b_n_nodes
            a_nodes_so_far += a_n_nodes

        # if b_nodes_so_far + a_nodes_so_far > 28000 or b_nodes_so_far > 18000 or a_nodes_so_far > 18000:
        #     print('{} is a large commit, skip!'.format(c))
        #     return None

        before_embeddings = self.get_embedding(b_node_tokens, b_colors)
        before_adj = self.get_adjacency_matrix(b_nodes_so_far, b_edges[0], b_edges[1])
        after_embeddings = self.get_embedding(a_node_tokens, a_colors)
        after_adj = self.get_adjacency_matrix(a_nodes_so_far, a_edges[0], a_edges[1])
        training_data = [before_embeddings, before_adj, after_embeddings, after_adj, metrics]

        return training_data


def predict(model, data):
    y_scores = []
    y_true = []
    # features_list = []
    # label_list = []
    model.eval()
    with torch.no_grad():
            if data is None:
                return -1
            model = model.to(device)
            output, features = model(data[0].to(device), data[1].to(device),
                                     data[2].to(device), data[3].to(device), None)
            # data[5].to(device))
            # features_list.append(features)
            # label_list.append(label)
            prob = torch.sigmoid(output).item()
    return prob


def main(commit):
    with open(os.path.join(BASE_PATH, 'vectorizer.pkl'), 'rb') as fp:
        vectorizer = pickle.load(fp)
    dataset = Dataset(vectorizer, special_token=False)
    data = dataset.prepare_data(commit)
    hidden_size = len(dataset.vectorizer_model.vocabulary_) + 2   # plus supernode node feature and node colors
    metric_size = 0
    message_size = 32
    model = JITGNN(hidden_size, message_size, metric_size)
    model = torch.load(os.path.join(BASE_PATH, '34_model_best_auc.pt'), map_location=torch.device('cpu'))
    prob = predict(model, data)
    return prob

# if __name__ == '__main__':
#     with open('../diff/commit.json') as fp:
#         commit = json.load(fp)
    # prepare_data(before, after)
