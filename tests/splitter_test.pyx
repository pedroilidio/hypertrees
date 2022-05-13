from sklearn.tree._criterion cimport Criterion
from sklearn.tree._splitter cimport Splitter, SplitRecord
from sklearn.tree._tree cimport SIZE_t

from hypertree.tree._nd_splitter cimport SplitRecord as SplitRecordND, Splitter2D

import numpy as np
cimport numpy as np

cdef double INFINITY = np.inf

cdef inline void _init_split(SplitRecord* self, SIZE_t start_pos) nogil:
    self.impurity_left = INFINITY
    self.impurity_right = INFINITY
    self.pos = start_pos
    self.feature = 0
    self.threshold = 0.
    self.improvement = -INFINITY


cpdef test_splitter(
        Splitter splitter,
        object X, np.ndarray y,
        tuple shape,
        verbose=False,
):
    cdef SplitRecord split
    _init_split(&split, 0)

    cdef SIZE_t end = shape[0]
    cdef SIZE_t ncf = 0  # n_constant_features
    cdef double wnns  # weighted_n_node_samples

    if verbose:
        print('[SPLITTER_TEST] calling splitter.init(X, y, NULL)')
    splitter.init(X, y, NULL)
    if verbose:
        print('[SPLITTER_TEST] calling splitter.node_reset(0, end, &wnns)')
    splitter.node_reset(0, end, &wnns)

    impurity = splitter.node_impurity()
    # impurity = splitter.criterion.node_impurity()  # Same. Above wraps this.

    if verbose:
        print('[SPLITTER_TEST] splitter.node_impurity():', impurity)
        print('[SPLITTER_TEST] y.var():', y.var())
        print('[SPLITTER_TEST] splitter.criterion.pos:', splitter.criterion.pos)
        print('[SPLITTER_TEST] calling splitter.node_split(impurity, &split, &ncf)')

    splitter.node_split(impurity, &split, &ncf)

    if verbose:
        print('[SPLITTER_TEST] splitter.criterion.pos:', splitter.criterion.pos)
        print('[SPLITTER_TEST] split', split)

    return split


def test_splitter2d(Splitter2D splitter,
                    object X, np.ndarray y):
    cdef SplitRecord split
    _init_split(&split, 0)

    cdef SIZE_t[2] ncf = [0, 0]  # n_constant_features
    cdef double wnns  # weighted_n_node_samples

    cdef SIZE_t[2] start = [0, 0]
    cdef SIZE_t[2] end = [X[0].shape[0], X[1].shape[0]]

    print("Initiating splitter")
    splitter.init(X, y, NULL)
    print("Calling splitter.node_reset")
    splitter.node_reset(start, end, &wnns)
    print("Calling splitter.node_impurity")
    impurity = splitter.node_impurity()
    print("Impurity:", impurity)
    print("wnns:", wnns)
    print("Calling splitter.node_split")
    splitter.node_split(impurity, &split, ncf)
    return split
