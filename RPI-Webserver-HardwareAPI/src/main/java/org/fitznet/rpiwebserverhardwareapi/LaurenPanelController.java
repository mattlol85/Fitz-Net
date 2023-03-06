package org.fitznet.rpiwebserverhardwareapi;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import com.pi4j.io.gpio.GpioController;
import com.pi4j.io.gpio.GpioFactory;
import com.pi4j.io.gpio.GpioPinDigitalOutput;
import com.pi4j.io.gpio.PinState;
import com.pi4j.io.gpio.RaspiPin;


@RestController
@RequestMapping("/laurenpanel")
public class LaurenPanelController {

    private final GpioController gpio = GpioFactory.getInstance();
    private final GpioPinDigitalOutput hungryPin = gpio.provisionDigitalOutputPin(RaspiPin.GPIO_01, "Hungry", PinState.LOW);
    private final GpioPinDigitalOutput lovePin = gpio.provisionDigitalOutputPin(RaspiPin.GPIO_02, "Love", PinState.LOW);
    private final GpioPinDigitalOutput sadPin = gpio.provisionDigitalOutputPin(RaspiPin.GPIO_03, "Sad", PinState.LOW);
    private final GpioPinDigitalOutput happyPin = gpio.provisionDigitalOutputPin(RaspiPin.GPIO_04, "Happy",
            PinState.LOW);


    @GetMapping("/hungry")
    public String getHungry() {
        hungryPin.toggle();
        return "I am hungry!";
    }
    
    @GetMapping("/love")
    public String getLove() {
        return "I love you!";
    }
    
    @GetMapping("/sad")
    public String getSad() {
        return "I am sad.";
    }
    
    @GetMapping("/happy")
    public String getHappy() {
        return "I am happy!";
    }
}
