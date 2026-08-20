import { useState } from "react";
import Header from "./components/common/Header";
import Footer from "./components/common/Footer";
import Button from "./components/common/Button";
import Card from "./components/common/Card";
import "./App.css";

const featureCards = [
  { number: "01", title: "Discover", text: "Browse a thoughtful collection of talented photographers." },
  { number: "02", title: "Match", text: "Use intelligent recommendations to find your perfect fit." },
  { number: "03", title: "Book", text: "Plan, reserve, and manage every detail with confidence." },
  { number: "04", title: "Capture", text: "Turn your best moments into images worth keeping." },
  { number: "05", title: "Relive", text: "Return to every story, beautifully delivered." },
];

function App() {
  const [activeCard, setActiveCard] = useState(2);

  const getCardStyle = (index) => {
    const rawOffset = index - activeCard;
    const offset = rawOffset > 2 ? rawOffset - featureCards.length : rawOffset < -2 ? rawOffset + featureCards.length : rawOffset;
    const positions = {
      "-2": { x: "-285px", y: "32px", rotate: "-24deg", z: 1, scale: 0.92 },
      "-1": { x: "-145px", y: "10px", rotate: "-12deg", z: 2, scale: 0.97 },
      "0": { x: "0px", y: "-12px", rotate: "0deg", z: 5, scale: 1 },
      "1": { x: "145px", y: "10px", rotate: "12deg", z: 2, scale: 0.97 },
      "2": { x: "285px", y: "32px", rotate: "24deg", z: 1, scale: 0.92 },
    };
    const position = positions[String(offset)];
    return {
      "--card-x": position.x,
      "--card-y": position.y,
      "--card-rotate": position.rotate,
      "--card-scale": position.scale,
      zIndex: position.z,
    };
  };

  return (
    <>
      <Header />

      <main className="home-page">
        <section className="hero-section">
          <p className="eyebrow">FIND YOUR VISUAL STORY</p>
          <h1>Photography, made<br /><span>beautifully simple.</span></h1>
          <p className="hero-copy">Discover photographers and effortless booking experiences tailored to your most meaningful moments.</p>
          <Button>Find your photographer</Button>
        </section>
        <section className="feature-grid" aria-label="Platform highlights">
          {featureCards.map((card, index) => (
            <Card
              key={card.number}
              className={index === activeCard ? "is-active" : ""}
              style={getCardStyle(index)}
              ariaLabel={`${card.title}: ${card.text}`}
              onClick={() => setActiveCard(index)}
            >
              <span className="feature-number">{card.number}</span>
              <h2>{card.title}</h2>
              <p>{card.text}</p>
            </Card>
          ))}
        </section>
      </main>

      <Footer />
    </>
  );
}

export default App;
