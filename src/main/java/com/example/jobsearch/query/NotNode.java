package com.example.jobsearch.query;

import java.util.HashSet;
import java.util.Set;

public record NotNode(QueryNode inner) implements QueryNode {

    @Override
    public Set<Long> evaluate(PostingsSource source) {
        Set<Long> result = new HashSet<>(source.universe());
        result.removeAll(inner.evaluate(source));
        return result;
    }

    @Override
    public void collectPositiveTerms(Set<String> out) {
        // terms under NOT are exclusions, not preferences
    }
}
