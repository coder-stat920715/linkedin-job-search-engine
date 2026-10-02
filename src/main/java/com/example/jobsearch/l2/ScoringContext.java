package com.example.jobsearch.l2;

import java.time.Instant;
import java.util.Set;

public record ScoringContext(Set<String> queriedSkills, Instant now) {
}
