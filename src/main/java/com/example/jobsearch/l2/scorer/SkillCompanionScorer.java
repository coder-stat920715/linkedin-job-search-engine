package com.example.jobsearch.l2.scorer;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.l2.CandidateScorer;
import com.example.jobsearch.l2.ScoringContext;
import com.example.jobsearch.l2.SkillCompanionMatrix;
import com.example.jobsearch.query.TermNormalizer;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.Set;
import java.util.stream.Collectors;

/**
 * SkillMatch = (1/|Q|) * sum over queried skills q of:
 *   1                         if the candidate holds q
 *   discount * max_h A[q][h]  otherwise (best companion skill h the candidate holds)
 */
@Component
@RequiredArgsConstructor
public class SkillCompanionScorer implements CandidateScorer {

    private final SkillCompanionMatrix matrix;
    private final SearchProperties properties;

    @Override
    public String name() {
        return "skillMatch";
    }

    @Override
    public double weight() {
        return properties.getWeights().getSkillMatch();
    }

    @Override
    public double score(Candidate candidate, CandidateFeatureSet features, ScoringContext context) {
        Set<String> queried = context.queriedSkills();
        if (queried.isEmpty()) {
            return 0.5;
        }
        Set<String> held = candidate.getSkills().stream().map(TermNormalizer::normalize).collect(Collectors.toSet());
        double sum = 0.0;
        for (String q : queried) {
            if (held.contains(q)) {
                sum += 1.0;
            } else {
                double best = held.stream().mapToDouble(h -> matrix.affinity(q, h)).max().orElse(0.0);
                sum += best * properties.getCompanionDiscount();
            }
        }
        return sum / queried.size();
    }
}
