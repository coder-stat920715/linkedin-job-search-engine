package com.example.jobsearch.query;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

public record OrNode(List<QueryNode> children) implements QueryNode {

    @Override
    public Set<Long> evaluate(PostingsSource source) {
        Set<Long> result = new HashSet<>();
        for (QueryNode child : children) {
            result.addAll(child.evaluate(source));
        }
        return result;
    }

    @Override
    public void collectPositiveTerms(Set<String> out) {
        children.forEach(c -> c.collectPositiveTerms(out));
    }
}
