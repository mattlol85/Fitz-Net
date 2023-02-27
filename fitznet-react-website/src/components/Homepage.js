import React from 'react';
import { Link } from 'react-router-dom';

function Homepage() {
    return (
        <div>
            
                <section className="hero">
                <div className="hero-content">
                    <h1>Welcome to your Home-Lab</h1>
                    <p>Build your own personal lab environment for learning, testing and experimenting with technology.</p>
                    <Link to="/get-started" className="button">Get started</Link>
                </div>
            </section>
            <section className="features">
                <div className="feature">
                    <h2>Flexibility</h2>
                    <p>Design and configure your lab environment to meet your specific needs and requirements.</p>
                </div>
                <div className="feature">
                    <h2>Cost savings</h2>
                    <p>Save money by building your own lab environment instead of paying for cloud-based solutions or renting dedicated hardware.</p>
                </div>
                <div className="feature">
                    <h2>Learning opportunities</h2>
                    <p>Experiment with new technologies and learn new skills in a safe and controlled environment.</p>
                </div>
            </section>
            <section className="testimonials">
                <h2>What our users are saying</h2>
                <div className="testimonial">
                    <p>"I built my own home-lab using Fitz-Net and it has been a game-changer for my learning and experimentation. The platform is easy to use and has saved me a lot of money."</p>
                    <p>- Jane Doe, Home-Lab user</p>
                </div>
            </section>
        </div>
    );
}

export default Homepage;
