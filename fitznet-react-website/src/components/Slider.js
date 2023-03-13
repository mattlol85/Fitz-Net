import React, { useState } from "react";
import "../css/Slider.css";

const VolumeSlider = () => {
  const [value, setValue] = useState(0);
  const handleSliderChange = (event) => {
    setValue(event.target.value);
  };

  return (
    <div className="volume-slider">
      <input
        type="range"
        min="0"
        max="100"
        value={value}
        onChange={handleSliderChange}
        className="slider"
      />
      <div className="slider-value">{value}</div>
    </div>
  );
};

export default VolumeSlider;
