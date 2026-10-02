package com.example.jobsearch.service;

import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.repository.CandidateFeatureSetRepository;
import com.example.jobsearch.util.TxUtils;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;
import java.util.stream.Collectors;

/** Feature store: Redis is the hot read path, SQL is the durable store. Redis failures degrade to SQL. */
@Slf4j
@Service
public class FeatureStoreService {

    private static final String KEY_PREFIX = "cfs:";
    private static final long BREAKER_MILLIS = 30_000L;

    private final CandidateFeatureSetRepository repository;
    private final RedisTemplate<String, CandidateFeatureSet> redis;
    private final Duration ttl;
    private volatile long redisDisabledUntil = 0L;

    public FeatureStoreService(CandidateFeatureSetRepository repository,
                               RedisTemplate<String, CandidateFeatureSet> redis,
                               @Value("${app.feature-store.ttl-minutes:10}") long ttlMinutes) {
        this.repository = repository;
        this.redis = redis;
        this.ttl = Duration.ofMinutes(ttlMinutes);
    }

    public Map<Long, CandidateFeatureSet> getBatch(Collection<Long> ids) {
        Map<Long, CandidateFeatureSet> result = new HashMap<>();
        if (ids.isEmpty()) {
            return result;
        }
        List<Long> idList = new ArrayList<>(ids);
        List<Long> misses = new ArrayList<>(idList);
        if (redisAvailable()) {
            try {
                List<CandidateFeatureSet> cached =
                        redis.opsForValue().multiGet(idList.stream().map(FeatureStoreService::key).toList());
                misses = new ArrayList<>();
                for (int i = 0; i < idList.size(); i++) {
                    CandidateFeatureSet f = cached == null ? null : cached.get(i);
                    if (f != null) {
                        result.put(idList.get(i), f);
                    } else {
                        misses.add(idList.get(i));
                    }
                }
            } catch (RuntimeException e) {
                tripBreaker(e);
                result.clear();
                misses = new ArrayList<>(idList);
            }
        }
        if (!misses.isEmpty()) {
            Map<Long, CandidateFeatureSet> fromDb = repository.findAllById(misses).stream()
                    .collect(Collectors.toMap(CandidateFeatureSet::getCandidateId, f -> f));
            fromDb.values().forEach(this::cachePut);
            result.putAll(fromDb);
        }
        return result;
    }

    public CandidateFeatureSet get(Long candidateId) {
        return getBatch(List.of(candidateId)).getOrDefault(candidateId, CandidateFeatureSet.empty(candidateId));
    }

    /** Atomic read-modify-write guarded by a row lock; the cache is refreshed only after commit. */
    @Transactional
    public CandidateFeatureSet update(Long candidateId, Consumer<CandidateFeatureSet> mutator) {
        CandidateFeatureSet features = repository.findForUpdate(candidateId)
                .orElseGet(() -> CandidateFeatureSet.empty(candidateId));
        mutator.accept(features);
        features.setUpdatedAt(Instant.now());
        CandidateFeatureSet saved = repository.save(features);
        TxUtils.afterCommit(() -> cachePut(saved));
        return saved;
    }

    @Transactional
    public int decaySessions(double factor) {
        return repository.decaySessionActivity(factor);
    }

    private void cachePut(CandidateFeatureSet f) {
        if (!redisAvailable()) {
            return;
        }
        try {
            redis.opsForValue().set(key(f.getCandidateId()), f, ttl);
        } catch (RuntimeException e) {
            tripBreaker(e);
        }
    }

    private boolean redisAvailable() {
        return System.currentTimeMillis() >= redisDisabledUntil;
    }

    private void tripBreaker(RuntimeException e) {
        redisDisabledUntil = System.currentTimeMillis() + BREAKER_MILLIS;
        log.warn("Redis unavailable, falling back to SQL for {}s: {}", BREAKER_MILLIS / 1000, e.getMessage());
    }

    private static String key(Long id) {
        return KEY_PREFIX + id;
    }
}
