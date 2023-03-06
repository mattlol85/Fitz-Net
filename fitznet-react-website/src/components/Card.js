import React from 'react';
import { Link } from 'react-router-dom';
import '../css/Card.css';

function Card(props) {
  return (
    <div className="card">
      <h2>{props.title}</h2>
      <p>{props.description}</p>
      <a href={props.link}>
        <button>{props.buttonText}</button>
      </a>
    </div>
  );
}

export default Card;
