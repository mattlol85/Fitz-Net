package org.fitznet.rpiwebserverhardwareapi.devices;

import com.diozero.api.PwmOutputDevice;
import com.diozero.api.RuntimeIOException;

public class MusicalBuzzer extends PwmOutputDevice {

    public MusicalBuzzer(int gpioNumber) throws RuntimeIOException {
        super(gpioNumber);
    }

    public void playTone(int frequency, int duration) throws RuntimeIOException {
        this.setPwmFrequency(frequency);
        this.on(); // turns on the device

        // create a new thread to turn off the PWM signal after a specified duration
        new Thread(() -> {
            try {
                Thread.sleep(duration);
                this.off(); // turns off the device
            } catch (Exception e) {
                e.printStackTrace();
            }
        }).start();
    }
}
