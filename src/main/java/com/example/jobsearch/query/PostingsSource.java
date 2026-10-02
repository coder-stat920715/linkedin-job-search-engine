package com.example.jobsearch.query;

import java.util.Set;

/** Read-only view of an inverted index. Returned sets must never be mutated by callers. */
public interface PostingsSource {
    Set<Long> postings(String term);

    Set<Long> universe();
}
