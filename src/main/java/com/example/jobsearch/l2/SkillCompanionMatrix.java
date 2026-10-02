package com.example.jobsearch.l2;

import org.springframework.stereotype.Component;

import java.util.HashMap;
import java.util.Map;

/** Symmetric skill-affinity matrix in [0, 1]: how strongly holding skill B implies competence in skill A. */
@Component
public class SkillCompanionMatrix {

    private final Map<String, Map<String, Double>> matrix = new HashMap<>();

    public SkillCompanionMatrix() {
        pair("java", "spring boot", 0.90);
        pair("java", "hibernate", 0.75);
        pair("java", "microservices", 0.70);
        pair("java", "kafka", 0.60);
        pair("java", "maven", 0.50);
        pair("java", "junit", 0.50);
        pair("java", "sql", 0.45);
        pair("spring boot", "microservices", 0.85);
        pair("spring boot", "hibernate", 0.70);
        pair("spring boot", "kafka", 0.65);
        pair("spring boot", "rate limiting", 0.55);
        pair("microservices", "rate limiting", 0.60);
        pair("microservices", "kafka", 0.70);
        pair("microservices", "docker", 0.60);
        pair("microservices", "kubernetes", 0.60);
        pair("docker", "kubernetes", 0.85);
        pair("rate limiting", "redis", 0.60);
        pair("redis", "caching", 0.70);
        pair("python", "django", 0.85);
        pair("python", "flask", 0.80);
        pair("python", "pandas", 0.75);
        pair("javascript", "typescript", 0.85);
        pair("javascript", "react", 0.85);
        pair("typescript", "react", 0.80);
        pair("aws", "terraform", 0.60);
        pair("aws", "docker", 0.50);
        pair("sql", "postgresql", 0.85);
        pair("sql", "mysql", 0.85);
        pair("recruiting", "talent acquisition", 0.90);
        pair("recruiting", "sourcing", 0.80);
        pair("talent acquisition", "sourcing", 0.70);
    }

    private void pair(String a, String b, double affinity) {
        matrix.computeIfAbsent(a, k -> new HashMap<>()).merge(b, affinity, Math::max);
        matrix.computeIfAbsent(b, k -> new HashMap<>()).merge(a, affinity, Math::max);
    }

    public double affinity(String queried, String held) {
        if (queried.equals(held)) {
            return 1.0;
        }
        return matrix.getOrDefault(queried, Map.of()).getOrDefault(held, 0.0);
    }

    public boolean isKnownSkill(String skill) {
        return matrix.containsKey(skill);
    }
}
