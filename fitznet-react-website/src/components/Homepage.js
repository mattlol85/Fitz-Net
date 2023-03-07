import React from 'react';
import '../css/Homepage.css';
import Logo from './LongBoxLogo';

function Homepage() {
  return (
    <div className="homepage-container">
      <h1 className="homepage-title"><Logo/></h1>
    </div>
  );
}

export default Homepage;