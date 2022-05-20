from sklearn.tree._criterion cimport Criterion, RegressionCriterion
from sklearn.tree._criterion import MSE
from sklearn.tree._tree cimport SIZE_t
from libc.stdlib cimport malloc, free, sizeof


# cdef class WeightedMSE(RegressionCriterion, MSE):
#     cdef void set_output_weights(self, DOUBLE_t* output_weigths) nogil:
#         self.output_weights = output_weights
#         # TODO:Implement output weights for multi-output criteria.
          # Remember sq_sums must be calculated accordingly (w * y**2).


cdef class SemisupervisedCriterion(Criterion):
    """Base class for semantic purposes and future maintenance.

    When training with an unsupervised criterion, one must provide X and y
    stacked (joined cols) as the y parameter of the estimator's fit(). E.g.:

    >>> clf = DecisionTreeRregressor()
    >>> clf.fit(X=X, y=np.hstack([X, y]))
    """


# Maybe "SSEnsembleCriterion"
cdef class SSCompositeCriterion(SemisupervisedCriterion):
    """Combines results from two criteria to yield its own.
    
    One criteria will receive y in its init() and the other will receive X.
    Their calculated impurities will then be combined as the final impurity:

        sup*supervised_impurity + (1-sup)*unsupervised_impurity

    where sup is self.supervision.

    When training with an unsupervised criterion, one must provide X and y
    stacked (joined cols) as the y parameter of the estimator's fit(). E.g.:

    >>> clf = DecisionTreeRregressor(criterion=ss_criterion)
    >>> clf.fit(X=X, y=np.hstack([X, y]))
    """
    def __init__(
        self,
        Criterion supervised_criterion,
        Criterion unsupervised_criterion,
        double supervision,
        *args, **kwargs,
    ):
        if not (0 <= supervision <= 1):
            # TODO: == 0 only for tests.
            raise ValueError("supervision must be in [0, 1] interval.")
        self.supervision = supervision
        self.supervised_criterion = supervised_criterion
        self.unsupervised_criterion = unsupervised_criterion
        self.n_outputs = supervised_criterion.n_outputs
        self.n_samples = supervised_criterion.n_samples
        self.n_features = unsupervised_criterion.n_outputs

    def __dealloc__(self):
        """Overwrite Criterion.__dealloc__

        Parent class would free sum_total, sum_left and sum_right, but since we
        get these pointers from children criteria, we must delegate this job to
        them.
        """
        # FIXME: allocating just to be deallocated by the parent class with no
        # complainints.
        self.sum_total = <double*> malloc(sizeof(double*))
        self.sum_left = <double*> malloc(sizeof(double*))
        self.sum_right = <double*> malloc(sizeof(double*))

    cdef int init(
            self, const DOUBLE_t[:, ::1] y,
            DOUBLE_t* sample_weight,
            double weighted_n_samples, SIZE_t* samples, SIZE_t start,
            SIZE_t end) nogil except -1:

        # y will actually be X and y concatenated.
        self.X = y[:, :self.n_features]
        self.y = y[:, self.n_features:]
        self.sample_weight = sample_weight
        self.samples = samples
        self.start = start
        self.end = end
        self.n_node_samples = end-start
        self.weighted_n_samples = weighted_n_samples

        self.supervised_criterion.init(
            self.y, sample_weight, weighted_n_samples, samples, start, end,
        )
        self.unsupervised_criterion.init(
            self.X, sample_weight, weighted_n_samples, samples, start, end,
        )

        # TODO: the stuff bellow is also calculated by the second splitter,
        # we should find a good way of calculating it only once.
        self.weighted_n_node_samples = \
            self.supervised_criterion.weighted_n_node_samples
        self.weighted_n_left = \
            self.supervised_criterion.weighted_n_left
        self.weighted_n_right = \
            self.supervised_criterion.weighted_n_right

        self.sum_total = self.supervised_criterion.sum_total
        self.sum_left = self.supervised_criterion.sum_left
        self.sum_right = self.supervised_criterion.sum_right
        ### Only RegressionCriteria have sq_sum_total. TODO: will we need it?
        # self.sq_sum_total = self.supervised_criterion.sq_sum_total

        return 0

    cdef int reset(self) nogil except -1:
        """Reset the criteria at pos=start."""
        if self.supervised_criterion.reset() == -1:
            return -1
        if self.unsupervised_criterion.reset() == -1:
            return -1
        return 0

    cdef int reverse_reset(self) nogil except -1:
        """Reset the criteria at pos=end."""
        if self.supervised_criterion.reverse_reset() == -1:
            return -1
        if self.unsupervised_criterion.reverse_reset() == -1:
            return -1
        return 0

    cdef int update(self, SIZE_t new_pos) nogil except -1:
        """Updated statistics by moving samples[pos:new_pos] to the left child.
        This updates the collected statistics by moving samples[pos:new_pos]
        from the right child to the left child.
        Parameters
        ----------
        new_pos : SIZE_t
            New starting index position of the samples in the right child
        """
        cdef int rc
        if self.supervised_criterion.update(new_pos) == -1:
            return -1
        if self.unsupervised_criterion.update(new_pos) == -1:
            return -1
        self.pos = new_pos
        return 0

    cdef double node_impurity(self) nogil:
        """Calculate the impurity of the node.
        Impurity of the current node, i.e. the impurity of samples[start:end].
        This is the primary function of the criterion class. The smaller the
        impurity the better.
        """
        cdef double sup = self.supervision

        return (
            sup * self.supervised_criterion.node_impurity() + \
            (1-sup) * self.unsupervised_criterion.node_impurity()
        )

    cdef void children_impurity(self, double* impurity_left,
                                double* impurity_right) nogil:
        """Calculate the impurity of children.
        Evaluate the impurity in children nodes, i.e. the impurity of
        samples[start:pos] + the impurity of samples[pos:end].

        Parameters
        ----------
        impurity_left : double pointer
            The memory address where the impurity of the left child should be
            stored.
        impurity_right : double pointer
            The memory address where the impurity of the right child should be
            stored
        """
        cdef double s_impurity_left, s_impurity_right
        cdef double u_impurity_left, u_impurity_right
        cdef double sup = self.supervision

        self.supervised_criterion.children_impurity(
            &s_impurity_left, &s_impurity_right,
        )
        self.unsupervised_criterion.children_impurity(
            &u_impurity_left, &u_impurity_right,
        )

        impurity_left[0] = sup*s_impurity_left + (1-sup)*u_impurity_left
        impurity_right[0] = sup*s_impurity_right + (1-sup)*u_impurity_right

    cdef void node_value(self, double* dest) nogil:
        """Store the node value.
        Compute the node value of samples[start:end] and save the value into
        dest.

        Parameters
        ----------
        dest : double pointer
            The memory address where the node value should be stored.
        """
        self.supervised_criterion.node_value(dest)

    cdef double proxy_impurity_improvement(self) nogil:
        """Compute a proxy of the impurity reduction.
        This method is used to speed up the search for the best split.
        It is a proxy quantity such that the split that maximizes this value
        also maximizes the impurity improvement. It neglects all constant terms
        of the impurity decrease for a given split.
        The absolute impurity improvement is only computed by the
        impurity_improvement method once the best split has been found.
        """
        cdef double sup = self.supervision
        return \
            sup * self.supervised_criterion.proxy_impurity_improvement() + \
            (1-sup) * self.unsupervised_criterion.proxy_impurity_improvement()


cdef class SSMSE(SSCompositeCriterion):
    """Applies MSE both on supervised (X) and unsupervised (y) data.
    
    One criteria will receive y in its init() and the other will receive X.
    Their calculated impurities will then be combined as the final impurity:

        sup*supervised_impurity + (1-sup)*unsupervised_impurity

    where sup is self.supervision.

    When training with an unsupervised criterion, one must provide X and y
    stacked (joined cols) as the y parameter of the estimator's fit(). E.g.:

    >>> clf = DecisionTreeRregressor()
    >>> clf.fit(X=X, y=np.hstack([X, y]))
    """
    def __init__(
        self,
        double supervision,
        SIZE_t n_features,
        SIZE_t n_samples,
        SIZE_t n_outputs,  # of y's columns.
        *args, **kwargs,
    ):
        self.supervision = supervision
        self.supervised_criterion = MSE(
            n_outputs=n_outputs, n_samples=n_samples)
        self.unsupervised_criterion = MSE(
            n_outputs=n_features, n_samples=n_samples)

        self.n_features = n_features
        self.n_samples = n_samples
        self.n_outputs = n_outputs


# cdef class SSCriterionWrapper(RegressionCriterionWrapper2D):
#     pass

cdef class WeightedOutputsRegressionCriterion(RegressionCriterion):
    r"""Abstract regression criterion with output weights.

    This handles cases where the target is a continuous value, and is
    evaluated by computing the variance of the target values left and right
    of the split point. The computation takes linear time with `n_samples`
    by using ::

        var = \sum_i^n (y_i - y_bar) ** 2
            = (\sum_i^n y_i ** 2) - n_samples * y_bar ** 2
    """
    def __cinit__(self, SIZE_t n_outputs, SIZE_t n_samples):
        self.output_weights = <DOUBLE_t*> malloc(sizeof(DOUBLE_t)*n_outputs)

    def __dealloc__(self):
        free(self.output_weights)

    cdef void set_output_weights(self, DOUBLE_t* output_weights) nogil:
        for k in range(self.n_outputs):
            self.output_weights[k] = output_weights[k]

    cdef int init(self, const DOUBLE_t[:, ::1] y, DOUBLE_t* sample_weight,
                  double weighted_n_samples, SIZE_t* samples, SIZE_t start,
                  SIZE_t end) nogil except -1:
        """Initialize the criterion.

        This initializes the criterion at node samples[start:end] and children
        samples[start:start] and samples[start:end].
        """
        cdef SIZE_t i
        cdef SIZE_t p
        cdef SIZE_t k
        cdef DOUBLE_t y_ik
        cdef DOUBLE_t w_y_ik
        cdef DOUBLE_t w = 1.0

        cdef DOUBLE_t[:, ::1] wy = y

        for p in range(start, end):
            i = samples[p]
            for k in range(self.n_outputs):
                wy[i, k] *= self.output_weights[k]

        if RegressionCriterion.init(
            self, wy, sample_weight, weighted_n_samples, samples, start, end,
        ) == -1:
            return -1

        self.sq_sum_total = 0.0

        for p in range(start, end):
            i = samples[p]

            if sample_weight != NULL:
                w = sample_weight[i]

            for k in range(self.n_outputs):
                y_ik = self.y[i, k]
                w_y_ik = w * y_ik
                self.sq_sum_total += w_y_ik * y_ik / self.output_weights[k]

        return 0


cdef class WOMSE(WeightedOutputsRegressionCriterion):
    """Weighted outputs mean squared error impurity criterion.

        MSE = var_left + var_right
    """

    cdef void children_impurity(self, double* impurity_left,
                                double* impurity_right) nogil:
        """Evaluate the impurity in children nodes.

        i.e. the impurity of the left child (samples[start:pos]) and the
        impurity the right child (samples[pos:end]).
        """
        cdef DOUBLE_t* sample_weight = self.sample_weight
        cdef SIZE_t* samples = self.samples
        cdef SIZE_t pos = self.pos
        cdef SIZE_t start = self.start

        cdef double* sum_left = self.sum_left
        cdef double* sum_right = self.sum_right
        cdef DOUBLE_t y_ik

        cdef double sq_sum_left = 0.0
        cdef double sq_sum_right

        cdef SIZE_t i
        cdef SIZE_t p
        cdef SIZE_t k
        cdef DOUBLE_t w = 1.0

        for p in range(start, pos):
            i = samples[p]

            if sample_weight != NULL:
                w = sample_weight[i]

            for k in range(self.n_outputs):
                y_ik = self.y[i, k]
                # Only change:
                sq_sum_left += w * y_ik * y_ik / self.output_weights[k]

        sq_sum_right = self.sq_sum_total - sq_sum_left

        impurity_left[0] = sq_sum_left / self.weighted_n_left
        impurity_right[0] = sq_sum_right / self.weighted_n_right

        for k in range(self.n_outputs):
            impurity_left[0] -= (sum_left[k] / self.weighted_n_left) ** 2.0
            impurity_right[0] -= (sum_right[k] / self.weighted_n_right) ** 2.0

        impurity_left[0] /= self.n_outputs
        impurity_right[0] /= self.n_outputs

cdef class SSMSE2(WOMSE):
    cdef void set_supervision(self, supervision) nogil:
        self.supervision = supervision