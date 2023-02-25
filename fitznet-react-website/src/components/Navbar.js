import React from 'react';
import { Link } from 'react-router-dom';
//import './css/Navbar.css  ';

function Navbar() {
  return (
    <nav>
      <ul>
        <li>
          <Link to="/home">Home</Link>
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