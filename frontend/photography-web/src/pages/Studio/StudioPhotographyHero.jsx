import { useEffect, useMemo, useRef, useState } from "react";
import { resolvePortfolioImageUrl } from "../../services/studioPortfolioService";
import "./StudioPhotographyHero.css";

const AUTOPLAY_DELAY_MS = 4000;

function useMediaQuery(query) {
  const [matches, setMatches] = useState(() => window.matchMedia(query).matches);
  useEffect(() => {
    const media = window.matchMedia(query);
    const update = () => setMatches(media.matches);
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, [query]);
  return matches;
}

function selectPhotos(portfolio) {
  const photos = [];
  const seen = new Set();
  for (const album of Array.isArray(portfolio) ? portfolio : []) {
    if (!album) continue;
    const images = Array.isArray(album.images) && album.images.length
      ? [...album.images].filter(Boolean).sort((a, b) => (a.displayOrder ?? 0) - (b.displayOrder ?? 0))
      : [{ imageUrl: album.imageUrl }];
    for (const image of images) {
      if (typeof image.imageUrl !== "string" || !image.imageUrl.trim()) continue;
      const url = resolvePortfolioImageUrl(image.imageUrl.trim());
      if (seen.has(url)) continue;
      seen.add(url);
      photos.push({ url, title: album.title?.trim() || "Portfolio photograph", category: album.category });
    }
  }
  return photos;
}

function placement(index, active, count, compact) {
  const offset = (index - active + count) % count;
  if (offset === 0) return "center";
  if (offset === 1) return "right";
  if (offset === count - 1) return "left";
  if (!compact && offset === 2) return "back-right";
  if (!compact && offset === count - 2) return "back-left";
  return "away";
}

function HeroComposition({ photos, children }) {
  const hero = useRef(null);
  const frame = useRef(null);
  const [{ active, previous }, setSlide] = useState({ active: 0, previous: 0 });
  const [hovered, setHovered] = useState(false);
  const [paused, setPaused] = useState(false);
  const [hidden, setHidden] = useState(() => document.hidden);
  const [failed, setFailed] = useState([]);
  const reduced = useMediaQuery("(prefers-reduced-motion: reduce)");
  const mouse = useMediaQuery("(hover: hover) and (pointer: fine)");
  const compact = useMediaQuery("(max-width: 700px)");
  const stopped = hovered || paused || hidden;
  const count = photos.length;
  const moveTo = (next) => setSlide((current) => ({ previous: current.active, active: (next + count) % count }));

  useEffect(() => {
    if (stopped || count < 2) return;
    const timer = window.setInterval(() => {
      setSlide((current) => ({ previous: current.active, active: (current.active + 1) % count }));
    }, AUTOPLAY_DELAY_MS);
    return () => window.clearInterval(timer);
  }, [stopped, count]);

  useEffect(() => {
    const update = () => setHidden(document.hidden);
    document.addEventListener("visibilitychange", update);
    return () => { document.removeEventListener("visibilitychange", update); window.cancelAnimationFrame(frame.current); };
  }, []);

  useEffect(() => {
    // Only warm the next entering layer, not the whole portfolio.
    if (count < 2 || hidden) return;
    const next = new Image();
    next.src = photos[(active + (compact ? 2 : 3)) % count].url;
  }, [active, compact, count, hidden, photos]);

  const resetPointer = () => {
    window.cancelAnimationFrame(frame.current);
    hero.current?.style.setProperty("--hero-mouse-x", "0px");
    hero.current?.style.setProperty("--hero-mouse-y", "0px");
  };
  const pointerMove = (event) => {
    if (!mouse || compact || reduced || event.pointerType !== "mouse") return;
    const bounds = event.currentTarget.getBoundingClientRect();
    const x = (event.clientX - bounds.left) / bounds.width - 0.5;
    const y = (event.clientY - bounds.top) / bounds.height - 0.5;
    window.cancelAnimationFrame(frame.current);
    frame.current = window.requestAnimationFrame(() => {
      hero.current?.style.setProperty("--hero-mouse-x", `${x * 20}px`);
      hero.current?.style.setProperty("--hero-mouse-y", `${y * 14}px`);
    });
  };
  const backgroundIndex = (index) => index;
  const backgrounds = [...new Set([backgroundIndex(previous), backgroundIndex(active)])];
  const fail = (url) => setFailed((current) => current.includes(url) ? current : [...current, url]);

  return <section ref={hero} className={`studio-cinema-hero${stopped ? " is-paused" : ""}`} aria-label="Studio photography showcase" aria-roledescription="carousel"
    onPointerMove={pointerMove} onPointerEnter={(event) => { if (event.pointerType === "mouse") setHovered(true); }}
    onPointerLeave={() => { setHovered(false); resetPointer(); }}
    onKeyDown={(event) => { if (count > 1 && ["ArrowLeft", "ArrowRight"].includes(event.key)) { event.preventDefault(); moveTo(active + (event.key === "ArrowRight" ? 1 : -1)); } }}>
    <div className="cinema-background" aria-hidden="true">{backgrounds.map((index) => !failed.includes(photos[index].url) && <div key={photos[index].url} className={`cinema-background-slide${index === backgroundIndex(active) ? " is-current" : ""}`}><img src={photos[index].url} alt="" decoding="async" onError={() => fail(photos[index].url)} /></div>)}</div>
    <div className="cinema-shade" />
    <div className="cinema-copy">{children}</div>
    <div className="cinema-stage" aria-live="off">
      {photos.map((photo, index) => {
        const role = placement(index, active, count, compact);
        const wasVisible = placement(index, previous, count, compact) !== "away";
        return <div key={photo.url} className={`cinema-layer cinema-layer-${role}`} aria-hidden={index !== active}>
          <div className="cinema-parallax"><figure className="cinema-photo">
            {(role !== "away" || wasVisible) && (failed.includes(photo.url) ? <div className="cinema-photo-error">Photo unavailable</div> : <img src={photo.url} alt={photo.title} decoding="async" onError={() => fail(photo.url)} />)}
            <figcaption>{photo.title}</figcaption>
          </figure></div>
        </div>;
      })}
    </div>
    <div className="cinema-footer"><a href="/studio/portfolio" className="cinema-portfolio-link">Your portfolio <span aria-hidden="true">↗</span></a>
      {count > 1 && <div className="cinema-controls">
        <div className="cinema-dots" aria-label="Choose photograph">{photos.map((photo, index) => <button key={photo.url} type="button" aria-label={`Show ${photo.title}, photograph ${index + 1}`} aria-current={active === index ? "true" : undefined} onClick={() => moveTo(index)} />)}</div>
        {!reduced && <button type="button" className="cinema-control" aria-label={paused ? "Play slideshow" : "Pause slideshow"} aria-pressed={paused} onClick={() => setPaused((value) => !value)}>{paused ? <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 6 9 6-9 6Z" /></svg> : <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 6v12M15 6v12" /></svg>}</button>}
        <button type="button" className="cinema-control" aria-label="Previous photograph" onClick={() => moveTo(active - 1)}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m14 6-6 6 6 6" /></svg></button>
        <button type="button" className="cinema-control" aria-label="Next photograph" onClick={() => moveTo(active + 1)}><svg viewBox="0 0 24 24" aria-hidden="true"><path d="m10 6 6 6-6 6" /></svg></button>
      </div>}
    </div>
    <span className="cinema-sr-only" aria-live={stopped ? "polite" : "off"}>{photos[active].title}, photograph {active + 1} of {count}</span>
  </section>;
}

export default function StudioPhotographyHero({ profile, profileLoading, profileError, portfolio, portfolioLoading, portfolioError }) {
  const photos = useMemo(() => selectPhotos(portfolio), [portfolio]);
  const welcome = <>
    <p className="cinema-eyebrow">Welcome back,</p>
    {profileLoading ? <h2 className="cinema-studio-name">Loading your studio…</h2> : profileError ? <><h2 className="cinema-studio-name">Your studio</h2><p role="status">{profileError}</p></> : profile?.studioName?.trim() ? <h2 className="cinema-studio-name">{profile.studioName.trim()}</h2> : <><h2 className="cinema-studio-name">Complete your Studio Profile</h2><a href="/studio/profile" className="cinema-setup-link">Set up your profile ↗</a></>}
    <p className="cinema-tagline">Showcase your work. <br />Manage your bookings.</p>
  </>;
  if (portfolioLoading || portfolioError || !photos.length) return <section className="studio-cinema-hero cinema-static" aria-label="Studio photography showcase"><div className="cinema-copy">{welcome}</div><div className="cinema-empty" role="status">
    {portfolioLoading ? <p>Loading your photography…</p> : portfolioError ? <><h3>Unable to load your portfolio</h3><p>{portfolioError}</p><a href="/studio/portfolio">Open Portfolio ↗</a></> : <><svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4" width="18" height="16" rx="2" /><circle cx="9" cy="10" r="2" /><path d="m21 15-5-5L5 20" /></svg><h3>No portfolio images yet</h3><p>Add your first portfolio to showcase your photography.</p><a href="/studio/portfolio">Add Portfolio ↗</a></>}
  </div></section>;
  return <HeroComposition key={photos.map((photo) => photo.url).join("|")} photos={photos}>{welcome}</HeroComposition>;
}
