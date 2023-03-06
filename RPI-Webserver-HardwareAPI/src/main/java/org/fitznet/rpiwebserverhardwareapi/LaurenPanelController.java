package org.fitznet.rpiwebserverhardwareapi;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/laurenpanel")
public class LaurenPanelController {
    
    @GetMapping("/hungry")
    public String getHungry() {
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
