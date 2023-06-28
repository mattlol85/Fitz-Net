package org.fitznet.rpiwebserverhardwareapi.dto;


import lombok.*;
import lombok.experimental.FieldDefaults;

@Builder
@Getter
@AllArgsConstructor
@NoArgsConstructor
@FieldDefaults(level = AccessLevel.PRIVATE)
public class BuzzerRequest {
    Integer frequency;
    Integer duration;
}
