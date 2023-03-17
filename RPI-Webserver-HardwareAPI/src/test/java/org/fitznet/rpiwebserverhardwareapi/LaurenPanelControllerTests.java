package org.fitznet.rpiwebserverhardwareapi;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import static org.junit.jupiter.api.Assertions.assertEquals;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
public class LaurenPanelControllerTests {

    @Autowired
    private TestRestTemplate restTemplate;

    @LocalServerPort
    private int port;

    @Test
    void testPinToggle() {
        // Test each pin and make sure it toggles
        // Test Led 1
        ResponseEntity<String> response1 = restTemplate.getForEntity("http://localhost:" + port + "/laurenpanel/hungry", String.class);
        assertEquals(HttpStatus.OK, response1.getStatusCode());
        assertEquals("I am hungry!", response1.getBody());

        // Test Led 2
        ResponseEntity<String> response2 = restTemplate.getForEntity("http://localhost:" + port + "/laurenpanel/love", String.class);
        assertEquals(HttpStatus.OK, response2.getStatusCode());
        assertEquals("I love you!", response2.getBody());

        // Test Led 3
        ResponseEntity<String> response3 = restTemplate.getForEntity("http://localhost:" + port + "/laurenpanel/sad", String.class);
        assertEquals(HttpStatus.OK, response3.getStatusCode());
        assertEquals("I am sad.", response3.getBody());

        // Test Led 4
        ResponseEntity<String> response4 = restTemplate.getForEntity("http://localhost:" + port + "/laurenpanel/happy", String.class);
        assertEquals(HttpStatus.OK, response4.getStatusCode());
        assertEquals("I am happy!", response4.getBody());
    }
}
