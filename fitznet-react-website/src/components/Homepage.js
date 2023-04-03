import React from 'react';
import '../css/Homepage.css';
import BoxLogo from './BoxLogo';

function Homepage() {
  return (
    <div className="homepage-container">
      <h1 className="homepage-title">
        <div style={{width: ".1%", height: ".1%"}}>
          <BoxLogo />
        </div>
      </h1>
    </div>
  );
}

export default Homepage;
