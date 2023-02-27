import React, { useState, useEffect, useRef } from 'react';
import '../css/GreetingMessage.css';

function GreetingMessage() {
  const [isHidden, setIsHidden] = useState(false);
  const cardRef = useRef(null);

  function handleCloseClick() {
    setIsHidden(true);
  }

  function handleClickOutside(event) {
    if (cardRef.current && !cardRef.current.contains(event.target)) {
      setIsHidden(true);
    }
  }

  useEffect(() => {
    document.addEventListener('mousedown', handleClickOutside);
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, []);

  return (
    <div id="greeting-message" className={isHidden ? 'hidden' : ''}>
      <div ref={cardRef} className="card">
        <button className="close-button" onClick={handleCloseClick}>
          X
        </button>
        <h1>Welcome to the Fitz-Net</h1>
      </div>
    </div>
  );
}

export default GreetingMessage;
