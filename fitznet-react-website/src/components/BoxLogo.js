import React from 'react';
import logo from '../img/FN_Logo_Animation_nonloop.gif';
import '../css/BoxLogo.css';

function BoxLogo() {
  return (
    <div>
      <img src={logo} alt="Logo" className="logo" />
    </div>
  );
}

export default BoxLogo;