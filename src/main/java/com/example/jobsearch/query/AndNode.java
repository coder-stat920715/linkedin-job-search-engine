package com.example.jobsearch.query;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public record AndNode(List<QueryNode> children) implements QueryNode {

    /** Intersects positive children smallest-first, then subtracts NOT children (avoids materialising the universe). */
    @Override
    public Set<Long> evaluate(PostingsSource source) {
        List<Set<Long>> positives = new ArrayList<>();
        List<Set<Long>> negatives = new ArrayList<>();
        for (QueryNode child : children) {
            if (child instanceof NotNode not) {
                negatives.add(not.inner().evaluate(source));
            } else {
                positives.add(child.evaluate(source));
            }
        }
        Set<Long> result;
        if (positives.isEmpty()) {
            result = new HashSet<>(source.universe());
        } else {
            positives.sort(Comparator.comparingInt(Set::size));
            result = new HashSet<>(positives.get(0));
            for (int i = 1; i < positives.size() && !result.isEmpty(); i++) {
                result.retainAll(positives.get(i));
            }
        }
        for (Set<Long> negative : negatives) {
            result.removeAll(negative);
        }
        return result;
    }

    @Override
    public void collectPositiveTerms(Set<String> out) {
        children.forEach(c -> c.collectPositiveTerms(out));
    }
}
