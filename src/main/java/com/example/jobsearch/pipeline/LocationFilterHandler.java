package com.example.jobsearch.pipeline;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import com.example.jobsearch.query.TermNormalizer;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
@Order(10)
public class LocationFilterHandler implements CandidateFilterHandler {

    @Override
    public List<Candidate> handle(List<Candidate> candidates, RecruiterSearchRequest request, CandidateFilterChain chain) {
        String wanted = TermNormalizer.normalize(request.location());
        if (wanted.isEmpty()) {
            return chain.proceed(candidates, request);
        }
        List<Candidate> filtered = candidates.stream()
                .filter(c -> TermNormalizer.normalize(c.getLocation()).contains(wanted))
                .toList();
        return chain.proceed(filtered, request);
    }
}
