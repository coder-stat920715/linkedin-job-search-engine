package com.example.jobsearch.l1;

import com.example.jobsearch.query.PostingsSource;
import com.example.jobsearch.query.QueryNode;
import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.locks.ReadWriteLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;

/** In-memory inverted index: term -> candidate ids. Many concurrent readers, exclusive writers. */
@Component
public class InvertedIndex {

    private final Map<String, Set<Long>> postings = new HashMap<>();
    private final Map<Long, Set<String>> forward = new HashMap<>();
    private final Set<Long> all = new HashSet<>();
    private final ReadWriteLock lock = new ReentrantReadWriteLock();

    public void upsert(long id, Set<String> terms) {
        lock.writeLock().lock();
        try {
            removeUnlocked(id);
            Set<String> copy = new HashSet<>(terms);
            forward.put(id, copy);
            all.add(id);
            for (String term : copy) {
                postings.computeIfAbsent(term, k -> new HashSet<>()).add(id);
            }
        } finally {
            lock.writeLock().unlock();
        }
    }

    public void remove(long id) {
        lock.writeLock().lock();
        try {
            removeUnlocked(id);
        } finally {
            lock.writeLock().unlock();
        }
    }

    public void clear() {
        lock.writeLock().lock();
        try {
            postings.clear();
            forward.clear();
            all.clear();
        } finally {
            lock.writeLock().unlock();
        }
    }

    public int size() {
        lock.readLock().lock();
        try {
            return all.size();
        } finally {
            lock.readLock().unlock();
        }
    }

    /** Evaluates the whole AST under one read lock so the result is a consistent snapshot. */
    public Set<Long> search(QueryNode node) {
        lock.readLock().lock();
        try {
            return node.evaluate(new PostingsSource() {
                @Override
                public Set<Long> postings(String term) {
                    return InvertedIndex.this.postings.getOrDefault(term, Set.of());
                }

                @Override
                public Set<Long> universe() {
                    return all;
                }
            });
        } finally {
            lock.readLock().unlock();
        }
    }

    private void removeUnlocked(long id) {
        Set<String> old = forward.remove(id);
        all.remove(id);
        if (old == null) {
            return;
        }
        for (String term : old) {
            Set<Long> ids = postings.get(term);
            if (ids != null) {
                ids.remove(id);
                if (ids.isEmpty()) {
                    postings.remove(term);
                }
            }
        }
    }
}
