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
