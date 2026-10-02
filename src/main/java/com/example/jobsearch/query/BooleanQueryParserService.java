package com.example.jobsearch.query;

import com.example.jobsearch.exception.QueryParseException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;

/**
 * Recursive-descent parser. Grammar (NOT > AND > OR, adjacent operands are implicitly ANDed):
 * <pre>
 *   or      := and ( "OR" and )*
 *   and     := unary ( ["AND"] unary )*
 *   unary   := "NOT" unary | primary
 *   primary := TERM | "(" or ")"
 * </pre>
 * Operators must be upper-case; quoted strings are phrases.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class BooleanQueryParserService {

    private static final int MAX_DEPTH = 64;

    private final QueryNodeFactory factory;

    public QueryNode parse(String query) {
        if (query == null || query.isBlank()) {
            throw new QueryParseException("Query must not be empty", 0);
        }
        Parser parser = new Parser(tokenize(query));
        QueryNode root = parser.parseOr(0);
        if (!parser.atEnd()) {
            Token t = parser.peek();
            throw new QueryParseException("Unexpected token '" + t.text() + "'", t.pos());
        }
        log.debug("Parsed query '{}' into {}", query, root);
        return root;
    }

    enum Type { LPAREN, RPAREN, AND, OR, NOT, TERM }

    record Token(Type type, String text, int pos) {
    }

    private List<Token> tokenize(String q) {
        List<Token> tokens = new ArrayList<>();
        int i = 0;
        while (i < q.length()) {
            char ch = q.charAt(i);
            if (Character.isWhitespace(ch)) {
                i++;
            } else if (ch == '(') {
                tokens.add(new Token(Type.LPAREN, "(", i++));
            } else if (ch == ')') {
                tokens.add(new Token(Type.RPAREN, ")", i++));
            } else if (ch == '"') {
                int end = q.indexOf('"', i + 1);
                if (end < 0) {
                    throw new QueryParseException("Unterminated quoted phrase", i);
                }
                String phrase = q.substring(i + 1, end);
                if (phrase.isBlank()) {
                    throw new QueryParseException("Empty quoted phrase", i);
                }
                tokens.add(new Token(Type.TERM, phrase, i));
                i = end + 1;
            } else {
                int start = i;
                while (i < q.length() && !Character.isWhitespace(q.charAt(i))
                        && q.charAt(i) != '(' && q.charAt(i) != ')' && q.charAt(i) != '"') {
                    i++;
                }
                String word = q.substring(start, i);
                Type type = switch (word) {
                    case "AND" -> Type.AND;
                    case "OR" -> Type.OR;
                    case "NOT" -> Type.NOT;
                    default -> Type.TERM;
                };
                tokens.add(new Token(type, word, start));
            }
        }
        return tokens;
    }

    private final class Parser {
        private final List<Token> tokens;
        private int index = 0;

        Parser(List<Token> tokens) {
            this.tokens = tokens;
        }

        boolean atEnd() {
            return index >= tokens.size();
        }

        Token peek() {
            return tokens.get(index);
        }

        private boolean match(Type type) {
            if (!atEnd() && peek().type() == type) {
                index++;
                return true;
            }
            return false;
        }

        QueryNode parseOr(int depth) {
            List<QueryNode> parts = new ArrayList<>();
            parts.add(parseAnd(depth));
            while (match(Type.OR)) {
                parts.add(parseAnd(depth));
            }
            return factory.or(parts);
        }

        private QueryNode parseAnd(int depth) {
            List<QueryNode> parts = new ArrayList<>();
            parts.add(parseUnary(depth));
            while (true) {
                if (match(Type.AND)) {
                    parts.add(parseUnary(depth));
                } else if (!atEnd() && startsOperand(peek().type())) {
                    parts.add(parseUnary(depth));
                } else {
                    break;
                }
            }
            return factory.and(parts);
        }

        private boolean startsOperand(Type type) {
            return type == Type.TERM || type == Type.NOT || type == Type.LPAREN;
        }

        private QueryNode parseUnary(int depth) {
            if (depth > MAX_DEPTH) {
                throw new QueryParseException("Query nesting too deep", atEnd() ? 0 : peek().pos());
            }
            if (match(Type.NOT)) {
                return factory.not(parseUnary(depth + 1));
            }
            return parsePrimary(depth);
        }

        private QueryNode parsePrimary(int depth) {
            if (atEnd()) {
                int pos = tokens.isEmpty() ? 0 : tokens.get(tokens.size() - 1).pos();
                throw new QueryParseException("Unexpected end of query", pos);
            }
            Token t = tokens.get(index++);
            switch (t.type()) {
                case TERM:
                    return factory.term(t.text());
                case LPAREN:
                    QueryNode inner = parseOr(depth + 1);
                    if (!match(Type.RPAREN)) {
                        throw new QueryParseException("Missing closing parenthesis", t.pos());
                    }
                    return inner;
                default:
                    throw new QueryParseException("Unexpected token '" + t.text() + "'", t.pos());
            }
        }
    }
}
