package com.example.jobsearch.pipeline;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.RecruiterSearchRequest;

import java.util.List;

/** Stateful, per-request chain: each handler filters and delegates to the next. */
public class CandidateFilterChain {

    private final List<CandidateFilterHandler> handlers;
    private int position = 0;

    public CandidateFilterChain(List<CandidateFilterHandler> handlers) {
        this.handlers = handlers;
    }

    public List<Candidate> proceed(List<Candidate> candidates, RecruiterSearchRequest request) {
        if (position >= handlers.size()) {
            return candidates;
        }
        return handlers.get(position++).handle(candidates, request, this);
    }
}
