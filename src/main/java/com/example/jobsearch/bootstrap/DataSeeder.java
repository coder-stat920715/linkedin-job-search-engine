package com.example.jobsearch.bootstrap;

import com.example.jobsearch.dto.CandidateUpsertRequest;
import com.example.jobsearch.repository.CandidateRepository;
import com.example.jobsearch.service.ProfileIngestionService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.util.Set;

/** Seeds demo candidates on an empty database so the Swagger UI returns data immediately. */
@Slf4j
@Component
@RequiredArgsConstructor
public class DataSeeder {

    private final CandidateRepository candidates;
    private final ProfileIngestionService ingestion;

    @EventListener(ApplicationReadyEvent.class)
    @Order(2)
    public void seed() {
        if (candidates.count() > 0) {
            return;
        }
        ingestion.create(new CandidateUpsertRequest("Priya Nair", "Talent Acquisition Lead | Java hiring", "JPMorgan",
                "Talent Acquisition Specialist", "Mumbai", true, true, 0, Set.of("Java", "Recruiting", "Sourcing")));
        ingestion.create(new CandidateUpsertRequest("Rahul Mehta", "Technical Recruiter, Java and Spring", "JPMorgan",
                "Recruiter", "Mumbai", true, false, 30, Set.of("Java", "Spring Boot", "Recruiting")));
        ingestion.create(new CandidateUpsertRequest("Ananya Rao", "Senior Recruiter", "JPMorgan",
                "Recruiter", "Bengaluru", false, false, 60, Set.of("Java", "Talent Acquisition")));
        ingestion.create(new CandidateUpsertRequest("Karan Shah", "Backend Engineer", "Google",
                "Software Engineer", "Bengaluru", true, true, 0, Set.of("Java", "Spring Boot", "Microservices", "Kafka")));
        ingestion.create(new CandidateUpsertRequest("Sneha Iyer", "Java Developer", "Infosys",
                "Senior Developer", "Pune", true, false, 45, Set.of("Java", "Hibernate", "SQL")));
        ingestion.create(new CandidateUpsertRequest("Vikram Singh", "Platform Engineer", "Amazon",
                "SDE II", "Hyderabad", false, false, 90, Set.of("Spring Boot", "Rate Limiting", "Redis", "Docker")));
        ingestion.create(new CandidateUpsertRequest("Meera Joshi", "Data Scientist", "Flipkart",
                "Data Scientist", "Bengaluru", true, true, 15, Set.of("Python", "Pandas", "SQL")));
        ingestion.create(new CandidateUpsertRequest("Arjun Das", "Full-stack Developer", "TCS",
                "Developer", "Mumbai", true, true, 0, Set.of("JavaScript", "React", "TypeScript", "Java")));
        log.info("Seeded {} demo candidates", candidates.count());
    }
}
