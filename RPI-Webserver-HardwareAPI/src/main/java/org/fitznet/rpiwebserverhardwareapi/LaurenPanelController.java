package org.fitznet.rpiwebserverhardwareapi;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.diozero.devices.LED;
import com.diozero.api.RuntimeIOException;

@RestController
@RequestMapping("/laurenpanel")
public class LaurenPanelController {

    private final LED redLed = new LED(13);
    private final LED greenLed = new LED(26);
    private final LED blueLed = new LED(16);
    private final LED yellowLed = new LED(12);

    @GetMapping("/hungry")
    public String getHungry() {
        try {
            redLed.blink(0.5f,0.5f,5,true);
            return "I am hungry!";
        } catch (RuntimeIOException e) {
            return "Error toggling LED: " + e.getMessage();
        }
    }

    @GetMapping("/love")
    public String getLove() {
        try {
            greenLed.blink(0.5f,0.5f,5,true);
            return "I love you!";
        } catch (RuntimeIOException e) {
            return "Error toggling LED: " + e.getMessage();
        }
    }

    @GetMapping("/sad")
    public String getSad() {
        try {
            blueLed.blink(0.5f,0.5f,5,true);
            return "I am sad.";
        } catch (Exception e) {
            return "Error toggling LED: " + e.getMessage();
        }
    }

    @GetMapping("/happy")
    public String getHappy() {
        try {
            yellowLed.blink(0.5f,0.5f,5,true);
            return "I am happy!";
        } catch (RuntimeIOException e) {
            return "Error toggling LED: " + e.getMessage();
        }
    }
}
