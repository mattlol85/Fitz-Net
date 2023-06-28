package org.fitznet.rpiwebserverhardwareapi;

import jakarta.annotation.PreDestroy;
import org.fitznet.rpiwebserverhardwareapi.devices.MusicalBuzzer;
import org.fitznet.rpiwebserverhardwareapi.dto.BuzzerRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.*;
import com.diozero.devices.LED;
import com.diozero.api.RuntimeIOException;

@RestController
@RequestMapping("/laurenpanel")
public class LaurenPanelController {
    private static final Logger LOGGER = LoggerFactory.getLogger(LaurenPanelController.class);
    private final LED redLed = new LED(12);
    private final LED greenLed = new LED(26);
    private final LED blueLed = new LED(16);
    private final LED yellowLed = new LED(20);
    private final MusicalBuzzer buzzer = new MusicalBuzzer(13);

    @GetMapping("/hungry")
    public String getHungry() {
        try {
            LOGGER.debug("Toggling LED for hungry");
            redLed.blink(0.5f, 0.5f, 5, true);
            return "I am hungry!";
        } catch (RuntimeIOException e) {
            return "Error toggling LED: " + e.getMessage();
        }
    }

    @GetMapping("/love")
    public String getLove() {
        try {
            greenLed.blink(0.5f, 0.5f, 5, true);
            return "I love you!";
        } catch (RuntimeIOException e) {
            return "Error toggling LED: " + e.getMessage();
        }
    }

    @GetMapping("/sad")
    public String getSad() {
        try {
            blueLed.blink(0.5f, 0.5f, 5, true);
            return "I am sad.";
        } catch (Exception e) {
            return "Error toggling LED: " + e.getMessage();
        }
    }

    @GetMapping("/happy")
    public String getHappy() {
        try {
            yellowLed.blink(0.5f, 0.5f, 5, true);
            return "I am happy!";
        } catch (RuntimeIOException e) {
            return "Error toggling LED: " + e.getMessage();
        }
    }

    @GetMapping("/buzzertest")
    public String getBuzzerTest(@RequestParam int  frequency, @RequestParam int duration) {
        try {
            buzzer.playTone(frequency, duration);
            return "Buzzer test complete!";
        } catch (RuntimeIOException e) {
            return "Error toggling buzzer: " + e.getMessage();
        }
    }

    @PostMapping("/buzzertest")
    public String postBuzzerTest(@RequestBody BuzzerRequest request) {
        try {
            buzzer.playTone(request.getFrequency(), request.getDuration());
            return "Buzzer test complete!";
        } catch (RuntimeIOException e) {
            return "Error toggling buzzer: " + e.getMessage();
        }
    }

    @PreDestroy
    public void cleanup() {
        LOGGER.debug("Cleaning up resources");
        redLed.close();
        greenLed.close();
        blueLed.close();
        yellowLed.close();
        buzzer.close();
    }

}
