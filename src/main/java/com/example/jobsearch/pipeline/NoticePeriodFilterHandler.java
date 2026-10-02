package com.example.jobsearch.pipeline;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
@Order(30)
public class NoticePeriodFilterHandler implements CandidateFilterHandler {

    @Override
    public List<Candidate> handle(List<Candidate> candidates, RecruiterSearchRequest request, CandidateFilterChain chain) {
        Integer max = request.maxNoticePeriodDays();
        if (max == null) {
            return chain.proceed(candidates, request);
        }
        List<Candidate> filtered = candidates.stream()
                .filter(c -> c.isImmediateJoiner() || (c.getNoticePeriodDays() != null && c.getNoticePeriodDays() <= max))
                .toList();
        return chain.proceed(filtered, request);
    }
}
