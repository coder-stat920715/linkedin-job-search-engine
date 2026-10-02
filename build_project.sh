#!/usr/bin/env bash
# build_project.sh - writes the complete Spring Boot project to disk and zips it.
set -euo pipefail
ROOT="linkedin-job-search-engine"
J="$ROOT/src/main/java/com/example/jobsearch"
T="$ROOT/src/test/java/com/example/jobsearch"
R="$ROOT/src/main/resources"
rm -rf "$ROOT" "$ROOT.zip"
mkdir -p "$J"/{config,domain,repository,dto,query,l1,l2/scorer,pipeline,controller,event,service,exception,web,util,bootstrap} \
         "$T"/{query,l1,l2,pipeline,event} "$R/db" "$ROOT/docs"

cat > "$ROOT/pom.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.3.4</version>
        <relativePath/>
    </parent>
    <groupId>com.example</groupId>
    <artifactId>linkedin-job-search-engine</artifactId>
    <version>1.0.0</version>
    <name>linkedin-job-search-engine</name>
    <description>Job Search and Recruiter Candidate Matching System (L1 retrieval + L2 reranking)</description>
    <properties>
        <java.version>21</java.version>
        <springdoc.version>2.6.0</springdoc.version>
    </properties>
    <dependencies>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-jpa</artifactId></dependency>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-data-redis</artifactId></dependency>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-validation</artifactId></dependency>
        <dependency><groupId>org.springframework.kafka</groupId><artifactId>spring-kafka</artifactId></dependency>
        <dependency><groupId>org.springdoc</groupId><artifactId>springdoc-openapi-starter-webmvc-ui</artifactId><version>${springdoc.version}</version></dependency>
        <dependency><groupId>com.h2database</groupId><artifactId>h2</artifactId><scope>runtime</scope></dependency>
        <dependency><groupId>org.postgresql</groupId><artifactId>postgresql</artifactId><scope>runtime</scope></dependency>
        <dependency><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId><optional>true</optional></dependency>
        <dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency>
        <dependency><groupId>org.springframework.kafka</groupId><artifactId>spring-kafka-test</artifactId><scope>test</scope></dependency>
    </dependencies>
    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
                <configuration>
                    <excludes><exclude><groupId>org.projectlombok</groupId><artifactId>lombok</artifactId></exclude></excludes>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
EOF

cat > "$R/application.yml" <<'EOF'
server:
  port: 8080

spring:
  application:
    name: linkedin-job-search-engine
  threads:
    virtual:
      enabled: true
  datasource:
    url: jdbc:h2:mem:jobsearch;MODE=PostgreSQL;DB_CLOSE_DELAY=-1
    username: sa
    password:
    driver-class-name: org.h2.Driver
  jpa:
    open-in-view: false
    hibernate:
      ddl-auto: update
    properties:
      hibernate.jdbc.batch_size: 50
  h2:
    console:
      enabled: true
  data:
    redis:
      host: localhost
      port: 6379
      timeout: 500ms
      connect-timeout: 1s
  kafka:
    bootstrap-servers: localhost:9092

springdoc:
  swagger-ui:
    path: /swagger-ui.html

app:
  kafka:
    engagement-topic: candidate-engagement-events
    group-id: l2-feature-updater
    listener-enabled: true      # false = do not start the Kafka consumer
    publish-enabled: true       # false = engagement API dispatches events in-process (no broker needed)
  feature-store:
    ttl-minutes: 10
  search:
    l1-max-candidates: 2000
    l2-max-candidates: 500
    companion-discount: 0.8
    weights:
      skill-match: 0.40         # w1
      in-mail-response: 0.30    # w2
      open-to-work: 0.20        # w3
      freshness: 0.10           # w4

logging:
  pattern:
    level: "%5p [%X{traceId:-}]"
  level:
    com.example.jobsearch: INFO

---
spring:
  config:
    activate:
      on-profile: postgres
  datasource:
    url: jdbc:postgresql://localhost:5432/jobsearch
    username: jobsearch
    password: jobsearch
    driver-class-name: org.postgresql.Driver
  h2:
    console:
      enabled: false
EOF

cat > "$J/JobSearchApplication.java" <<'EOF'
package com.example.jobsearch;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.ConfigurationPropertiesScan;
import org.springframework.scheduling.annotation.EnableScheduling;

@SpringBootApplication
@ConfigurationPropertiesScan
@EnableScheduling
public class JobSearchApplication {
    public static void main(String[] args) {
        SpringApplication.run(JobSearchApplication.class, args);
    }
}
EOF

# ---------------------------------------------------------------- config
cat > "$J/config/SearchProperties.java" <<'EOF'
package com.example.jobsearch.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

@Data
@ConfigurationProperties(prefix = "app.search")
public class SearchProperties {
    private int l1MaxCandidates = 2000;
    private int l2MaxCandidates = 500;
    private double companionDiscount = 0.8;
    private Weights weights = new Weights();

    @Data
    public static class Weights {
        private double skillMatch = 0.40;
        private double inMailResponse = 0.30;
        private double openToWork = 0.20;
        private double freshness = 0.10;
    }
}
EOF

cat > "$J/config/RedisConfig.java" <<'EOF'
package com.example.jobsearch.config;

import com.example.jobsearch.domain.CandidateFeatureSet;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.data.redis.serializer.Jackson2JsonRedisSerializer;
import org.springframework.data.redis.serializer.StringRedisSerializer;

@Configuration
public class RedisConfig {

    @Bean
    public RedisTemplate<String, CandidateFeatureSet> featureRedisTemplate(RedisConnectionFactory factory,
                                                                           ObjectMapper objectMapper) {
        RedisTemplate<String, CandidateFeatureSet> template = new RedisTemplate<>();
        template.setConnectionFactory(factory);
        StringRedisSerializer keySerializer = new StringRedisSerializer();
        Jackson2JsonRedisSerializer<CandidateFeatureSet> valueSerializer =
                new Jackson2JsonRedisSerializer<>(objectMapper, CandidateFeatureSet.class);
        template.setKeySerializer(keySerializer);
        template.setHashKeySerializer(keySerializer);
        template.setValueSerializer(valueSerializer);
        template.setHashValueSerializer(valueSerializer);
        template.afterPropertiesSet();
        return template;
    }
}
EOF

cat > "$J/config/KafkaConfig.java" <<'EOF'
package com.example.jobsearch.config;

import com.example.jobsearch.dto.EngagementEvent;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.ConcurrentKafkaListenerContainerFactory;
import org.springframework.kafka.config.TopicBuilder;
import org.springframework.kafka.core.ConsumerFactory;
import org.springframework.kafka.core.DefaultKafkaConsumerFactory;
import org.springframework.kafka.core.DefaultKafkaProducerFactory;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.core.ProducerFactory;
import org.springframework.kafka.listener.DefaultErrorHandler;
import org.springframework.kafka.support.serializer.ErrorHandlingDeserializer;
import org.springframework.kafka.support.serializer.JsonDeserializer;
import org.springframework.kafka.support.serializer.JsonSerializer;
import org.springframework.util.backoff.FixedBackOff;
import org.apache.kafka.clients.admin.NewTopic;

import java.util.HashMap;
import java.util.Map;

@Configuration
public class KafkaConfig {

    @Value("${spring.kafka.bootstrap-servers}")
    private String bootstrapServers;

    @Value("${app.kafka.engagement-topic}")
    private String engagementTopic;

    @Value("${app.kafka.group-id}")
    private String groupId;

    @Bean
    public NewTopic engagementTopic() {
        return TopicBuilder.name(engagementTopic).partitions(12).replicas(1).build();
    }

    @Bean
    public ProducerFactory<String, EngagementEvent> engagementProducerFactory(ObjectMapper objectMapper) {
        Map<String, Object> props = new HashMap<>();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ProducerConfig.ACKS_CONFIG, "all");
        props.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
        props.put(ProducerConfig.MAX_BLOCK_MS_CONFIG, 2000);
        props.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, 3000);
        props.put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, 5000);
        JsonSerializer<EngagementEvent> valueSerializer = new JsonSerializer<>(objectMapper);
        valueSerializer.setAddTypeInfo(false);
        return new DefaultKafkaProducerFactory<>(props, new StringSerializer(), valueSerializer);
    }

    @Bean
    public KafkaTemplate<String, EngagementEvent> engagementKafkaTemplate(
            ProducerFactory<String, EngagementEvent> engagementProducerFactory) {
        return new KafkaTemplate<>(engagementProducerFactory);
    }

    @Bean
    public ConsumerFactory<String, EngagementEvent> engagementConsumerFactory(ObjectMapper objectMapper) {
        Map<String, Object> props = new HashMap<>();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, groupId);
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);
        JsonDeserializer<EngagementEvent> json = new JsonDeserializer<>(EngagementEvent.class, objectMapper, false);
        return new DefaultKafkaConsumerFactory<>(props, new StringDeserializer(), new ErrorHandlingDeserializer<>(json));
    }

    @Bean(name = "kafkaListenerContainerFactory")
    public ConcurrentKafkaListenerContainerFactory<String, EngagementEvent> kafkaListenerContainerFactory(
            ConsumerFactory<String, EngagementEvent> engagementConsumerFactory) {
        ConcurrentKafkaListenerContainerFactory<String, EngagementEvent> factory =
                new ConcurrentKafkaListenerContainerFactory<>();
        factory.setConsumerFactory(engagementConsumerFactory);
        factory.setConcurrency(3);
        factory.setCommonErrorHandler(new DefaultErrorHandler(new FixedBackOff(1000L, 3L)));
        return factory;
    }
}
EOF

cat > "$J/config/SwaggerConfig.java" <<'EOF'
package com.example.jobsearch.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class SwaggerConfig {

    @Bean
    public OpenAPI jobSearchOpenApi() {
        return new OpenAPI().info(new Info()
                .title("Job Search & Recruiter Candidate Matching API")
                .version("1.0.0")
                .description("L1 Boolean retrieval + L2 multi-factor reranking over candidate profiles")
                .contact(new Contact().name("Search & Matching Infrastructure")));
    }
}
EOF

cat > "$J/config/ExecutorConfig.java" <<'EOF'
package com.example.jobsearch.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@Configuration
public class ExecutorConfig {

    /** Virtual-thread-per-task executor used for parallel L2 scoring (Java 21). */
    @Bean(name = "scoringExecutor")
    public ExecutorService scoringExecutor() {
        return Executors.newVirtualThreadPerTaskExecutor();
    }
}
EOF

# ---------------------------------------------------------------- domain
cat > "$J/domain/Candidate.java" <<'EOF'
package com.example.jobsearch.domain;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.HashSet;
import java.util.Set;

@Entity
@Table(name = "candidates", indexes = {
        @Index(name = "idx_candidates_company", columnList = "current_company"),
        @Index(name = "idx_candidates_location", columnList = "location")})
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Candidate {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String fullName;

    @Column(length = 500)
    private String headline;

    @Column(name = "current_company")
    private String currentCompany;

    private String currentTitle;

    @Column(name = "location")
    private String location;

    private boolean openToWork;
    private boolean immediateJoiner;
    private Integer noticePeriodDays;
    private Instant lastActiveAt;
    private Instant profileUpdatedAt;

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "candidate_skills", joinColumns = @JoinColumn(name = "candidate_id"))
    @Column(name = "skill", nullable = false)
    @Builder.Default
    private Set<String> skills = new HashSet<>();
}
EOF

cat > "$J/domain/JobPosting.java" <<'EOF'
package com.example.jobsearch.domain;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.HashSet;
import java.util.Set;

@Entity
@Table(name = "job_postings")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class JobPosting {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String title;

    @Column(nullable = false)
    private String company;

    private String location;

    @Column(length = 4000)
    private String description;

    private Integer minExperienceYears;
    private Long recruiterId;
    private Instant postedAt;
    private boolean active;

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "job_required_skills", joinColumns = @JoinColumn(name = "job_id"))
    @Column(name = "skill", nullable = false)
    @Builder.Default
    private Set<String> requiredSkills = new HashSet<>();
}
EOF

cat > "$J/domain/InMailInteraction.java" <<'EOF'
package com.example.jobsearch.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

@Entity
@Table(name = "inmail_communications", indexes = {
        @Index(name = "idx_inmail_candidate", columnList = "candidate_id"),
        @Index(name = "idx_inmail_recruiter", columnList = "recruiter_id")})
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class InMailInteraction {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "message_id", nullable = false, unique = true)
    private String messageId;

    @Column(name = "candidate_id", nullable = false)
    private Long candidateId;

    @Column(name = "recruiter_id")
    private Long recruiterId;

    @Column(name = "sent_at", nullable = false)
    private Instant sentAt;

    @Column(name = "responded_at")
    private Instant respondedAt;
}
EOF

cat > "$J/domain/RecruiterSearch.java" <<'EOF'
package com.example.jobsearch.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

@Entity
@Table(name = "recruiter_searches")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class RecruiterSearch {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long recruiterId;

    @Column(name = "raw_query", length = 2000, nullable = false)
    private String rawQuery;

    private int resultCount;
    private long tookMs;
    private Instant createdAt;
}
EOF

cat > "$J/domain/CandidateFeatureSet.java" <<'EOF'
package com.example.jobsearch.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

/** L2 feature-store row: system of record in SQL, hot copy in Redis. */
@Entity
@Table(name = "candidate_feature_scores")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CandidateFeatureSet {

    @Id
    @Column(name = "candidate_id")
    private Long candidateId;

    @Column(name = "inmails_received", nullable = false)
    private int inMailsReceived;

    @Column(name = "inmails_responded", nullable = false)
    private int inMailsResponded;

    @Column(name = "avg_response_hours", nullable = false)
    private double avgResponseHours;

    @Column(name = "session_activity", nullable = false)
    private double sessionActivity;

    @Column(name = "updated_at")
    private Instant updatedAt;

    public static CandidateFeatureSet empty(Long candidateId) {
        return CandidateFeatureSet.builder().candidateId(candidateId).updatedAt(Instant.now()).build();
    }
}
EOF

# ---------------------------------------------------------------- repositories
cat > "$J/repository/CandidateRepository.java" <<'EOF'
package com.example.jobsearch.repository;

import com.example.jobsearch.domain.Candidate;
import org.springframework.data.jpa.repository.JpaRepository;

public interface CandidateRepository extends JpaRepository<Candidate, Long> {
}
EOF

cat > "$J/repository/JobPostingRepository.java" <<'EOF'
package com.example.jobsearch.repository;

import com.example.jobsearch.domain.JobPosting;
import org.springframework.data.jpa.repository.JpaRepository;

public interface JobPostingRepository extends JpaRepository<JobPosting, Long> {
}
EOF

cat > "$J/repository/InMailInteractionRepository.java" <<'EOF'
package com.example.jobsearch.repository;

import com.example.jobsearch.domain.InMailInteraction;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface InMailInteractionRepository extends JpaRepository<InMailInteraction, Long> {
    Optional<InMailInteraction> findByMessageId(String messageId);
}
EOF

cat > "$J/repository/RecruiterSearchRepository.java" <<'EOF'
package com.example.jobsearch.repository;

import com.example.jobsearch.domain.RecruiterSearch;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RecruiterSearchRepository extends JpaRepository<RecruiterSearch, Long> {
}
EOF

cat > "$J/repository/CandidateFeatureSetRepository.java" <<'EOF'
package com.example.jobsearch.repository;

import com.example.jobsearch.domain.CandidateFeatureSet;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Optional;

public interface CandidateFeatureSetRepository extends JpaRepository<CandidateFeatureSet, Long> {

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select f from CandidateFeatureSet f where f.candidateId = :id")
    Optional<CandidateFeatureSet> findForUpdate(@Param("id") Long id);

    @Modifying
    @Query("update CandidateFeatureSet f set f.sessionActivity = f.sessionActivity * :factor")
    int decaySessionActivity(@Param("factor") double factor);
}
EOF

cat > "$J/util/TxUtils.java" <<'EOF'
package com.example.jobsearch.util;

import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

public final class TxUtils {

    private TxUtils() {
    }

    /** Runs the action after the surrounding transaction commits, or immediately when none is active. */
    public static void afterCommit(Runnable action) {
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    action.run();
                }
            });
        } else {
            action.run();
        }
    }
}
EOF

# ---------------------------------------------------------------- dto
cat > "$J/dto/RecruiterSearchRequest.java" <<'EOF'
package com.example.jobsearch.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.List;

public record RecruiterSearchRequest(
        @Schema(example = "\"JPMorgan\" AND (\"Talent Acquisition\" OR \"Recruiter\") AND \"Java\" AND \"Immediate Joiner\"")
        @NotBlank @Size(max = 2000) String query,
        List<@NotBlank String> requiredSkills,
        String location,
        Boolean openToWorkOnly,
        @Min(0) Integer maxNoticePeriodDays,
        @Min(1) @Max(100) Integer pageSize,
        Long recruiterId) {

    public int effectivePageSize() {
        return pageSize == null ? 20 : pageSize;
    }

    public List<String> skillsOrEmpty() {
        return requiredSkills == null ? List.of() : requiredSkills;
    }
}
EOF

cat > "$J/dto/CandidateSearchResultDTO.java" <<'EOF'
package com.example.jobsearch.dto;

import java.util.List;
import java.util.Map;

public record CandidateSearchResultDTO(
        Long candidateId,
        String fullName,
        String headline,
        String currentCompany,
        String currentTitle,
        String location,
        boolean openToWork,
        double score,
        Map<String, Double> scoreBreakdown,
        List<String> matchedSkills) {
}
EOF

cat > "$J/dto/SearchResponse.java" <<'EOF'
package com.example.jobsearch.dto;

import java.util.List;

public record SearchResponse(
        String searchId,
        int l1Matches,
        int afterFilters,
        long tookMs,
        List<CandidateSearchResultDTO> results) {
}
EOF

cat > "$J/dto/EngagementType.java" <<'EOF'
package com.example.jobsearch.dto;

public enum EngagementType {
    INMAIL_SENT,
    INMAIL_RESPONDED,
    PROFILE_VIEWED,
    SESSION_ACTIVITY
}
EOF

cat > "$J/dto/EngagementEvent.java" <<'EOF'
package com.example.jobsearch.dto;

import jakarta.validation.constraints.NotNull;

import java.time.Instant;

public record EngagementEvent(
        String eventId,
        @NotNull EngagementType type,
        @NotNull Long candidateId,
        Long recruiterId,
        String messageId,
        Instant occurredAt) {
}
EOF

cat > "$J/dto/CandidateUpsertRequest.java" <<'EOF'
package com.example.jobsearch.dto;

import jakarta.validation.constraints.NotBlank;

import java.util.Set;

public record CandidateUpsertRequest(
        @NotBlank String fullName,
        String headline,
        String currentCompany,
        String currentTitle,
        String location,
        boolean openToWork,
        boolean immediateJoiner,
        Integer noticePeriodDays,
        Set<String> skills) {
}
EOF

cat > "$J/dto/JobPostingRequest.java" <<'EOF'
package com.example.jobsearch.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;

import java.util.Set;

public record JobPostingRequest(
        @NotBlank String title,
        @NotBlank String company,
        String location,
        String description,
        Integer minExperienceYears,
        Long recruiterId,
        @NotEmpty Set<@NotBlank String> requiredSkills) {
}
EOF

# ---------------------------------------------------------------- exceptions
cat > "$J/exception/QueryParseException.java" <<'EOF'
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
EOF

cat > "$J/exception/ResourceNotFoundException.java" <<'EOF'
package com.example.jobsearch.exception;

public class ResourceNotFoundException extends RuntimeException {
    public ResourceNotFoundException(String message) {
        super(message);
    }
}
EOF

cat > "$J/exception/GlobalExceptionHandler.java" <<'EOF'
package com.example.jobsearch.exception;

import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.ErrorResponse;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.LinkedHashMap;
import java.util.Map;

@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(QueryParseException.class)
    public ProblemDetail handleQueryParse(QueryParseException ex) {
        log.warn("Invalid boolean query: {}", ex.getMessage());
        ProblemDetail pd = problem(HttpStatus.BAD_REQUEST, "Invalid Boolean query", ex.getMessage());
        pd.setProperty("position", ex.getPosition());
        return pd;
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ProblemDetail handleValidation(MethodArgumentNotValidException ex) {
        Map<String, String> errors = new LinkedHashMap<>();
        ex.getBindingResult().getFieldErrors()
                .forEach(fe -> errors.putIfAbsent(fe.getField(), String.valueOf(fe.getDefaultMessage())));
        ProblemDetail pd = problem(HttpStatus.BAD_REQUEST, "Validation failed", "Request validation failed");
        pd.setProperty("errors", errors);
        return pd;
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ProblemDetail handleUnreadable(HttpMessageNotReadableException ex) {
        return problem(HttpStatus.BAD_REQUEST, "Malformed request body", "Request body is missing or malformed JSON");
    }

    @ExceptionHandler(ResourceNotFoundException.class)
    public ProblemDetail handleNotFound(ResourceNotFoundException ex) {
        return problem(HttpStatus.NOT_FOUND, "Resource not found", ex.getMessage());
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<?> handleAny(Exception ex) {
        if (ex instanceof ErrorResponse er) {
            return ResponseEntity.status(er.getStatusCode()).body(er.getBody());
        }
        log.error("Unhandled exception", ex);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(problem(HttpStatus.INTERNAL_SERVER_ERROR, "Internal error", "Unexpected server error"));
    }

    private ProblemDetail problem(HttpStatus status, String title, String detail) {
        ProblemDetail pd = ProblemDetail.forStatusAndDetail(status, detail);
        pd.setTitle(title);
        String traceId = MDC.get("traceId");
        if (traceId != null) {
            pd.setProperty("traceId", traceId);
        }
        return pd;
    }
}
EOF

# ---------------------------------------------------------------- query (AST + factory + parser)
cat > "$J/query/TermNormalizer.java" <<'EOF'
package com.example.jobsearch.query;

import java.util.Locale;

public final class TermNormalizer {

    private TermNormalizer() {
    }

    public static String normalize(String raw) {
        return raw == null ? "" : raw.toLowerCase(Locale.ROOT).trim().replaceAll("\\s+", " ");
    }
}
EOF

cat > "$J/query/PostingsSource.java" <<'EOF'
package com.example.jobsearch.query;

import java.util.Set;

/** Read-only view of an inverted index. Returned sets must never be mutated by callers. */
public interface PostingsSource {
    Set<Long> postings(String term);

    Set<Long> universe();
}
EOF

cat > "$J/query/QueryNode.java" <<'EOF'
package com.example.jobsearch.query;

import java.util.Set;

public interface QueryNode {

    /** Evaluates this node against the index, always returning a fresh mutable set. */
    Set<Long> evaluate(PostingsSource source);

    /** Collects terms that appear outside any NOT; used by L2 to derive the queried skills. */
    void collectPositiveTerms(Set<String> out);
}
EOF

cat > "$J/query/TermNode.java" <<'EOF'
package com.example.jobsearch.query;

import java.util.HashSet;
import java.util.Set;

public record TermNode(String term) implements QueryNode {

    @Override
    public Set<Long> evaluate(PostingsSource source) {
        return new HashSet<>(source.postings(term));
    }

    @Override
    public void collectPositiveTerms(Set<String> out) {
        out.add(term);
    }
}
EOF

cat > "$J/query/NotNode.java" <<'EOF'
package com.example.jobsearch.query;

import java.util.HashSet;
import java.util.Set;

public record NotNode(QueryNode inner) implements QueryNode {

    @Override
    public Set<Long> evaluate(PostingsSource source) {
        Set<Long> result = new HashSet<>(source.universe());
        result.removeAll(inner.evaluate(source));
        return result;
    }

    @Override
    public void collectPositiveTerms(Set<String> out) {
        // terms under NOT are exclusions, not preferences
    }
}
EOF

cat > "$J/query/AndNode.java" <<'EOF'
package com.example.jobsearch.query;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public record AndNode(List<QueryNode> children) implements QueryNode {

    /** Intersects positive children smallest-first, then subtracts NOT children (avoids materialising the universe). */
    @Override
    public Set<Long> evaluate(PostingsSource source) {
        List<Set<Long>> positives = new ArrayList<>();
        List<Set<Long>> negatives = new ArrayList<>();
        for (QueryNode child : children) {
            if (child instanceof NotNode not) {
                negatives.add(not.inner().evaluate(source));
            } else {
                positives.add(child.evaluate(source));
            }
        }
        Set<Long> result;
        if (positives.isEmpty()) {
            result = new HashSet<>(source.universe());
        } else {
            positives.sort(Comparator.comparingInt(Set::size));
            result = new HashSet<>(positives.get(0));
            for (int i = 1; i < positives.size() && !result.isEmpty(); i++) {
                result.retainAll(positives.get(i));
            }
        }
        for (Set<Long> negative : negatives) {
            result.removeAll(negative);
        }
        return result;
    }

    @Override
    public void collectPositiveTerms(Set<String> out) {
        children.forEach(c -> c.collectPositiveTerms(out));
    }
}
EOF

cat > "$J/query/OrNode.java" <<'EOF'
package com.example.jobsearch.query;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

public record OrNode(List<QueryNode> children) implements QueryNode {

    @Override
    public Set<Long> evaluate(PostingsSource source) {
        Set<Long> result = new HashSet<>();
        for (QueryNode child : children) {
            result.addAll(child.evaluate(source));
        }
        return result;
    }

    @Override
    public void collectPositiveTerms(Set<String> out) {
        children.forEach(c -> c.collectPositiveTerms(out));
    }
}
EOF

cat > "$J/query/QueryNodeFactory.java" <<'EOF'
package com.example.jobsearch.query;

import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/** Factory Pattern: single place that builds (and normalises/flattens) AST nodes. */
@Component
public class QueryNodeFactory {

    public QueryNode term(String raw) {
        return new TermNode(TermNormalizer.normalize(raw));
    }

    public QueryNode not(QueryNode inner) {
        return new NotNode(inner);
    }

    public QueryNode and(List<QueryNode> children) {
        if (children.size() == 1) {
            return children.get(0);
        }
        List<QueryNode> flat = new ArrayList<>();
        for (QueryNode c : children) {
            if (c instanceof AndNode and) {
                flat.addAll(and.children());
            } else {
                flat.add(c);
            }
        }
        return new AndNode(List.copyOf(flat));
    }

    public QueryNode or(List<QueryNode> children) {
        if (children.size() == 1) {
            return children.get(0);
        }
        List<QueryNode> flat = new ArrayList<>();
        for (QueryNode c : children) {
            if (c instanceof OrNode or) {
                flat.addAll(or.children());
            } else {
                flat.add(c);
            }
        }
        return new OrNode(List.copyOf(flat));
    }
}
EOF

cat > "$J/query/BooleanQueryParserService.java" <<'EOF'
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
EOF

# ---------------------------------------------------------------- L1
cat > "$J/l1/InvertedIndex.java" <<'EOF'
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
EOF

cat > "$J/l1/CandidateTermExtractor.java" <<'EOF'
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
EOF

cat > "$J/l1/L1CandidateRetrievalService.java" <<'EOF'
package com.example.jobsearch.l1;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.query.QueryNode;
import com.example.jobsearch.repository.CandidateRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Set;

/** L1 fast retrieval: Boolean AST evaluation on the inverted index, then hydrate candidates from the system of record. */
@Slf4j
@Service
@RequiredArgsConstructor
public class L1CandidateRetrievalService {

    private final InvertedIndex index;
    private final CandidateTermExtractor extractor;
    private final CandidateRepository candidateRepository;
    private final SearchProperties properties;

    public record L1Result(List<Candidate> candidates, int totalMatches) {
    }

    public void indexCandidate(Candidate candidate) {
        index.upsert(candidate.getId(), extractor.extract(candidate));
    }

    public void removeCandidate(Long candidateId) {
        index.remove(candidateId);
    }

    @EventListener(ApplicationReadyEvent.class)
    @Order(1)
    public void rebuildOnStartup() {
        log.info("L1 index rebuilt with {} candidates", rebuildIndex());
    }

    public int rebuildIndex() {
        index.clear();
        candidateRepository.findAll().forEach(this::indexCandidate);
        return index.size();
    }

    public L1Result retrieve(QueryNode ast) {
        Set<Long> ids = index.search(ast);
        int total = ids.size();
        List<Long> limited = ids.stream().sorted().limit(properties.getL1MaxCandidates()).toList();
        List<Candidate> candidates = limited.isEmpty() ? List.of() : candidateRepository.findAllById(limited);
        log.debug("L1 retrieved {} matches, hydrated {}", total, candidates.size());
        return new L1Result(candidates, total);
    }
}
EOF

# ---------------------------------------------------------------- feature store service
cat > "$J/service/FeatureStoreService.java" <<'EOF'
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
EOF

cat > "$J/service/FeatureDecayJob.java" <<'EOF'
package com.example.jobsearch.service;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Nightly exponential decay so session activity approximates a rolling 7-day window. */
@Slf4j
@Component
@RequiredArgsConstructor
public class FeatureDecayJob {

    private final FeatureStoreService featureStore;

    @Scheduled(cron = "0 0 3 * * *")
    public void decay() {
        int rows = featureStore.decaySessions(6.0 / 7.0);
        log.info("Decayed session activity for {} candidates", rows);
    }
}
EOF

# ---------------------------------------------------------------- L2
cat > "$J/l2/ScoringContext.java" <<'EOF'
package com.example.jobsearch.l2;

import java.time.Instant;
import java.util.Set;

public record ScoringContext(Set<String> queriedSkills, Instant now) {
}
EOF

cat > "$J/l2/ScoredCandidate.java" <<'EOF'
package com.example.jobsearch.l2;

import com.example.jobsearch.domain.Candidate;

import java.util.Map;

public record ScoredCandidate(Candidate candidate, double score, Map<String, Double> breakdown) {
}
EOF

cat > "$J/l2/CandidateScorer.java" <<'EOF'
package com.example.jobsearch.l2;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;

/** Strategy Pattern: each scorer returns a normalised value in [0, 1]. */
public interface CandidateScorer {

    String name();

    double weight();

    double score(Candidate candidate, CandidateFeatureSet features, ScoringContext context);
}
EOF

cat > "$J/l2/SkillCompanionMatrix.java" <<'EOF'
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
EOF

cat > "$J/l2/scorer/SkillCompanionScorer.java" <<'EOF'
package com.example.jobsearch.l2.scorer;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.l2.CandidateScorer;
import com.example.jobsearch.l2.ScoringContext;
import com.example.jobsearch.l2.SkillCompanionMatrix;
import com.example.jobsearch.query.TermNormalizer;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.util.Set;
import java.util.stream.Collectors;

/**
 * SkillMatch = (1/|Q|) * sum over queried skills q of:
 *   1                         if the candidate holds q
 *   discount * max_h A[q][h]  otherwise (best companion skill h the candidate holds)
 */
@Component
@RequiredArgsConstructor
public class SkillCompanionScorer implements CandidateScorer {

    private final SkillCompanionMatrix matrix;
    private final SearchProperties properties;

    @Override
    public String name() {
        return "skillMatch";
    }

    @Override
    public double weight() {
        return properties.getWeights().getSkillMatch();
    }

    @Override
    public double score(Candidate candidate, CandidateFeatureSet features, ScoringContext context) {
        Set<String> queried = context.queriedSkills();
        if (queried.isEmpty()) {
            return 0.5;
        }
        Set<String> held = candidate.getSkills().stream().map(TermNormalizer::normalize).collect(Collectors.toSet());
        double sum = 0.0;
        for (String q : queried) {
            if (held.contains(q)) {
                sum += 1.0;
            } else {
                double best = held.stream().mapToDouble(h -> matrix.affinity(q, h)).max().orElse(0.0);
                sum += best * properties.getCompanionDiscount();
            }
        }
        return sum / queried.size();
    }
}
EOF

cat > "$J/l2/scorer/InMailResponsivenessScorer.java" <<'EOF'
package com.example.jobsearch.l2.scorer;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.l2.CandidateScorer;
import com.example.jobsearch.l2.ScoringContext;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * Bayesian-smoothed response rate (prior 0.3, strength 5) blended with an exponential speed factor:
 * score = 0.8 * (responded + 5*0.3) / (received + 5) + 0.2 * exp(-avgResponseHours / 48)
 */
@Component
@RequiredArgsConstructor
public class InMailResponsivenessScorer implements CandidateScorer {

    private static final double PRIOR_RATE = 0.3;
    private static final double PRIOR_STRENGTH = 5.0;

    private final SearchProperties properties;

    @Override
    public String name() {
        return "inMailResponse";
    }

    @Override
    public double weight() {
        return properties.getWeights().getInMailResponse();
    }

    @Override
    public double score(Candidate candidate, CandidateFeatureSet f, ScoringContext context) {
        double rate = (f.getInMailsResponded() + PRIOR_STRENGTH * PRIOR_RATE) / (f.getInMailsReceived() + PRIOR_STRENGTH);
        double speed = f.getInMailsResponded() == 0 ? 0.5 : Math.exp(-f.getAvgResponseHours() / 48.0);
        return Math.min(1.0, 0.8 * rate + 0.2 * speed);
    }
}
EOF

cat > "$J/l2/scorer/OpenToWorkScorer.java" <<'EOF'
package com.example.jobsearch.l2.scorer;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.l2.CandidateScorer;
import com.example.jobsearch.l2.ScoringContext;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

@Component
@RequiredArgsConstructor
public class OpenToWorkScorer implements CandidateScorer {

    private final SearchProperties properties;

    @Override
    public String name() {
        return "openToWork";
    }

    @Override
    public double weight() {
        return properties.getWeights().getOpenToWork();
    }

    @Override
    public double score(Candidate candidate, CandidateFeatureSet features, ScoringContext context) {
        if (!candidate.isOpenToWork()) {
            return 0.1;
        }
        return candidate.isImmediateJoiner() ? 1.0 : 0.8;
    }
}
EOF

cat > "$J/l2/scorer/FreshnessScorer.java" <<'EOF'
package com.example.jobsearch.l2.scorer;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.l2.CandidateScorer;
import com.example.jobsearch.l2.ScoringContext;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;

/**
 * Freshness = 0.4 * 2^(-daysSinceProfileUpdate/90) + 0.3 * 2^(-daysSinceLastActive/14) + 0.3 * min(1, sessionActivity/10)
 */
@Component
@RequiredArgsConstructor
public class FreshnessScorer implements CandidateScorer {

    private final SearchProperties properties;

    @Override
    public String name() {
        return "freshness";
    }

    @Override
    public double weight() {
        return properties.getWeights().getFreshness();
    }

    @Override
    public double score(Candidate candidate, CandidateFeatureSet f, ScoringContext context) {
        double profile = halfLifeDecay(candidate.getProfileUpdatedAt(), context.now(), 90.0);
        double active = halfLifeDecay(candidate.getLastActiveAt(), context.now(), 14.0);
        double sessions = Math.min(1.0, f.getSessionActivity() / 10.0);
        return 0.4 * profile + 0.3 * active + 0.3 * sessions;
    }

    private double halfLifeDecay(Instant then, Instant now, double halfLifeDays) {
        if (then == null) {
            return 0.0;
        }
        double days = Math.max(0.0, Duration.between(then, now).toMinutes() / 1440.0);
        return Math.pow(2.0, -days / halfLifeDays);
    }
}
EOF

cat > "$J/l2/L2RerankingEngine.java" <<'EOF'
package com.example.jobsearch.l2;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.service.FeatureStoreService;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;

/** Score = sum(w_i * s_i) / sum(w_i), so the final score stays in [0, 1]. Candidates are scored in parallel. */
@Slf4j
@Service
public class L2RerankingEngine {

    private final List<CandidateScorer> scorers;
    private final FeatureStoreService featureStore;
    private final ExecutorService executor;

    public L2RerankingEngine(List<CandidateScorer> scorers,
                             FeatureStoreService featureStore,
                             @Qualifier("scoringExecutor") ExecutorService executor) {
        this.scorers = scorers;
        this.featureStore = featureStore;
        this.executor = executor;
    }

    public List<ScoredCandidate> rerank(List<Candidate> candidates, ScoringContext context) {
        if (candidates.isEmpty()) {
            return List.of();
        }
        double totalWeight = scorers.stream().mapToDouble(CandidateScorer::weight).sum();
        if (totalWeight <= 0) {
            throw new IllegalStateException("Sum of scorer weights must be positive");
        }
        Map<Long, CandidateFeatureSet> features =
                featureStore.getBatch(candidates.stream().map(Candidate::getId).toList());
        Map<String, String> mdc = MDC.getCopyOfContextMap();

        List<CompletableFuture<ScoredCandidate>> futures = candidates.stream()
                .map(c -> CompletableFuture.supplyAsync(() -> scoreOne(c,
                        features.getOrDefault(c.getId(), CandidateFeatureSet.empty(c.getId())),
                        context, totalWeight, mdc), executor))
                .toList();

        List<ScoredCandidate> ranked = futures.stream()
                .map(CompletableFuture::join)
                .sorted(Comparator.comparingDouble(ScoredCandidate::score).reversed()
                        .thenComparing(s -> s.candidate().getId()))
                .toList();
        log.debug("L2 reranked {} candidates using {} scorers", ranked.size(), scorers.size());
        return ranked;
    }

    private ScoredCandidate scoreOne(Candidate c, CandidateFeatureSet f, ScoringContext ctx,
                                     double totalWeight, Map<String, String> mdc) {
        if (mdc != null) {
            MDC.setContextMap(mdc);
        }
        try {
            Map<String, Double> breakdown = new LinkedHashMap<>();
            double weighted = 0.0;
            for (CandidateScorer scorer : scorers) {
                double s = Math.max(0.0, Math.min(1.0, scorer.score(c, f, ctx)));
                breakdown.put(scorer.name(), s);
                weighted += scorer.weight() * s;
            }
            return new ScoredCandidate(c, weighted / totalWeight, breakdown);
        } finally {
            MDC.clear();
        }
    }
}
EOF

# ---------------------------------------------------------------- filter chain (Chain of Responsibility)
cat > "$J/pipeline/CandidateFilterHandler.java" <<'EOF'
package com.example.jobsearch.pipeline;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.RecruiterSearchRequest;

import java.util.List;

public interface CandidateFilterHandler {
    List<Candidate> handle(List<Candidate> candidates, RecruiterSearchRequest request, CandidateFilterChain chain);
}
EOF

cat > "$J/pipeline/CandidateFilterChain.java" <<'EOF'
package com.example.jobsearch.pipeline;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.RecruiterSearchRequest;

import java.util.List;

/** Stateful, per-request chain: each handler filters and delegates to the next. */
public class CandidateFilterChain {

    private final List<CandidateFilterHandler> handlers;
    private int position = 0;

    public CandidateFilterChain(List<CandidateFilterHandler> handlers) {
        this.handlers = handlers;
    }

    public List<Candidate> proceed(List<Candidate> candidates, RecruiterSearchRequest request) {
        if (position >= handlers.size()) {
            return candidates;
        }
        return handlers.get(position++).handle(candidates, request, this);
    }
}
EOF

cat > "$J/pipeline/LocationFilterHandler.java" <<'EOF'
package com.example.jobsearch.pipeline;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import com.example.jobsearch.query.TermNormalizer;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
@Order(10)
public class LocationFilterHandler implements CandidateFilterHandler {

    @Override
    public List<Candidate> handle(List<Candidate> candidates, RecruiterSearchRequest request, CandidateFilterChain chain) {
        String wanted = TermNormalizer.normalize(request.location());
        if (wanted.isEmpty()) {
            return chain.proceed(candidates, request);
        }
        List<Candidate> filtered = candidates.stream()
                .filter(c -> TermNormalizer.normalize(c.getLocation()).contains(wanted))
                .toList();
        return chain.proceed(filtered, request);
    }
}
EOF

cat > "$J/pipeline/OpenToWorkFilterHandler.java" <<'EOF'
package com.example.jobsearch.pipeline;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
@Order(20)
public class OpenToWorkFilterHandler implements CandidateFilterHandler {

    @Override
    public List<Candidate> handle(List<Candidate> candidates, RecruiterSearchRequest request, CandidateFilterChain chain) {
        if (!Boolean.TRUE.equals(request.openToWorkOnly())) {
            return chain.proceed(candidates, request);
        }
        return chain.proceed(candidates.stream().filter(Candidate::isOpenToWork).toList(), request);
    }
}
EOF

cat > "$J/pipeline/NoticePeriodFilterHandler.java" <<'EOF'
package com.example.jobsearch.pipeline;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
@Order(30)
public class NoticePeriodFilterHandler implements CandidateFilterHandler {

    @Override
    public List<Candidate> handle(List<Candidate> candidates, RecruiterSearchRequest request, CandidateFilterChain chain) {
        Integer max = request.maxNoticePeriodDays();
        if (max == null) {
            return chain.proceed(candidates, request);
        }
        List<Candidate> filtered = candidates.stream()
                .filter(c -> c.isImmediateJoiner() || (c.getNoticePeriodDays() != null && c.getNoticePeriodDays() <= max))
                .toList();
        return chain.proceed(filtered, request);
    }
}
EOF

cat > "$J/pipeline/RecruiterSearchPipeline.java" <<'EOF'
package com.example.jobsearch.pipeline;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.RecruiterSearch;
import com.example.jobsearch.dto.CandidateSearchResultDTO;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import com.example.jobsearch.dto.SearchResponse;
import com.example.jobsearch.l1.L1CandidateRetrievalService;
import com.example.jobsearch.l2.L2RerankingEngine;
import com.example.jobsearch.l2.ScoredCandidate;
import com.example.jobsearch.l2.ScoringContext;
import com.example.jobsearch.l2.SkillCompanionMatrix;
import com.example.jobsearch.query.BooleanQueryParserService;
import com.example.jobsearch.query.QueryNode;
import com.example.jobsearch.query.TermNormalizer;
import com.example.jobsearch.repository.RecruiterSearchRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;

/** Orchestrates: parse -> L1 retrieval -> filter chain -> L2 rerank -> page -> audit. */
@Slf4j
@Service
public class RecruiterSearchPipeline {

    private final BooleanQueryParserService parser;
    private final L1CandidateRetrievalService l1;
    private final List<CandidateFilterHandler> filterHandlers;
    private final L2RerankingEngine l2;
    private final SkillCompanionMatrix matrix;
    private final SearchProperties properties;
    private final RecruiterSearchRepository searchRepository;

    public RecruiterSearchPipeline(BooleanQueryParserService parser,
                                   L1CandidateRetrievalService l1,
                                   List<CandidateFilterHandler> filterHandlers,
                                   L2RerankingEngine l2,
                                   SkillCompanionMatrix matrix,
                                   SearchProperties properties,
                                   RecruiterSearchRepository searchRepository) {
        this.parser = parser;
        this.l1 = l1;
        this.filterHandlers = filterHandlers;
        this.l2 = l2;
        this.matrix = matrix;
        this.properties = properties;
        this.searchRepository = searchRepository;
    }

    public SearchResponse execute(RecruiterSearchRequest request) {
        long start = System.nanoTime();
        String searchId = UUID.randomUUID().toString();
        log.info("Search {} started: query='{}'", searchId, request.query());

        QueryNode ast = parser.parse(request.query());
        Set<String> queriedSkills = deriveQueriedSkills(ast, request);

        L1CandidateRetrievalService.L1Result l1Result = l1.retrieve(ast);
        List<Candidate> filtered = new CandidateFilterChain(filterHandlers).proceed(l1Result.candidates(), request);

        List<Candidate> forRerank = filtered.stream()
                .sorted(Comparator.comparing(Candidate::getProfileUpdatedAt,
                        Comparator.nullsLast(Comparator.reverseOrder())))
                .limit(properties.getL2MaxCandidates())
                .toList();

        List<ScoredCandidate> ranked = l2.rerank(forRerank, new ScoringContext(queriedSkills, Instant.now()));
        List<CandidateSearchResultDTO> results = ranked.stream()
                .limit(request.effectivePageSize())
                .map(s -> toDto(s, queriedSkills))
                .toList();

        long tookMs = (System.nanoTime() - start) / 1_000_000;
        audit(request, results.size(), tookMs);
        log.info("Search {} finished: l1={}, filtered={}, returned={}, tookMs={}",
                searchId, l1Result.totalMatches(), filtered.size(), results.size(), tookMs);
        return new SearchResponse(searchId, l1Result.totalMatches(), filtered.size(), tookMs, results);
    }

    private Set<String> deriveQueriedSkills(QueryNode ast, RecruiterSearchRequest request) {
        Set<String> skills = new LinkedHashSet<>();
        request.skillsOrEmpty().forEach(s -> skills.add(TermNormalizer.normalize(s)));
        Set<String> terms = new LinkedHashSet<>();
        ast.collectPositiveTerms(terms);
        terms.stream().filter(matrix::isKnownSkill).forEach(skills::add);
        skills.remove("");
        return skills;
    }

    private CandidateSearchResultDTO toDto(ScoredCandidate s, Set<String> queriedSkills) {
        Candidate c = s.candidate();
        List<String> matched = c.getSkills().stream()
                .filter(skill -> queriedSkills.contains(TermNormalizer.normalize(skill)))
                .sorted()
                .toList();
        return new CandidateSearchResultDTO(c.getId(), c.getFullName(), c.getHeadline(), c.getCurrentCompany(),
                c.getCurrentTitle(), c.getLocation(), c.isOpenToWork(), s.score(), s.breakdown(), matched);
    }

    private void audit(RecruiterSearchRequest request, int resultCount, long tookMs) {
        try {
            searchRepository.save(RecruiterSearch.builder()
                    .recruiterId(request.recruiterId())
                    .rawQuery(request.query())
                    .resultCount(resultCount)
                    .tookMs(tookMs)
                    .createdAt(Instant.now())
                    .build());
        } catch (RuntimeException e) {
            log.warn("Failed to persist search audit record: {}", e.getMessage());
        }
    }
}
EOF

# ---------------------------------------------------------------- business services
cat > "$J/service/ProfileIngestionService.java" <<'EOF'
package com.example.jobsearch.service;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.CandidateUpsertRequest;
import com.example.jobsearch.exception.ResourceNotFoundException;
import com.example.jobsearch.l1.L1CandidateRetrievalService;
import com.example.jobsearch.repository.CandidateRepository;
import com.example.jobsearch.util.TxUtils;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.HashSet;

@Slf4j
@Service
@RequiredArgsConstructor
public class ProfileIngestionService {

    private final CandidateRepository candidateRepository;
    private final L1CandidateRetrievalService l1;

    @Transactional
    public Candidate create(CandidateUpsertRequest request) {
        return save(new Candidate(), request);
    }

    @Transactional
    public Candidate update(Long id, CandidateUpsertRequest request) {
        Candidate existing = candidateRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Candidate " + id + " not found"));
        return save(existing, request);
    }

    @Transactional(readOnly = true)
    public Candidate get(Long id) {
        return candidateRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Candidate " + id + " not found"));
    }

    private Candidate save(Candidate c, CandidateUpsertRequest r) {
        c.setFullName(r.fullName());
        c.setHeadline(r.headline());
        c.setCurrentCompany(r.currentCompany());
        c.setCurrentTitle(r.currentTitle());
        c.setLocation(r.location());
        c.setOpenToWork(r.openToWork());
        c.setImmediateJoiner(r.immediateJoiner());
        c.setNoticePeriodDays(r.noticePeriodDays());
        c.setSkills(r.skills() == null ? new HashSet<>() : new HashSet<>(r.skills()));
        c.setProfileUpdatedAt(Instant.now());
        if (c.getLastActiveAt() == null) {
            c.setLastActiveAt(Instant.now());
        }
        Candidate saved = candidateRepository.save(c);
        TxUtils.afterCommit(() -> l1.indexCandidate(saved));
        log.info("Ingested candidate {}", saved.getId());
        return saved;
    }
}
EOF

cat > "$J/service/JobPostingService.java" <<'EOF'
package com.example.jobsearch.service;

import com.example.jobsearch.domain.JobPosting;
import com.example.jobsearch.dto.JobPostingRequest;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import com.example.jobsearch.dto.SearchResponse;
import com.example.jobsearch.exception.ResourceNotFoundException;
import com.example.jobsearch.pipeline.RecruiterSearchPipeline;
import com.example.jobsearch.repository.JobPostingRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.HashSet;
import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class JobPostingService {

    private final JobPostingRepository repository;
    private final RecruiterSearchPipeline pipeline;

    @Transactional
    public JobPosting create(JobPostingRequest r) {
        return repository.save(JobPosting.builder()
                .title(r.title())
                .company(r.company())
                .location(r.location())
                .description(r.description())
                .minExperienceYears(r.minExperienceYears())
                .recruiterId(r.recruiterId())
                .requiredSkills(new HashSet<>(r.requiredSkills()))
                .postedAt(Instant.now())
                .active(true)
                .build());
    }

    @Transactional(readOnly = true)
    public JobPosting get(Long id) {
        return repository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Job posting " + id + " not found"));
    }

    /** Job -> candidates: OR over required skills for recall, L2 skill-companion scoring for precision. */
    public SearchResponse matchCandidates(Long jobId, int size) {
        JobPosting job = get(jobId);
        String query = job.getRequiredSkills().stream()
                .map(s -> "\"" + s.replace("\"", "") + "\"")
                .collect(Collectors.joining(" OR "));
        RecruiterSearchRequest request = new RecruiterSearchRequest(
                query, List.copyOf(job.getRequiredSkills()), job.getLocation(), null, null, size, job.getRecruiterId());
        return pipeline.execute(request);
    }
}
EOF

# ---------------------------------------------------------------- events (Observer pattern)
cat > "$J/event/EngagementObserver.java" <<'EOF'
package com.example.jobsearch.event;

import com.example.jobsearch.dto.EngagementEvent;
import com.example.jobsearch.dto.EngagementType;

/** Observer Pattern: observers subscribe to engagement events by type. */
public interface EngagementObserver {
    boolean supports(EngagementType type);

    void onEvent(EngagementEvent event);
}
EOF

cat > "$J/event/EngagementEventDispatcher.java" <<'EOF'
package com.example.jobsearch.event;

import com.example.jobsearch.dto.EngagementEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.List;

/** Subject of the Observer pattern. */
@Slf4j
@Component
@RequiredArgsConstructor
public class EngagementEventDispatcher {

    private final List<EngagementObserver> observers;

    public void dispatch(EngagementEvent event) {
        for (EngagementObserver observer : observers) {
            if (observer.supports(event.type())) {
                observer.onEvent(event);
            }
        }
        log.debug("Dispatched {} for candidate {}", event.type(), event.candidateId());
    }
}
EOF

cat > "$J/event/InMailFeatureObserver.java" <<'EOF'
package com.example.jobsearch.event;

import com.example.jobsearch.domain.InMailInteraction;
import com.example.jobsearch.dto.EngagementEvent;
import com.example.jobsearch.dto.EngagementType;
import com.example.jobsearch.repository.InMailInteractionRepository;
import com.example.jobsearch.service.FeatureStoreService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Duration;
import java.time.Instant;

/** Maintains InMail counters and the running average response time in the L2 feature store. Idempotent. */
@Slf4j
@Component
@RequiredArgsConstructor
public class InMailFeatureObserver implements EngagementObserver {

    private final InMailInteractionRepository interactions;
    private final FeatureStoreService featureStore;

    @Override
    public boolean supports(EngagementType type) {
        return type == EngagementType.INMAIL_SENT || type == EngagementType.INMAIL_RESPONDED;
    }

    @Override
    @Transactional
    public void onEvent(EngagementEvent event) {
        if (event.messageId() == null || event.messageId().isBlank()) {
            throw new IllegalArgumentException("messageId is required for " + event.type());
        }
        Instant at = event.occurredAt() != null ? event.occurredAt() : Instant.now();
        if (event.type() == EngagementType.INMAIL_SENT) {
            onSent(event, at);
        } else {
            onResponded(event, at);
        }
    }

    private void onSent(EngagementEvent event, Instant at) {
        if (interactions.findByMessageId(event.messageId()).isPresent()) {
            log.debug("Duplicate INMAIL_SENT for {} ignored", event.messageId());
            return;
        }
        interactions.save(InMailInteraction.builder()
                .messageId(event.messageId())
                .candidateId(event.candidateId())
                .recruiterId(event.recruiterId())
                .sentAt(at)
                .build());
        featureStore.update(event.candidateId(), f -> f.setInMailsReceived(f.getInMailsReceived() + 1));
    }

    private void onResponded(EngagementEvent event, Instant at) {
        InMailInteraction interaction = interactions.findByMessageId(event.messageId()).orElse(null);
        if (interaction == null) {
            log.warn("INMAIL_RESPONDED for unknown message {}", event.messageId());
            return;
        }
        if (interaction.getRespondedAt() != null) {
            log.debug("Duplicate INMAIL_RESPONDED for {} ignored", event.messageId());
            return;
        }
        interaction.setRespondedAt(at);
        interactions.save(interaction);
        final double hours = Math.max(0.0, Duration.between(interaction.getSentAt(), at).toMinutes() / 60.0);
        featureStore.update(event.candidateId(), f -> {
            int n = f.getInMailsResponded() + 1;
            f.setAvgResponseHours((f.getAvgResponseHours() * (n - 1) + hours) / n);
            f.setInMailsResponded(n);
        });
    }
}
EOF

cat > "$J/event/SessionActivityObserver.java" <<'EOF'
package com.example.jobsearch.event;

import com.example.jobsearch.dto.EngagementEvent;
import com.example.jobsearch.dto.EngagementType;
import com.example.jobsearch.repository.CandidateRepository;
import com.example.jobsearch.service.FeatureStoreService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;

@Component
@RequiredArgsConstructor
public class SessionActivityObserver implements EngagementObserver {

    private final FeatureStoreService featureStore;
    private final CandidateRepository candidates;

    @Override
    public boolean supports(EngagementType type) {
        return type == EngagementType.SESSION_ACTIVITY || type == EngagementType.PROFILE_VIEWED;
    }

    @Override
    @Transactional
    public void onEvent(EngagementEvent event) {
        final double increment = event.type() == EngagementType.SESSION_ACTIVITY ? 1.0 : 0.25;
        featureStore.update(event.candidateId(), f -> f.setSessionActivity(f.getSessionActivity() + increment));
        if (event.type() == EngagementType.SESSION_ACTIVITY) {
            candidates.findById(event.candidateId()).ifPresent(c -> c.setLastActiveAt(Instant.now()));
        }
    }
}
EOF

cat > "$J/event/CandidateEngagementKafkaConsumer.java" <<'EOF'
package com.example.jobsearch.event;

import com.example.jobsearch.dto.EngagementEvent;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Slf4j
@Component
@RequiredArgsConstructor
public class CandidateEngagementKafkaConsumer {

    private final EngagementEventDispatcher dispatcher;

    @KafkaListener(topics = "${app.kafka.engagement-topic}",
            groupId = "${app.kafka.group-id}",
            containerFactory = "kafkaListenerContainerFactory",
            autoStartup = "${app.kafka.listener-enabled:true}")
    public void consume(EngagementEvent event) {
        MDC.put("traceId", event.eventId() == null ? "kafka" : event.eventId());
        try {
            log.info("Consumed {} for candidate {}", event.type(), event.candidateId());
            dispatcher.dispatch(event);
        } finally {
            MDC.remove("traceId");
        }
    }
}
EOF

cat > "$J/event/EngagementEventPublisher.java" <<'EOF'
package com.example.jobsearch.event;

import com.example.jobsearch.dto.EngagementEvent;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.UUID;

@Slf4j
@Service
public class EngagementEventPublisher {

    private final KafkaTemplate<String, EngagementEvent> kafkaTemplate;
    private final EngagementEventDispatcher dispatcher;
    private final String topic;
    private final boolean publishToKafka;

    public EngagementEventPublisher(KafkaTemplate<String, EngagementEvent> kafkaTemplate,
                                    EngagementEventDispatcher dispatcher,
                                    @Value("${app.kafka.engagement-topic}") String topic,
                                    @Value("${app.kafka.publish-enabled:true}") boolean publishToKafka) {
        this.kafkaTemplate = kafkaTemplate;
        this.dispatcher = dispatcher;
        this.topic = topic;
        this.publishToKafka = publishToKafka;
    }

    /** Publishes to Kafka (keyed by candidateId for per-candidate ordering) or dispatches in-process. */
    public EngagementEvent publish(EngagementEvent input) {
        EngagementEvent event = new EngagementEvent(
                input.eventId() != null ? input.eventId() : UUID.randomUUID().toString(),
                input.type(), input.candidateId(), input.recruiterId(), input.messageId(),
                input.occurredAt() != null ? input.occurredAt() : Instant.now());
        if (!publishToKafka) {
            dispatcher.dispatch(event);
            return event;
        }
        kafkaTemplate.send(topic, String.valueOf(event.candidateId()), event).whenComplete((result, ex) -> {
            if (ex != null) {
                log.error("Failed to publish engagement event {}", event.eventId(), ex);
            }
        });
        return event;
    }
}
EOF

# ---------------------------------------------------------------- web + controllers + bootstrap
cat > "$J/web/TraceIdFilter.java" <<'EOF'
package com.example.jobsearch.web;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class TraceIdFilter extends OncePerRequestFilter {

    public static final String HEADER = "X-Trace-Id";

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        String traceId = request.getHeader(HEADER);
        if (traceId == null || traceId.isBlank()) {
            traceId = UUID.randomUUID().toString().substring(0, 8);
        }
        MDC.put("traceId", traceId);
        response.setHeader(HEADER, traceId);
        try {
            chain.doFilter(request, response);
        } finally {
            MDC.remove("traceId");
        }
    }
}
EOF

cat > "$J/controller/JobSearchController.java" <<'EOF'
package com.example.jobsearch.controller;

import com.example.jobsearch.domain.JobPosting;
import com.example.jobsearch.dto.JobPostingRequest;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import com.example.jobsearch.dto.SearchResponse;
import com.example.jobsearch.pipeline.RecruiterSearchPipeline;
import com.example.jobsearch.service.JobPostingService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1")
@RequiredArgsConstructor
@Tag(name = "Search", description = "Recruiter candidate search and job matching")
public class JobSearchController {

    private final RecruiterSearchPipeline pipeline;
    private final JobPostingService jobPostingService;

    @Operation(summary = "Recruiter Boolean candidate search (L1 retrieval + L2 reranking)")
    @PostMapping("/search/candidates")
    public SearchResponse searchCandidates(@Valid @RequestBody RecruiterSearchRequest request) {
        return pipeline.execute(request);
    }

    @Operation(summary = "Create a job posting")
    @PostMapping("/jobs")
    @ResponseStatus(HttpStatus.CREATED)
    public JobPosting createJob(@Valid @RequestBody JobPostingRequest request) {
        return jobPostingService.create(request);
    }

    @Operation(summary = "Get a job posting")
    @GetMapping("/jobs/{id}")
    public JobPosting getJob(@PathVariable Long id) {
        return jobPostingService.get(id);
    }

    @Operation(summary = "Rank candidates that match a job posting")
    @GetMapping("/jobs/{id}/matches")
    public SearchResponse matches(@PathVariable Long id, @RequestParam(defaultValue = "20") int size) {
        return jobPostingService.matchCandidates(id, Math.max(1, Math.min(size, 100)));
    }
}
EOF

cat > "$J/controller/CandidateController.java" <<'EOF'
package com.example.jobsearch.controller;

import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.dto.CandidateUpsertRequest;
import com.example.jobsearch.l1.L1CandidateRetrievalService;
import com.example.jobsearch.service.ProfileIngestionService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
@RequestMapping("/api/v1")
@RequiredArgsConstructor
@Tag(name = "Profiles", description = "Candidate profile ingestion and index administration")
public class CandidateController {

    private final ProfileIngestionService ingestionService;
    private final L1CandidateRetrievalService l1;

    @Operation(summary = "Create a candidate profile and index it")
    @PostMapping("/candidates")
    @ResponseStatus(HttpStatus.CREATED)
    public Candidate create(@Valid @RequestBody CandidateUpsertRequest request) {
        return ingestionService.create(request);
    }

    @Operation(summary = "Update a candidate profile and re-index it")
    @PutMapping("/candidates/{id}")
    public Candidate update(@PathVariable Long id, @Valid @RequestBody CandidateUpsertRequest request) {
        return ingestionService.update(id, request);
    }

    @Operation(summary = "Get a candidate profile")
    @GetMapping("/candidates/{id}")
    public Candidate get(@PathVariable Long id) {
        return ingestionService.get(id);
    }

    @Operation(summary = "Rebuild the L1 inverted index from the system of record")
    @PostMapping("/admin/index/rebuild")
    public Map<String, Integer> rebuild() {
        return Map.of("indexedCandidates", l1.rebuildIndex());
    }
}
EOF

cat > "$J/controller/EngagementController.java" <<'EOF'
package com.example.jobsearch.controller;

import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.dto.EngagementEvent;
import com.example.jobsearch.event.EngagementEventPublisher;
import com.example.jobsearch.service.FeatureStoreService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1")
@RequiredArgsConstructor
@Tag(name = "Engagement", description = "Engagement events feeding the L2 feature store")
public class EngagementController {

    private final EngagementEventPublisher publisher;
    private final FeatureStoreService featureStore;

    @Operation(summary = "Publish an engagement event (InMail sent/responded, session activity, profile view)")
    @PostMapping("/engagement/events")
    @ResponseStatus(HttpStatus.ACCEPTED)
    public EngagementEvent publish(@Valid @RequestBody EngagementEvent event) {
        return publisher.publish(event);
    }

    @Operation(summary = "Inspect a candidate's L2 feature set")
    @GetMapping("/candidates/{id}/features")
    public CandidateFeatureSet features(@PathVariable Long id) {
        return featureStore.get(id);
    }
}
EOF

cat > "$J/bootstrap/DataSeeder.java" <<'EOF'
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
EOF

# ---------------------------------------------------------------- tests
cat > "$T/query/BooleanQueryParserServiceTest.java" <<'EOF'
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
EOF

cat > "$T/l1/L1CandidateRetrievalServiceTest.java" <<'EOF'
package com.example.jobsearch.l1;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.query.BooleanQueryParserService;
import com.example.jobsearch.query.QueryNodeFactory;
import com.example.jobsearch.repository.CandidateRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class L1CandidateRetrievalServiceTest {

    @Mock
    private CandidateRepository repository;

    private final BooleanQueryParserService parser = new BooleanQueryParserService(new QueryNodeFactory());
    private L1CandidateRetrievalService service;
    private Candidate c1;

    @BeforeEach
    void setUp() {
        service = new L1CandidateRetrievalService(new InvertedIndex(), new CandidateTermExtractor(), repository,
                new SearchProperties());
        c1 = Candidate.builder().id(1L).fullName("A").currentCompany("JPMorgan")
                .currentTitle("Talent Acquisition Specialist").skills(Set.of("Java", "Spring Boot"))
                .openToWork(true).immediateJoiner(true).build();
        Candidate c2 = Candidate.builder().id(2L).fullName("B").currentCompany("Google")
                .currentTitle("Software Engineer").skills(Set.of("Python")).build();
        service.indexCandidate(c1);
        service.indexCandidate(c2);
    }

    @Test
    void retrievesOnlyMatchingCandidatesUsingPhraseAndFlagTerms() {
        when(repository.findAllById(List.of(1L))).thenReturn(List.of(c1));
        var result = service.retrieve(parser.parse("\"talent acquisition\" AND java AND \"immediate joiner\""));
        assertEquals(1, result.totalMatches());
        assertEquals(List.of(c1), result.candidates());
    }

    @Test
    void removedCandidatesAreNoLongerRetrievable() {
        service.removeCandidate(1L);
        var result = service.retrieve(parser.parse("java"));
        assertEquals(0, result.totalMatches());
        assertTrue(result.candidates().isEmpty());
    }
}
EOF

cat > "$T/l2/ScorersTest.java" <<'EOF'
package com.example.jobsearch.l2;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.l2.scorer.FreshnessScorer;
import com.example.jobsearch.l2.scorer.InMailResponsivenessScorer;
import com.example.jobsearch.l2.scorer.OpenToWorkScorer;
import com.example.jobsearch.l2.scorer.SkillCompanionScorer;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.time.Instant;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ScorersTest {

    private final SearchProperties props = new SearchProperties();
    private final Instant now = Instant.now();

    private ScoringContext ctx(String... skills) {
        return new ScoringContext(Set.of(skills), now);
    }

    private Candidate candidate(boolean open, boolean immediate, String... skills) {
        return Candidate.builder().id(1L).fullName("X").openToWork(open).immediateJoiner(immediate)
                .skills(Set.of(skills)).build();
    }

    private CandidateFeatureSet features(int received, int responded, double avgHours, double sessions) {
        return CandidateFeatureSet.builder().candidateId(1L).inMailsReceived(received)
                .inMailsResponded(responded).avgResponseHours(avgHours).sessionActivity(sessions).build();
    }

    @Test
    void skillScorerGivesFullCreditForDirectMatches() {
        SkillCompanionScorer scorer = new SkillCompanionScorer(new SkillCompanionMatrix(), props);
        double s = scorer.score(candidate(false, false, "Java", "Spring Boot"), features(0, 0, 0, 0),
                ctx("java", "spring boot"));
        assertEquals(1.0, s, 1e-9);
    }

    @Test
    void skillScorerGivesDiscountedCreditForCompanionSkills() {
        SkillCompanionScorer scorer = new SkillCompanionScorer(new SkillCompanionMatrix(), props);
        double s = scorer.score(candidate(false, false, "Spring Boot"), features(0, 0, 0, 0), ctx("java"));
        assertEquals(0.9 * 0.8, s, 1e-9);
    }

    @Test
    void skillScorerIsNeutralWithoutQueriedSkills() {
        SkillCompanionScorer scorer = new SkillCompanionScorer(new SkillCompanionMatrix(), props);
        assertEquals(0.5, scorer.score(candidate(false, false, "Java"), features(0, 0, 0, 0), ctx()), 1e-9);
    }

    @Test
    void responsiveCandidatesOutscoreUnresponsiveOnes() {
        InMailResponsivenessScorer scorer = new InMailResponsivenessScorer(props);
        double good = scorer.score(candidate(true, false), features(10, 9, 2, 0), ctx());
        double bad = scorer.score(candidate(true, false), features(10, 0, 0, 0), ctx());
        assertTrue(good > bad);
        assertTrue(good <= 1.0 && bad >= 0.0);
    }

    @Test
    void openToWorkScoring() {
        OpenToWorkScorer scorer = new OpenToWorkScorer(props);
        assertEquals(1.0, scorer.score(candidate(true, true), features(0, 0, 0, 0), ctx()), 1e-9);
        assertEquals(0.8, scorer.score(candidate(true, false), features(0, 0, 0, 0), ctx()), 1e-9);
        assertEquals(0.1, scorer.score(candidate(false, false), features(0, 0, 0, 0), ctx()), 1e-9);
    }

    @Test
    void freshnessDecaysWithAge() {
        FreshnessScorer scorer = new FreshnessScorer(props);
        Candidate fresh = candidate(true, false);
        fresh.setProfileUpdatedAt(now);
        fresh.setLastActiveAt(now);
        Candidate stale = candidate(true, false);
        stale.setProfileUpdatedAt(now.minus(Duration.ofDays(400)));
        stale.setLastActiveAt(now.minus(Duration.ofDays(400)));
        assertTrue(scorer.score(fresh, features(0, 0, 0, 10), ctx()) > 0.99);
        assertTrue(scorer.score(stale, features(0, 0, 0, 0), ctx()) < 0.1);
    }
}
EOF

cat > "$T/l2/L2RerankingEngineTest.java" <<'EOF'
package com.example.jobsearch.l2;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.l2.scorer.FreshnessScorer;
import com.example.jobsearch.l2.scorer.InMailResponsivenessScorer;
import com.example.jobsearch.l2.scorer.OpenToWorkScorer;
import com.example.jobsearch.l2.scorer.SkillCompanionScorer;
import com.example.jobsearch.service.FeatureStoreService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyCollection;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class L2RerankingEngineTest {

    @Mock
    private FeatureStoreService featureStore;

    private final ExecutorService executor = Executors.newVirtualThreadPerTaskExecutor();

    @AfterEach
    void tearDown() {
        executor.close();
    }

    @Test
    void ranksStrongResponsiveFreshCandidateFirst() {
        SearchProperties props = new SearchProperties();
        L2RerankingEngine engine = new L2RerankingEngine(List.of(
                new SkillCompanionScorer(new SkillCompanionMatrix(), props),
                new InMailResponsivenessScorer(props),
                new OpenToWorkScorer(props),
                new FreshnessScorer(props)), featureStore, executor);

        Instant now = Instant.now();
        Candidate strong = Candidate.builder().id(1L).fullName("Strong").openToWork(true).immediateJoiner(true)
                .skills(Set.of("Java", "Spring Boot")).profileUpdatedAt(now).lastActiveAt(now).build();
        Candidate weak = Candidate.builder().id(2L).fullName("Weak").openToWork(false)
                .skills(Set.of("Python")).profileUpdatedAt(now.minus(Duration.ofDays(400)))
                .lastActiveAt(now.minus(Duration.ofDays(400))).build();

        when(featureStore.getBatch(anyCollection())).thenReturn(Map.of(
                1L, CandidateFeatureSet.builder().candidateId(1L).inMailsReceived(10).inMailsResponded(9)
                        .avgResponseHours(2).sessionActivity(8).build(),
                2L, CandidateFeatureSet.builder().candidateId(2L).inMailsReceived(10).inMailsResponded(0).build()));

        List<ScoredCandidate> ranked = engine.rerank(List.of(weak, strong),
                new ScoringContext(Set.of("java", "spring boot"), now));

        assertEquals(2, ranked.size());
        assertEquals(1L, ranked.get(0).candidate().getId());
        assertTrue(ranked.get(0).score() > ranked.get(1).score());
        assertTrue(ranked.get(0).score() <= 1.0 && ranked.get(1).score() >= 0.0);
        assertEquals(4, ranked.get(0).breakdown().size());
    }
}
EOF

cat > "$T/pipeline/RecruiterSearchPipelineTest.java" <<'EOF'
package com.example.jobsearch.pipeline;

import com.example.jobsearch.config.SearchProperties;
import com.example.jobsearch.domain.Candidate;
import com.example.jobsearch.domain.RecruiterSearch;
import com.example.jobsearch.dto.RecruiterSearchRequest;
import com.example.jobsearch.dto.SearchResponse;
import com.example.jobsearch.l1.L1CandidateRetrievalService;
import com.example.jobsearch.l2.L2RerankingEngine;
import com.example.jobsearch.l2.ScoredCandidate;
import com.example.jobsearch.l2.SkillCompanionMatrix;
import com.example.jobsearch.query.BooleanQueryParserService;
import com.example.jobsearch.query.QueryNodeFactory;
import com.example.jobsearch.repository.RecruiterSearchRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class RecruiterSearchPipelineTest {

    @Mock
    private L1CandidateRetrievalService l1;
    @Mock
    private L2RerankingEngine l2;
    @Mock
    private RecruiterSearchRepository searchRepository;

    private Candidate candidate(long id, String location, boolean open) {
        return Candidate.builder().id(id).fullName("C" + id).location(location).openToWork(open)
                .skills(Set.of("Java")).build();
    }

    @Test
    void appliesFilterChainThenRerankThenAudits() {
        Candidate a = candidate(1L, "Mumbai", true);
        Candidate b = candidate(2L, "Pune", true);
        Candidate c = candidate(3L, "Mumbai", false);
        when(l1.retrieve(any())).thenReturn(new L1CandidateRetrievalService.L1Result(List.of(a, b, c), 3));
        when(l2.rerank(anyList(), any())).thenAnswer(inv -> {
            List<Candidate> in = inv.getArgument(0);
            return in.stream().map(x -> new ScoredCandidate(x, 0.9, Map.of("skillMatch", 0.9))).toList();
        });

        RecruiterSearchPipeline pipeline = new RecruiterSearchPipeline(
                new BooleanQueryParserService(new QueryNodeFactory()), l1,
                List.of(new LocationFilterHandler(), new OpenToWorkFilterHandler(), new NoticePeriodFilterHandler()),
                l2, new SkillCompanionMatrix(), new SearchProperties(), searchRepository);

        SearchResponse response = pipeline.execute(
                new RecruiterSearchRequest("\"java\"", List.of("Java"), "Mumbai", true, null, 10, 7L));

        assertEquals(3, response.l1Matches());
        assertEquals(1, response.afterFilters());
        assertEquals(1, response.results().size());
        assertEquals(1L, response.results().get(0).candidateId());
        assertEquals(List.of("Java"), response.results().get(0).matchedSkills());
        verify(searchRepository).save(any(RecruiterSearch.class));
    }
}
EOF

cat > "$T/event/InMailFeatureObserverTest.java" <<'EOF'
package com.example.jobsearch.event;

import com.example.jobsearch.domain.CandidateFeatureSet;
import com.example.jobsearch.domain.InMailInteraction;
import com.example.jobsearch.dto.EngagementEvent;
import com.example.jobsearch.dto.EngagementType;
import com.example.jobsearch.repository.InMailInteractionRepository;
import com.example.jobsearch.service.FeatureStoreService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.Instant;
import java.util.Optional;
import java.util.function.Consumer;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class InMailFeatureObserverTest {

    @Mock
    private InMailInteractionRepository interactions;
    @Mock
    private FeatureStoreService featureStore;

    private InMailFeatureObserver observer() {
        return new InMailFeatureObserver(interactions, featureStore);
    }

    @Test
    void respondedEventUpdatesCountersAndAverageLatency() {
        InMailInteraction interaction = InMailInteraction.builder().id(1L).messageId("m1").candidateId(5L)
                .recruiterId(2L).sentAt(Instant.parse("2026-01-01T00:00:00Z")).build();
        when(interactions.findByMessageId("m1")).thenReturn(Optional.of(interaction));
        CandidateFeatureSet features = CandidateFeatureSet.empty(5L);
        when(featureStore.update(eq(5L), any())).thenAnswer(inv -> {
            Consumer<CandidateFeatureSet> mutator = inv.getArgument(1);
            mutator.accept(features);
            return features;
        });

        observer().onEvent(new EngagementEvent("e1", EngagementType.INMAIL_RESPONDED, 5L, 2L, "m1",
                Instant.parse("2026-01-01T06:00:00Z")));

        assertEquals(1, features.getInMailsResponded());
        assertEquals(6.0, features.getAvgResponseHours(), 1e-9);
        assertNotNull(interaction.getRespondedAt());
        verify(interactions).save(interaction);
    }

    @Test
    void duplicateResponseIsIgnored() {
        InMailInteraction interaction = InMailInteraction.builder().id(1L).messageId("m1").candidateId(5L)
                .sentAt(Instant.parse("2026-01-01T00:00:00Z")).respondedAt(Instant.parse("2026-01-01T01:00:00Z")).build();
        when(interactions.findByMessageId("m1")).thenReturn(Optional.of(interaction));

        observer().onEvent(new EngagementEvent("e2", EngagementType.INMAIL_RESPONDED, 5L, 2L, "m1", Instant.now()));

        verifyNoInteractions(featureStore);
    }

    @Test
    void sentEventCreatesInteractionAndIncrementsReceived() {
        when(interactions.findByMessageId("m2")).thenReturn(Optional.empty());
        CandidateFeatureSet features = CandidateFeatureSet.empty(9L);
        when(featureStore.update(eq(9L), any())).thenAnswer(inv -> {
            Consumer<CandidateFeatureSet> mutator = inv.getArgument(1);
            mutator.accept(features);
            return features;
        });

        observer().onEvent(new EngagementEvent("e3", EngagementType.INMAIL_SENT, 9L, 2L, "m2", Instant.now()));

        assertEquals(1, features.getInMailsReceived());
        verify(interactions).save(any(InMailInteraction.class));
    }
}
EOF

# ---------------------------------------------------------------- DDL
cat > "$R/db/postgres-schema.sql" <<'EOF'
CREATE TABLE candidates (
    id                 BIGSERIAL PRIMARY KEY,
    full_name          VARCHAR(255) NOT NULL,
    headline           VARCHAR(500),
    current_company    VARCHAR(255),
    current_title      VARCHAR(255),
    location           VARCHAR(255),
    open_to_work       BOOLEAN NOT NULL DEFAULT FALSE,
    immediate_joiner   BOOLEAN NOT NULL DEFAULT FALSE,
    notice_period_days INT,
    last_active_at     TIMESTAMPTZ,
    profile_updated_at TIMESTAMPTZ
);
CREATE INDEX idx_candidates_company  ON candidates (current_company);
CREATE INDEX idx_candidates_location ON candidates (location);

CREATE TABLE candidate_skills (
    candidate_id BIGINT       NOT NULL REFERENCES candidates (id) ON DELETE CASCADE,
    skill        VARCHAR(255) NOT NULL,
    PRIMARY KEY (candidate_id, skill)
);

CREATE TABLE job_postings (
    id                   BIGSERIAL PRIMARY KEY,
    title                VARCHAR(255) NOT NULL,
    company              VARCHAR(255) NOT NULL,
    location             VARCHAR(255),
    description          VARCHAR(4000),
    min_experience_years INT,
    recruiter_id         BIGINT,
    posted_at            TIMESTAMPTZ,
    active               BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE job_required_skills (
    job_id BIGINT       NOT NULL REFERENCES job_postings (id) ON DELETE CASCADE,
    skill  VARCHAR(255) NOT NULL,
    PRIMARY KEY (job_id, skill)
);

CREATE TABLE recruiter_searches (
    id           BIGSERIAL PRIMARY KEY,
    recruiter_id BIGINT,
    raw_query    VARCHAR(2000) NOT NULL,
    result_count INT NOT NULL,
    took_ms      BIGINT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL
);

CREATE TABLE inmail_communications (
    id           BIGSERIAL PRIMARY KEY,
    message_id   VARCHAR(255) NOT NULL UNIQUE,
    candidate_id BIGINT NOT NULL,
    recruiter_id BIGINT,
    sent_at      TIMESTAMPTZ NOT NULL,
    responded_at TIMESTAMPTZ
);
CREATE INDEX idx_inmail_candidate ON inmail_communications (candidate_id);
CREATE INDEX idx_inmail_recruiter ON inmail_communications (recruiter_id);

CREATE TABLE candidate_feature_scores (
    candidate_id       BIGINT PRIMARY KEY,
    inmails_received   INT NOT NULL DEFAULT 0,
    inmails_responded  INT NOT NULL DEFAULT 0,
    avg_response_hours DOUBLE PRECISION NOT NULL DEFAULT 0,
    session_activity   DOUBLE PRECISION NOT NULL DEFAULT 0,
    updated_at         TIMESTAMPTZ
);
EOF

# ---------------------------------------------------------------- HLD / LLD document
cat > "$ROOT/docs/HLD_LLD.md" <<'EOF'
# Job Search & Recruiter Candidate Matching System: HLD and LLD

## 0. Run it
```bash
cd linkedin-job-search-engine
mvn clean test
mvn spring-boot:run          # H2 + demo data; Redis/Kafka optional (graceful degradation)
# Swagger UI: http://localhost:8080/swagger-ui.html
# No broker? run with --app.kafka.listener-enabled=false --app.kafka.publish-enabled=false
```
Try `POST /api/v1/search/candidates` with
`{"query":"\"JPMorgan\" AND (\"Talent Acquisition\" OR \"Recruiter\") AND \"Java\" AND \"Immediate Joiner\"","requiredSkills":["Java"]}`.

## 1. High-Level Design

### 1.1 Targets
100M+ members, 10M+ job posts, 50k+ QPS. Search p99 < 300 ms. Profile updates searchable in < 5 s. Availability 99.95%.

### 1.2 Architecture
```mermaid
flowchart LR
  Client[Recruiter / Member apps] --> GW[API Gateway: auth, rate limit]
  GW --> SAPI[Search/Retrieval API]
  GW --> ING[Profile Ingestion Service]
  GW --> JOBS[Job Indexing Service]
  GW --> ENG[Engagement and Response Tracker]

  ING -->|profile-updates| K[(Apache Kafka)]
  JOBS -->|job-updates| K
  ENG -->|candidate-engagement-events| K

  K --> IDX[Index Builders]
  IDX --> ES[(Elasticsearch: L1 inverted index)]
  IDX --> VEC[(Milvus/Qdrant: embeddings)]
  K --> FEAT[Feature Updaters: Observer consumers]
  FEAT --> REDIS[(Redis Cluster: feature store / L2 cache)]
  FEAT --> SQL[(PostgreSQL: system of record)]
  ING --> SQL
  JOBS --> SQL

  SAPI --> L1[L1 Fast Retrieval: Boolean + hybrid vector]
  L1 --> ES
  L1 --> VEC
  L1 --> FILT[Filter chain]
  FILT --> RR[Reranking Service L2: XGBoost / multi-factor]
  RR --> REDIS
  RR --> SAPI
```

### 1.3 Microservices
| Service | Responsibility | Scale axis |
|---|---|---|
| Profile Ingestion | Validate and persist profile changes, emit `profile-updates` | write QPS, partitioned by member id |
| Job Indexing | Persist job posts, build job documents/embeddings | job volume |
| Search/Retrieval API | Parse Boolean query, call L1, run filter chain, call L2, page results | read QPS (stateless, HPA) |
| Reranking Service | Batch-fetch features, score candidates in parallel, return ranked list | CPU; horizontal |
| Engagement & Response Tracker | Accept InMail sent/replied/session events, publish to Kafka | write QPS |

### 1.4 Dual-engine search
* **L1 (recall, milliseconds):** distributed inverted index (Elasticsearch in production; in-memory `InvertedIndex` in this code base) evaluating the Boolean AST over term postings; optional ANN vector retrieval fused by reciprocal-rank fusion. Output capped at ~2000 candidates.
* **L2 (precision, tens of ms):** multi-factor scoring (InMail responsiveness, Open-to-Work, skill-companion semantics, freshness/session activity). In production the linear scorer is replaced or blended with an XGBoost model served from the same feature vector.

### 1.5 Sequence: Recruiter Boolean query
```mermaid
sequenceDiagram
  actor R as Recruiter
  participant API as JobSearchController
  participant P as RecruiterSearchPipeline
  participant Q as BooleanQueryParser
  participant L1 as L1 Retrieval
  participant F as Filter Chain
  participant L2 as L2 Reranking Engine
  participant FS as Feature Store (Redis, SQL fallback)
  R->>API: POST /search/candidates {"JPMorgan" AND (...) AND "Java" AND "Immediate Joiner"}
  API->>P: execute(request)
  P->>Q: parse(query)
  Q-->>P: AST (And/Or/Not/Term)
  P->>L1: retrieve(AST)
  L1-->>P: candidate ids -> hydrated candidates
  P->>F: location / open-to-work / notice-period
  F-->>P: filtered candidates
  P->>L2: rerank(candidates, queriedSkills)
  L2->>FS: multiGet features
  FS-->>L2: feature sets
  L2-->>P: scored list (parallel, virtual threads)
  P-->>API: SearchResponse (top N, score breakdown)
  API-->>R: 200 OK
```

### 1.6 Sequence: Real-time feedback loop
```mermaid
sequenceDiagram
  actor C as Candidate
  participant ENG as Engagement API
  participant K as Kafka (key=candidateId)
  participant CON as CandidateEngagementKafkaConsumer
  participant D as EngagementEventDispatcher
  participant O as InMailFeatureObserver
  participant DB as PostgreSQL
  participant FS as Redis feature store
  C->>ENG: replies to InMail
  ENG->>K: INMAIL_RESPONDED(messageId)
  K->>CON: consume (ordered per candidate)
  CON->>D: dispatch(event)
  D->>O: onEvent (observer supports type)
  O->>DB: mark responded_at, row-lock feature row, update counters/avg latency
  DB-->>O: commit
  O->>FS: write-through after commit
  Note over FS: next search sees the new responsiveness within seconds
```

### 1.7 Storage, scalability, resilience
| Tier | Technology | Role | Scaling / HA |
|---|---|---|---|
| System of record | PostgreSQL | profiles, jobs, InMail log, features | shard by `candidate_id` hash (Citus/Vitess-style), 1 primary + 2 sync/async replicas per shard, PITR backups |
| L1 index | Elasticsearch | inverted index | shards by member-id hash, 2 replicas, rolling reindex via alias swap |
| Vectors | Milvus/Qdrant | skill/profile embeddings | HNSW, partitioned collections, replicas |
| L2 cache / features | Redis Cluster | `cfs:{id}` JSON, 10 min TTL | 16384 slots, replicas, cache-aside + write-through |

* **Caching:** feature store cache-aside with write-through on update; query-result cache keyed by normalised query + filters (30-60 s TTL) for hot recruiter searches; local Caffeine for matrix/config.
* **Rate limiting:** token bucket per recruiter and per IP at the gateway (Redis Lua), plus bulkheads on L2 executor.
* **Fault tolerance:** Redis outage trips a circuit breaker and reads fall back to SQL (implemented in `FeatureStoreService`); Kafka consumers retry with back-off then DLQ; L2 failure degrades to L1 order; index rebuild endpoint; idempotent event handling by `messageId`; multi-AZ deployment, region-level active-active reads.

## 2. Low-Level Design

### 2.1 Class diagram
```mermaid
classDiagram
  class JobSearchController
  class RecruiterSearchPipeline {
    +execute(RecruiterSearchRequest) SearchResponse
  }
  class BooleanQueryParserService {
    +parse(String) QueryNode
  }
  class QueryNodeFactory {
    +term(String) QueryNode
    +and(List) QueryNode
    +or(List) QueryNode
    +not(QueryNode) QueryNode
  }
  class QueryNode {
    <<interface>>
    +evaluate(PostingsSource) Set
    +collectPositiveTerms(Set)
  }
  QueryNode <|.. TermNode
  QueryNode <|.. AndNode
  QueryNode <|.. OrNode
  QueryNode <|.. NotNode
  class InvertedIndex
  class L1CandidateRetrievalService
  class CandidateFilterHandler {
    <<interface>>
  }
  CandidateFilterHandler <|.. LocationFilterHandler
  CandidateFilterHandler <|.. OpenToWorkFilterHandler
  CandidateFilterHandler <|.. NoticePeriodFilterHandler
  class CandidateFilterChain
  class L2RerankingEngine
  class CandidateScorer {
    <<interface>>
    +name() String
    +weight() double
    +score(Candidate, CandidateFeatureSet, ScoringContext) double
  }
  CandidateScorer <|.. SkillCompanionScorer
  CandidateScorer <|.. InMailResponsivenessScorer
  CandidateScorer <|.. OpenToWorkScorer
  CandidateScorer <|.. FreshnessScorer
  class SkillCompanionMatrix
  class FeatureStoreService
  class EngagementObserver {
    <<interface>>
  }
  EngagementObserver <|.. InMailFeatureObserver
  EngagementObserver <|.. SessionActivityObserver
  class EngagementEventDispatcher
  class CandidateEngagementKafkaConsumer
  JobSearchController --> RecruiterSearchPipeline
  RecruiterSearchPipeline --> BooleanQueryParserService
  BooleanQueryParserService --> QueryNodeFactory
  RecruiterSearchPipeline --> L1CandidateRetrievalService
  L1CandidateRetrievalService --> InvertedIndex
  RecruiterSearchPipeline --> CandidateFilterChain
  RecruiterSearchPipeline --> L2RerankingEngine
  L2RerankingEngine --> CandidateScorer
  SkillCompanionScorer --> SkillCompanionMatrix
  L2RerankingEngine --> FeatureStoreService
  CandidateEngagementKafkaConsumer --> EngagementEventDispatcher
  EngagementEventDispatcher --> EngagementObserver
  InMailFeatureObserver --> FeatureStoreService
```

### 2.2 Design patterns
| Pattern | Where | Why |
|---|---|---|
| Strategy | `CandidateScorer` implementations | add/replace scoring signals without touching the engine (Open/Closed) |
| Chain of Responsibility | `CandidateFilterHandler` + `CandidateFilterChain` (ordered by `@Order`) | composable L1 -> L2 filters |
| Factory | `QueryNodeFactory` | one place to normalise terms and flatten AND/OR nodes |
| Observer | `EngagementObserver` + `EngagementEventDispatcher` | new consumers of engagement events without changing the Kafka consumer |
| Composite | `QueryNode` tree | uniform evaluation of Boolean expressions |

### 2.3 L1 Boolean evaluation
Grammar (NOT > AND > OR, adjacent operands implicitly ANDed):
```
or      := and ( "OR" and )*
and     := unary ( ["AND"] unary )*
unary   := "NOT" unary | primary
primary := TERM | "(" or ")"
```
Index terms per candidate: skills, company/title/headline/location phrases and their 1-3-gram shingles, plus flag terms `immediate joiner`, `open to work`.

```
evaluate(node):
  Term(t):  postings[t]
  Or(c...): union(evaluate(ci))
  And(c...):
     P = [evaluate(ci) for ci not Not];  N = [evaluate(inner) for ci = Not(inner)]
     sort P by size ascending; result = P[0]; result ∩= P[i] (early exit when empty)
     if P empty: result = universe
     result -= each N
  Not(x):   universe - evaluate(x)
```
Complexity: O(sum of the smallest posting list sizes) for AND-heavy queries.

### 2.4 L2 scoring
$$Score = \frac{w_1 \cdot \text{SkillMatch} + w_2 \cdot \text{InMailResponseRate} + w_3 \cdot \text{OpenToWorkStatus} + w_4 \cdot \text{ProfileFreshness}}{w_1 + w_2 + w_3 + w_4}$$
Defaults: $w_1=0.40,\ w_2=0.30,\ w_3=0.20,\ w_4=0.10$ (configurable under `app.search.weights`). Each signal is in $[0,1]$, so $Score \in [0,1]$.

* **InMailResponseRate** = $0.8 \cdot \frac{r + 5 \cdot 0.3}{n + 5} + 0.2 \cdot e^{-\bar{h}/48}$ ($r$ replies, $n$ InMails received, $\bar{h}$ mean reply hours; Bayesian prior 0.3 stops tiny samples from dominating; speed term is 0.5 when there are no replies).
* **OpenToWorkStatus** = 1.0 (open + immediate joiner), 0.8 (open), 0.1 (not open).
* **ProfileFreshness** = $0.4 \cdot 2^{-d_{update}/90} + 0.3 \cdot 2^{-d_{active}/14} + 0.3 \cdot \min(1, s/10)$ where $s$ is the decayed session-activity score (nightly decay x 6/7).
* **SkillMatch**: see below.

```
rerank(candidates, ctx):
  features = featureStore.getBatch(ids)           # one Redis MGET, SQL for misses
  parallel for each candidate (virtual threads):
     breakdown[s.name] = clamp(s.score(c, features[c], ctx), 0, 1) for each scorer s
     total = sum(s.weight * breakdown[s.name]) / sum(s.weight)
  sort by total desc, tie-break by id
```

### 2.5 Semantic skill companion matrix
`SkillCompanionMatrix` stores symmetric affinities $A[a][b] \in [0,1]$ (for example Java-Spring Boot 0.90, Spring Boot-Microservices 0.85, Microservices-Rate Limiting 0.60). Queried skills $Q$ come from the request's `requiredSkills` plus positive query terms that are known skills.
$$\text{SkillMatch} = \frac{1}{|Q|}\sum_{q \in Q}\begin{cases}1 & q \in S_c\\ \delta \cdot \max_{h \in S_c} A[q][h] & \text{otherwise}\end{cases}$$
with $S_c$ the candidate's skills and $\delta = 0.8$ (`companion-discount`). A candidate with `Spring Boot` but not `Java` therefore earns 0.72 for `Java`, while one with an unrelated stack earns 0. In production the matrix is learned offline (skill co-occurrence / embedding cosine) and loaded from the feature platform.

## 3. Database schema (PostgreSQL DDL)
EOF
{ echo '```sql'; cat "$R/db/postgres-schema.sql"; echo '```'; } >> "$ROOT/docs/HLD_LLD.md"

# ---------------------------------------------------------------- zip
cp "$0" "$ROOT/build_project.sh" 2>/dev/null || true
if command -v zip >/dev/null 2>&1; then
  zip -qr "$ROOT.zip" "$ROOT"
else
  python3 -m zipfile -c "$ROOT.zip" "$ROOT"
fi
echo "Created $ROOT.zip"
