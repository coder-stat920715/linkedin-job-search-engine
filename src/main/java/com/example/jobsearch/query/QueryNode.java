package com.example.jobsearch.query;

import java.util.Set;

public interface QueryNode {

    /** Evaluates this node against the index, always returning a fresh mutable set. */
    Set<Long> evaluate(PostingsSource source);

    /** Collects terms that appear outside any NOT; used by L2 to derive the queried skills. */
    void collectPositiveTerms(Set<String> out);
}
