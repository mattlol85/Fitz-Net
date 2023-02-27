import React from 'react';
import '../css/Footer.css';


function Footer() {
  return (
    <div className="footer">
      &copy; {new Date().getFullYear()} FitzNet.org by Matthew Fitzgerald
    </div>
  );
}

export default Footer;
