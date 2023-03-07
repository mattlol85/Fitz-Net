import React from 'react';
import '../css/Footer.css';


function Footer() {
  return (
    <div className="footer">
      &copy; {new Date().getFullYear()} fitznet.org by Matthew Fitzgerald
    </div>
  );
}

export default Footer;
