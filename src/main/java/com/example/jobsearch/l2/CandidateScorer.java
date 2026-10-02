package com.example.jobsearch.l2;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;

/** Strategy Pattern: each scorer returns a normalised value in [0, 1]. */
public interface CandidateScorer {

    String name();

    double weight();

    double score(Candidate candidate, CandidateFeatureSet features, ScoringContext context);
}
