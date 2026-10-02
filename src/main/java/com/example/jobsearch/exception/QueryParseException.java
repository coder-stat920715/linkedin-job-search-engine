package com.example.jobsearch.exception;

public class QueryParseException extends RuntimeException {
    private final int position;

    public QueryParseException(String message, int position) {
        super(message + " (at position " + position + ")");
        this.position = position;
    }

    public int getPosition() {
        return position;
    }
}
