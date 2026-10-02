package com.example.jobsearch.l1;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.query.TermNormalizer;
import org.springframework.stereotype.Component;

import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

/** Turns a candidate profile into index terms: skills, full phrases and 1..3-gram shingles of text fields. */
@Component
public class CandidateTermExtractor {

    private static final int MAX_NGRAM = 3;

    public Set<String> extract(Candidate c) {
        Set<String> terms = new HashSet<>();
        if (c.getSkills() != null) {
            for (String skill : c.getSkills()) {
                String n = TermNormalizer.normalize(skill);
                if (!n.isEmpty()) {
                    terms.add(n);
                }
            }
        }
        addPhrase(terms, c.getCurrentCompany());
        addPhrase(terms, c.getCurrentTitle());
        addPhrase(terms, c.getHeadline());
        addPhrase(terms, c.getLocation());
        if (c.isImmediateJoiner()) {
            terms.add("immediate joiner");
        }
        if (c.isOpenToWork()) {
            terms.add("open to work");
        }
        return terms;
    }

    private void addPhrase(Set<String> terms, String raw) {
        String normalized = TermNormalizer.normalize(raw);
        if (normalized.isEmpty()) {
            return;
        }
        terms.add(normalized);
        List<String> tokens = Arrays.stream(normalized.split("[^a-z0-9+#.]+"))
                .map(t -> t.replaceAll("\\.+$", ""))
                .filter(t -> !t.isEmpty())
                .toList();
        for (int i = 0; i < tokens.size(); i++) {
            for (int len = 1; len <= MAX_NGRAM && i + len <= tokens.size(); len++) {
                terms.add(String.join(" ", tokens.subList(i, i + len)));
            }
        }
    }
}
