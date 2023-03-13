import React from 'react';
import Card from '../components/Card';
import '../css/LaurenPanelContent.css';
import Slider from './Slider';

function LaurenPanelContent() {
  const cards = [
    {
      title: 'Hungry',
      description: 'Need food. Immediately',
      link: 'https://www.google.com',
      buttonText: '🍗',
    },
    {
      title: 'Love',
      description: 'Send love across the internet',
      link: 'https://www.google.com',
      buttonText: '💙',
    },
    {
      title: 'Sad',
      description: 'Someone is sad today',
      link: 'https://www.google.com',
      buttonText: '😥',
    },
    {
      title: 'Happy',
      description: 'Somone is happy today... I wonder who',
      link: 'https://www.google.com',
      buttonText: '😊',
    },
    {
    title: 'Bored',
    description: 'Bored Bored Bored',
    link: 'https://www.google.com',
    buttonText: '😑',
  }
  ];

  return (
    <div className="dashboard">
      <div className="card-container">
        {cards.map((card) => (
          <Card
            key={card.title}
            title={card.title}
            description={card.description}
            link={card.link}
            buttonText={card.buttonText}
          />
        ))}
      </div>
      <div className="slider-contianer">
          <Slider></Slider>
        </div>
    </div>
  );
}

export default LaurenPanelContent;
