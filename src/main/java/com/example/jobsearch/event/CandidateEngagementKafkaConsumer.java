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
