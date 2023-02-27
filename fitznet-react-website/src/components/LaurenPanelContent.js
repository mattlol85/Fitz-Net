import React from 'react';
import Card from '../components/Card';
import '../css/LaurenPanelContent.css';

function LaurenPanelContent() {
  const cards = [
    {
      title: 'Card 1',
      description: 'This is the description for card 1.',
      link: '/card1',
      buttonText: 'Go to Card 1',
    },
    {
      title: 'Card 2',
      description: 'This is the description for card 2.',
      link: '/card2',
      buttonText: 'Go to Card 2',
    },
    {
      title: 'Card 3',
      description: 'This is the description for card 3.',
      link: '/card3',
      buttonText: 'Go to Card 3',
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
