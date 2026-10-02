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
