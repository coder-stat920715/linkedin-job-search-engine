package com.example.jobsearch.l2;

import com.example.jobsearch.domain.Candidate;

import java.util.Map;

public record ScoredCandidate(Candidate candidate, double score, Map<String, Double> breakdown) {
}
