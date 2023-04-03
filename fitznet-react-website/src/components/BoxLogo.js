import React from 'react';
import logo from '../img/Fitz_Net_Logo.png';
import '../css/BoxLogo.css';

function BoxLogo() {
  return (
    <div>
      <img src={logo} alt="Logo" className="logo" />
    </div>
  );
}

export default BoxLogo;