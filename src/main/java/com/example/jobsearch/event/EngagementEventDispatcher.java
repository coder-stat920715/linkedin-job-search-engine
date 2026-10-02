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
