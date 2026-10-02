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
