package com.example.jobsearch.query;

import java.util.HashSet;
import java.util.Set;

public record TermNode(String term) implements QueryNode {

    @Override
    public Set<Long> evaluate(PostingsSource source) {
        return new HashSet<>(source.postings(term));
    }

    @Override
    public void collectPositiveTerms(Set<String> out) {
        out.add(term);
    }
}
