package com.example.jobsearch.pipeline;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
@Order(20)
public class OpenToWorkFilterHandler implements CandidateFilterHandler {

    @Override
    public List<Candidate> handle(List<Candidate> candidates, RecruiterSearchRequest request, CandidateFilterChain chain) {
        if (!Boolean.TRUE.equals(request.openToWorkOnly())) {
            return chain.proceed(candidates, request);
        }
        return chain.proceed(candidates.stream().filter(Candidate::isOpenToWork).toList(), request);
    }
}
