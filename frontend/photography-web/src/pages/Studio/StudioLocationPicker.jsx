import { Component, useEffect, useState } from "react";
import { APIProvider, APILoadingStatus, Map, Marker, useApiLoadingStatus, useMap } from "@vis.gl/react-google-maps";
import { googleMapsApiKey, hasGoogleMapsApiKey } from "../../config/googleMaps";
import "./StudioLocationPicker.css";

const initialCenter = { lat: 7.8731, lng: 80.7718 };
const failureMessage = "The map is unavailable. You can still enter coordinates manually and save your profile.";

class MapErrorBoundary extends Component {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  render() {
    return this.state.failed ? <p role="status">{failureMessage}</p> : this.props.children;
  }
}

function SyncPosition({ latitude, longitude }) {
  const map = useMap();
  useEffect(() => {
    if (map && latitude != null && longitude != null) {
      map.panTo({ lat: latitude, lng: longitude });
    }
  }, [map, latitude, longitude]);
  return null;
}

function PickerMap({ position, onSelect }) {
  const status = useApiLoadingStatus();
  const [timedOut, setTimedOut] = useState(false);
  useEffect(() => {
    if (status === APILoadingStatus.LOADED) return;
    const timer = window.setTimeout(() => setTimedOut(true), 20000);
    return () => window.clearTimeout(timer);
  }, [status]);

  if (status === APILoadingStatus.FAILED || status === APILoadingStatus.AUTH_FAILURE ||
      (timedOut && status !== APILoadingStatus.LOADED)) {
    return <p role="status">{failureMessage}</p>;
  }
  if (status !== APILoadingStatus.LOADED) return <p role="status">Loading map...</p>;

  return (
    <div className="studio-location-map" aria-label="Select studio location on Google Maps">
      <Map
        defaultCenter={position || initialCenter}
        defaultZoom={position ? 15 : 7}
        gestureHandling="cooperative"
        disableDefaultUI
        zoomControl
        keyboardShortcuts
        clickableIcons={false}
        onClick={(event) => {
          const point = event.detail.latLng;
          if (point && Number.isFinite(point.lat) && Number.isFinite(point.lng)) {
            onSelect(point.lat.toFixed(6), point.lng.toFixed(6));
          }
        }}
      >
        <SyncPosition latitude={position?.lat} longitude={position?.lng} />
        {position && <Marker position={position} title="Selected studio location" />}
      </Map>
    </div>
  );
}

export default function StudioLocationPicker({ latitude, longitude, onSelect }) {
  const [opened, setOpened] = useState(false);
  const [mapFailed, setMapFailed] = useState(false);
  useEffect(() => {
    if (!opened || !hasGoogleMapsApiKey) return;
    // Authentication errors can arrive after the script reports a successful load.
    const previousHandler = window.gm_authFailure;
    const handleAuthFailure = () => {
      setMapFailed(true);
      if (typeof previousHandler === "function") previousHandler();
    };
    window.gm_authFailure = handleAuthFailure;
    return () => {
      if (window.gm_authFailure === handleAuthFailure) {
        window.gm_authFailure = previousHandler;
      }
    };
  }, [opened]);
  const hasCoordinates = latitude != null && longitude != null &&
    String(latitude).trim() !== "" && String(longitude).trim() !== "";
  const lat = Number(latitude);
  const lng = Number(longitude);
  const position = hasCoordinates && Number.isFinite(lat) && Number.isFinite(lng) &&
    Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? { lat, lng } : null;

  return (
    <section className="studio-location-picker" aria-label="Studio location map">
      {!hasGoogleMapsApiKey ? <p>Map selection is not configured. Enter your studio coordinates manually below.</p> : <>
        <button type="button" className="studio-location-toggle" aria-expanded={opened} onClick={() => setOpened(!opened)}>
          {opened ? "Hide map" : "Choose location on map"}
        </button>
        {opened && <>
          <p>Click the map to place your studio pin. Use Save profile to save your selection.</p>
          {!position && <p>No location selected. The initial view is only a starting point.</p>}
          {mapFailed ? <p role="status">{failureMessage}</p> : <MapErrorBoundary>
            <APIProvider apiKey={googleMapsApiKey} disableUsageAttribution onError={() => setMapFailed(true)}>
              <PickerMap position={position} onSelect={onSelect} />
            </APIProvider>
          </MapErrorBoundary>}
        </>}
      </>}
    </section>
  );
}
