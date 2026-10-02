package com.example.jobsearch.l2.scorer;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.l2.CandidateScorer;
import com.example.jobsearch.l2.ScoringContext;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
public class OpenToWorkScorer implements CandidateScorer {

    private final SearchProperties properties;

    @Override
    public String name() {
        return "openToWork";
    }

    @Override
    public double weight() {
        return properties.getWeights().getOpenToWork();
    }

    @Override
    public double score(Candidate candidate, CandidateFeatureSet features, ScoringContext context) {
        if (!candidate.isOpenToWork()) {
            return 0.1;
        }
        return candidate.isImmediateJoiner() ? 1.0 : 0.8;
    }
}
