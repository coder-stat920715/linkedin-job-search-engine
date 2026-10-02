package com.example.jobsearch.pipeline;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.RecruiterSearchRequest;

import java.util.List;

public interface CandidateFilterHandler {
    List<Candidate> handle(List<Candidate> candidates, RecruiterSearchRequest request, CandidateFilterChain chain);
}
