package com.example.jobsearch.query;

import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/** Factory Pattern: single place that builds (and normalises/flattens) AST nodes. */
@Component
public class QueryNodeFactory {

    public QueryNode term(String raw) {
        return new TermNode(TermNormalizer.normalize(raw));
    }

    public QueryNode not(QueryNode inner) {
        return new NotNode(inner);
    }

    public QueryNode and(List<QueryNode> children) {
        if (children.size() == 1) {
            return children.get(0);
        }
        List<QueryNode> flat = new ArrayList<>();
        for (QueryNode c : children) {
            if (c instanceof AndNode and) {
                flat.addAll(and.children());
            } else {
                flat.add(c);
            }
        }
        return new AndNode(List.copyOf(flat));
    }

    public QueryNode or(List<QueryNode> children) {
        if (children.size() == 1) {
            return children.get(0);
        }
        List<QueryNode> flat = new ArrayList<>();
        for (QueryNode c : children) {
            if (c instanceof OrNode or) {
                flat.addAll(or.children());
            } else {
                flat.add(c);
            }
        }
        return new OrNode(List.copyOf(flat));
    }
}
