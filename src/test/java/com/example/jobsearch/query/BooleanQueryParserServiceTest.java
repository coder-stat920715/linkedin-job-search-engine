package com.example.jobsearch.query;

import com.example.jobsearch.exception.QueryParseException;
import com.example.jobsearch.l1.InvertedIndex;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

class BooleanQueryParserServiceTest {

    private final BooleanQueryParserService parser = new BooleanQueryParserService(new QueryNodeFactory());
    private InvertedIndex index;

    @BeforeEach
    void setUp() {
        index = new InvertedIndex();
        index.upsert(1L, Set.of("jpmorgan", "talent acquisition", "java", "immediate joiner"));
        index.upsert(2L, Set.of("jpmorgan", "recruiter", "java"));
        index.upsert(3L, Set.of("jpmorgan", "recruiter", "java", "immediate joiner"));
        index.upsert(4L, Set.of("google", "recruiter", "java", "immediate joiner"));
    }

    @Test
    void recruiterBooleanQueryMatchesExpectedCandidates() {
        QueryNode ast = parser.parse(
                "\"JPMorgan\" AND (\"Talent Acquisition\" OR \"Recruiter\") AND \"Java\" AND \"Immediate Joiner\"");
        assertEquals(Set.of(1L, 3L), index.search(ast));
    }

    @Test
    void andBindsTighterThanOr() {
        assertEquals(Set.of(1L, 4L), index.search(parser.parse("\"google\" OR \"jpmorgan\" AND \"talent acquisition\"")));
    }

    @Test
    void notExcludesMatches() {
        assertEquals(Set.of(2L), index.search(parser.parse("\"jpmorgan\" AND NOT \"immediate joiner\" AND java")));
    }

    @Test
    void adjacentOperandsAreImplicitlyAnded() {
        assertEquals(Set.of(2L, 3L, 4L), index.search(parser.parse("java recruiter")));
    }

    @Test
    void collectsOnlyPositiveTerms() {
        Set<String> terms = new java.util.HashSet<>();
        parser.parse("java AND NOT google").collectPositiveTerms(terms);
        assertEquals(Set.of("java"), terms);
    }

    @Test
    void malformedQueriesAreRejected() {
        assertThrows(QueryParseException.class, () -> parser.parse(""));
        assertThrows(QueryParseException.class, () -> parser.parse("(\"java\""));
        assertThrows(QueryParseException.class, () -> parser.parse("\"java"));
        assertThrows(QueryParseException.class, () -> parser.parse("AND java"));
        assertThrows(QueryParseException.class, () -> parser.parse("java )"));
        assertThrows(QueryParseException.class, () -> parser.parse("java OR"));
    }
}
