import React from 'react';
import Card from '../components/Card';
import '../css/LaurenPanelContent.css';

function LaurenPanelContent() {
  const cards = [
    {
      title: 'Hungry',
      description: 'Need food. Immediately',
      link: '/card1',
      buttonText: '🍗',
    },
    {
      title: 'Love',
      description: 'Send love accross the internet',
      link: '/card2',
      buttonText: '💙',
    },
    {
      title: 'Sad',
      description: 'Someone is sad today',
      link: '/card3',
      buttonText: '😥',
    },
    {
      title: 'Happy',
      description: 'Somone is happy today... I wonder who',
      link: '/card2',
      buttonText: '😊',
    },
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
    </div>
  );
}

export default LaurenPanelContent;
