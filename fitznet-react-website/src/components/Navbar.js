import React from 'react';
import { Link } from 'react-router-dom';
import logo from '../img/FN_Logo_Straight.png';
import '../css/Navbar.css';

function Navbar() {
  return (
    <nav>
      <ul>
        <li>
          <Link to="/" className="logo-link">
            <img src={logo} alt="Fitz-Net Logo" className="logo-img" />
          </Link>
        </li>
        <li>
          <Link to="/laurenpanel">Lauren Panel</Link>
        </li>
        <li>
          <Link to="/info">Info</Link>
        </li>
      </ul>
    </nav>
  );
}

export default Navbar;
