package com.example.jobsearch.query;

import java.util.Locale;

public final class TermNormalizer {

    private TermNormalizer() {
    }

    public static String normalize(String raw) {
        return raw == null ? "" : raw.toLowerCase(Locale.ROOT).trim().replaceAll("\\s+", " ");
    }
}
